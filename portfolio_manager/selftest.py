"""
Offline exercise of portfolio_manager.py against a fake Binance.

Runs the whole system — valuation, HWM persistence, all five kill-switch
guards, the 4h screen, order sequencing, a full kill-switch fire and the
re-entry block — with no network, no API keys and no money at risk.

    python selftest.py        # exits 0 on success, 1 on any failure

Run this after changing any threshold or guard. It is the only way to see
the kill switch actually fire without a real 15% drawdown.
"""
import os, sys, json, math, random, shutil, tempfile

STATE = tempfile.mkdtemp(prefix="pmtest-")
os.environ.update({
    "BINANCE_API_KEY": "test", "BINANCE_SECRET": "test",
    "PM_STATE_DIR": STATE, "KILL_CONFIRM_DELAY_S": "0", "NO_COLOR": "1",
})
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import portfolio_manager as pm

PRICES = {"BTC": 60000.0, "ETH": 3000.0, "SOL": 150.0, "ADA": 0.45,
          "BNB": 550.0, "XRP": 0.6, "LINK": 15.0, "AVAX": 30.0,
          "DOGE": 0.12, "TON": 5.0, "WEIRD": 2.0}


class FakeClient:
    def __init__(self, kind):
        self.kind = kind
        self.orders = []
        self.cancelled = []
        self.markets = {}
        for a in PRICES:
            self.markets[f"{a}/USDT"] = {
                "active": True, "spot": True,
                "limits": {"amount": {"min": 0.0001}, "cost": {"min": 5.0}},
            }
        self.markets["BTC/USDT:USDT"] = {"active": True, "spot": False,
                                         "limits": {"amount": {"min": 0.001}, "cost": {"min": 5.0}}}
        # WEIRD has no tradable stable pair -> exercises the unsellable path
        del self.markets["WEIRD/USDT"]

    def load_markets(self): return self.markets
    def amount_to_precision(self, s, a): return f"{float(a):.6f}"

    def fetch_tickers(self):
        if getattr(self, "break_tickers", False):
            raise pm.ccxt.NetworkError("simulated ticker outage")
        out = {}
        for a, p in PRICES.items():
            if a == "WEIRD" and getattr(self, "hide_weird", False):
                continue
            out[f"{a}/USDT"] = {"bid": p * 0.999, "ask": p * 1.001, "last": p}
        return out

    def fetch_balance(self):
        if self.kind == "spot":
            bal = getattr(self, "balances", {"BTC": 0.05, "ETH": 1.0, "ADA": 3000.0,
                                             "WEIRD": 10.0, "USDT": 2000.0})
            return {"total": dict(bal), "free": dict(bal)}
        return {"info": {"totalMarginBalance": str(getattr(self, "margin", 1500.0))},
                "total": {"USDT": getattr(self, "margin", 1500.0)}}

    def fetch_positions(self):
        return getattr(self, "positions", [{
            "symbol": "BTC/USDT:USDT", "contracts": 0.02, "side": "long",
            "entryPrice": 62000.0, "markPrice": 60000.0, "notional": 1200.0,
            "unrealizedPnl": -40.0, "leverage": 3, "info": {"positionSide": "BOTH"},
        }])

    def fetch_open_orders(self, symbol=None):
        return getattr(self, "open_orders", [{"id": "o1", "symbol": "ADA/USDT"}])

    def cancel_order(self, oid, symbol=None): self.cancelled.append((oid, symbol))

    def create_order(self, symbol, typ, side, amount, price=None, params=None):
        self.orders.append((symbol, side, amount, params))
        return {"id": f"x{len(self.orders)}", "filled": amount, "average": 1.0, "amount": amount}

    def fetch_ohlcv(self, symbol, timeframe=None, limit=None):
        base = symbol.split("/")[0]
        p0 = PRICES.get(base, 1.0)
        rnd = random.Random(hash(base) & 0xffff)
        # ADA trends down, everything else drifts up -> deterministic-ish screen
        drift = -0.004 if base == "ADA" else 0.003
        rows, price, t = [], p0 * 0.7, 1_700_000_000_000
        for i in range(limit or 200):
            price *= (1 + drift + rnd.uniform(-0.01, 0.01))
            hi, lo = price * 1.01, price * 0.99
            rows.append([t + i * 14400000, price, hi, lo, price, 1000.0])
        return rows


class FakeExchanges:
    def __init__(self):
        self.spot = FakeClient("spot")
        self.futures = FakeClient("futures")
        self.futures_available = True


def banner(t): print(f"\n{'='*70}\n{t}\n{'='*70}")

pm.Exchanges = FakeExchanges
mgr = pm.PortfolioManager()
fails = []

def check(name, cond):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}")
    if not cond: fails.append(name)

# ---------------------------------------------------------------- valuation
banner("1. VALUATION")
snap = mgr.valuer.take()
expected = 0.05*60000 + 1*3000 + 3000*0.45 + 10*2.0 + 2000 + 1500
check(f"net worth {snap.net_worth:,.2f} == {expected:,.2f}", abs(snap.net_worth-expected) < 1)
check("futures position parsed", len(snap.positions) == 1 and snap.positions[0].side == "long")
check("stables identified", abs(snap.stable_usd - 2000) < 1)
check("snapshot trustworthy", snap.is_trustworthy)

# ---------------------------------------------------------------- hwm store
banner("2. HWM STORE")
h = mgr.store.load(); check("missing file => untrusted", not h.trusted)
h = mgr.store.observe(h, 10000.0); check("seeded to 10000", h.value == 10000.0 and h.samples == 1)
h = mgr.store.observe(mgr.store.load(), 12000.0); check("raised to 12000", h.value == 12000.0)
h = mgr.store.observe(mgr.store.load(), 9000.0)
check("peak retained on decline", h.value == 12000.0 and h.samples == 3)
(pm.HWM_FILE).write_text("{corrupt")
check("corrupt file => untrusted", not mgr.store.load().trusted)
mgr.store.save(h)

# ---------------------------------------------------------------- guards
banner("3. KILL SWITCH GUARDS")
good = mgr.valuer.take()
hwm = pm.Hwm(value=good.net_worth/0.8, samples=5, trusted=True)  # 20% drawdown
dd = (hwm.value - good.net_worth)/hwm.value
ok, res = mgr.guards.evaluate(good, hwm, dd)
for r in res: print(f"     {r.name:<14} {'PASS' if r.passed else 'HOLD'} — {r.detail}")
check(f"real {dd:.0%} drawdown fires", ok)

mgr.ex.spot.hide_weird = True   # G1: a held asset can no longer be priced
bad = mgr.valuer.take()
ok1, r1 = mgr.guards.evaluate(bad, hwm, dd)
check("G1 holds on unpriced holding", not ok1 and any(x.name.startswith("G1") and not x.passed for x in r1))
mgr.ex.spot.hide_weird = False

ok2, r2 = mgr.guards.evaluate(good, pm.Hwm(value=hwm.value, samples=1, trusted=True), dd)
check("G2 holds on fresh HWM", not ok2)
ok3, _ = mgr.guards.evaluate(good, pm.Hwm(value=hwm.value, samples=5, trusted=False), dd)
check("G2 holds on untrusted HWM", not ok3)

huge = pm.Hwm(value=good.net_worth*10, samples=9, trusted=True)   # "90% loss"
ok4, r4 = mgr.guards.evaluate(huge and good, huge, 0.9)
check("G3 holds on implausible loss", not ok4 and any(x.name.startswith("G3") and not x.passed for x in r4))

class Flaky(pm.Valuer):
    n = 0
    def take(self):
        s = super().take()
        Flaky.n += 1
        if Flaky.n >= 1:  # the confirmation read shows no drawdown
            s.futures_wallet_usd += hwm.value
        return s
ok5, r5 = pm.KillSwitchGuards(Flaky(mgr.ex)).evaluate(good, hwm, dd)
check("G4 holds when 2nd read disagrees", not ok5 and any(x.name.startswith("G4") and not x.passed for x in r5))

pm.KILL_SWITCH_ENABLED = False
ok6, _ = mgr.guards.evaluate(good, hwm, dd); check("G5 holds when disarmed", not ok6)
pm.KILL_SWITCH_ENABLED = True

# ---------------------------------------------------------------- analysis
banner("4. 4h ANALYSIS + PROPOSAL")
actions, assess = mgr.proposer.build(good)
print(f"     assessed {len(assess)} assets")
for a in sorted(assess.values(), key=lambda x: -x.score)[:4]:
    print(f"       {a.asset:<6} score {a.score:+6.1f}  rsi {a.rsi:5.1f}  7d {a.ret_7d:+.1%}")
check("assessments produced", len(assess) >= 8)
check("every score finite and in range", all(math.isfinite(a.score) and -100 <= a.score <= 100 for a in assess.values()))
check("every action has a justification", all(a.reason for a in actions))
check("ADA (downtrend) scores below BTC", assess["ADA"].score < assess["BTC"].score)
pm.print_proposal(good, mgr.store.load(), 0.03, actions, assess)

# ---------------------------------------------------------------- execution
banner("5. EXECUTION (dry-run then live-sim)")
mgr.trader.execute(mgr.ex, actions)
check("dry-run sent no orders", len(mgr.ex.spot.orders) == 0)
pm.LIVE_TRADING = True
mgr.trader.execute(mgr.ex, actions)
sells = [o for o in mgr.ex.spot.orders if o[1] == "sell"]
buys = [o for o in mgr.ex.spot.orders if o[1] == "buy"]
check(f"live-sim placed orders ({len(sells)} sell / {len(buys)} buy)", len(mgr.ex.spot.orders) == len(actions))
if sells and buys:
    check("sells sequenced before buys", mgr.ex.spot.orders.index(sells[0]) < mgr.ex.spot.orders.index(buys[0]))

# ---------------------------------------------------------------- kill fire
banner("6. KILL SWITCH FIRE (live-sim)")
mgr.ex.spot.orders.clear(); mgr.ex.futures.orders.clear()
try:
    mgr.kill.fire(good, hwm, dd)
    fails.append("kill switch did not exit")
except SystemExit as e:
    check("exited with code 2", e.code == 2)
check("cancelled spot order", ("o1", "ADA/USDT") in mgr.ex.spot.cancelled)
check("closed futures long with a sell", any(o[1] == "sell" and "USDT:USDT" in o[0] for o in mgr.ex.futures.orders))
check("reduceOnly on the close", any((o[3] or {}).get("reduceOnly") or (o[3] or {}).get("positionSide") for o in mgr.ex.futures.orders))
sold = {o[0].split("/")[0] for o in mgr.ex.spot.orders if o[1] == "sell"}
check(f"sold all risk assets {sorted(sold)}", {"BTC", "ETH", "ADA"} <= sold)
check("did not sell USDT", "USDT" not in sold)
check("left unsellable WEIRD alone", "WEIRD" not in sold)
check("sentinel written", pm.KILL_SENTINEL.exists())
check("sentinel records the drawdown", json.loads(pm.KILL_SENTINEL.read_text())["drawdown"] > 0.15)

banner("7. RE-ENTRY BLOCK")
try:
    pm.preflight(); fails.append("preflight did not block")
except SystemExit as e:
    check("startup refused with code 3", e.code == 3)

print(f"\n{'='*70}")
print(f"{len(fails)} FAILURE(S)" if fails else "ALL CHECKS PASSED")
for f in fails: print("  - " + f)
shutil.rmtree(STATE, ignore_errors=True)
sys.exit(1 if fails else 0)
