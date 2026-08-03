# Binance Portfolio Manager

A single-file Python process that values your whole Binance account (Spot +
USDⓈ-M Futures) every 4 hours, tracks a High-Water Mark, enforces a hard
maximum-drawdown kill switch, and proposes rebalancing trades that only
execute when you type `EXECUTE`.

> Education/analysis tool. Not financial advice. You are responsible for
> every order it places.

---

## 1. Install

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install ccxt pandas
```

Or from the pinned file:

```bash
pip install -r requirements.txt
```

That is the whole dependency list — `ccxt` for exchange access and `pandas`
for the indicator maths. Everything else is Python standard library.

## 2. Credentials

The script reads two environment variables and never accepts keys any other
way:

```bash
export BINANCE_API_KEY="..."
export BINANCE_SECRET="..."
```

Windows PowerShell:

```powershell
$env:BINANCE_API_KEY = "..."
$env:BINANCE_SECRET  = "..."
```

**On the API key itself:** enable *Reading* and *Spot & Margin Trading* (plus
*Futures* if you hold positions). Leave **withdrawals disabled** — nothing
here withdraws, so a key that can withdraw only adds a way to lose the
account. Bind the key to your IP if the machine has a static one.

## 3. Run

```bash
python portfolio_manager.py
```

First runs are **dry-run**: full analysis, full proposals, full kill-switch
evaluation, but no order ever reaches Binance. Watch a few cycles and check
the reported net worth against the Binance UI. When the numbers match:

```bash
export PM_LIVE_TRADING=1
python portfolio_manager.py
```

To rehearse against Binance testnet instead, use testnet keys and set
`PM_TESTNET=1`.

## 4. Verify it before you trust it

```bash
python selftest.py
```

This drives the entire system against a fake Binance — no network, no keys,
no money. It asserts the valuation maths, HWM persistence across a peak and
a decline, **each of the five kill-switch guards holding for its own
reason**, the 4h screen, sell-before-buy ordering, a complete kill-switch
fire, and the startup re-entry block. 27 checks; exits non-zero on any
failure.

Run it after changing any threshold. It is the only way to watch the kill
switch actually fire without living through a real 15% drawdown.

## 5. What each cycle does

1. **Value the account.** Bulk ticker fetch, spot balances, futures margin
   balance (including unrealised PnL) and open positions. Assets with no
   direct stable pair are priced through a BTC/ETH/BNB bridge.
2. **Update the High-Water Mark** in `hwm.json` (atomic write) and compute
   drawdown against the *prior* peak.
3. **Evaluate the kill switch** if drawdown > `MAX_DRAWDOWN_PCT`.
4. **Screen the 4h charts** for every holding plus the watchlist: EMA20/50
   structure, Wilder RSI(14), ATR%, 24h and 7d returns, and relative
   strength versus BTC. These roll into a −100…+100 score.
5. **Print the proposal** — net worth, HWM, drawdown, allocation bars,
   ranked actions with the numbers behind each one.
6. **Block on the command gate** until you type `EXECUTE` or `SKIP`.

Sells are always sent before buys, because the buys are funded by them.

## 6. The kill switch, and why it has guards

The kill switch is the only thing here that trades **without** your approval.
That is what you asked for, and it is also the most dangerous line of code in
the project — because the most likely thing to ever fire it is not a crash
but a bad API response. One delisted symbol with no ticker, one truncated
`hwm.json`, one partial balance during a Binance outage, and an unguarded
implementation market-dumps the entire account at 4am.

So five guards sit in front of the trigger. **All must pass:**

| Guard | Holds when | Stops |
|---|---|---|
| **G1 VALUATION** | any fetch failed, or a non-dust holding could not be priced | an understated net worth manufacturing a fake drawdown |
| **G2 HWM** | `hwm.json` was missing/corrupt, non-positive, or has fewer than `MIN_HWM_SAMPLES` observations | liquidating against a garbage or freshly-seeded denominator |
| **G3 PLAUSIBLE** | net worth reads below `IMPLAUSIBLE_FLOOR_PCT` (35%) of the HWM | dumping on a "you lost 90%" reading that is almost certainly a data fault |
| **G4 CONFIRMED** | a full second valuation 60s later disagrees, or the two readings differ by more than `CONFIRM_TOLERANCE` | a single bad tick reaching the market |
| **G5 ARMED** | `KILL_SWITCH_ENABLED=0` | accidental arming |

The cost of the guards in a genuine crash is `KILL_CONFIRM_DELAY_S` (60s) of
extra drawdown. The benefit is that a transient HTTP failure cannot
irreversibly liquidate your account while you sleep.

When every guard passes, the switch:

1. cancels all open spot **and** futures orders (frees locked balance first),
2. closes every futures position largest-notional-first with `reduceOnly`
   market orders (hedge mode detected via `positionSide`),
3. market-sells every non-stable spot holding above the dust threshold,
4. prints a full-width red terminal warning,
5. writes `KILL_SWITCH_FIRED.json` and exits with code 2.

**Re-entry is blocked at startup**, not just at exit: while that sentinel
file exists the script refuses to run. Delete it deliberately, after you have
looked at the account. If you leave the process under `systemd` or a
supervisor, that file is the only thing preventing an automatic restart from
walking straight back into the market.

### A judgement call that is yours, not the script's

**15% is an ordinary crypto drawdown, not a catastrophic one.** Measured
against an all-time HWM, a 15% threshold will fire — probably within months,
and most likely near a local low, after which you are in USDT and the process
is stopped. That is a legitimate capital-preservation stance, but make it
knowingly. `MAX_DRAWDOWN_PCT` is one constant, and 0.25–0.35 is a more
conventional band for a portfolio that holds altcoins.

Also worth knowing: the kill switch measures *account* drawdown, so a
leveraged futures loss and a spot decline are treated identically, and any
deposit you make raises the HWM permanently. A withdrawal will look exactly
like a loss — pause the process before you move funds out.

## 7. Configuration

Every constant can be overridden by an environment variable of the same name.

| Variable | Default | Meaning |
|---|---|---|
| `PM_LIVE_TRADING` | `0` | `1` arms real order placement |
| `PM_TESTNET` | `0` | route to Binance testnet |
| `MAX_DRAWDOWN_PCT` | `0.15` | kill-switch threshold |
| `KILL_SWITCH_ENABLED` | `1` | master disarm |
| `KILL_CONFIRM_DELAY_S` | `60` | G4 re-verification delay |
| `CONFIRM_TOLERANCE` | `0.05` | max disagreement between the two readings |
| `IMPLAUSIBLE_FLOOR_PCT` | `0.35` | below this fraction of HWM = data fault |
| `MIN_HWM_SAMPLES` | `2` | observations before the HWM can trigger |
| `CYCLE_HOURS` | `4` | analysis cadence |
| `TIMEFRAME` | `4h` | OHLCV timeframe |
| `WATCHLIST` | majors | extra buy candidates, comma-separated |
| `MAX_POSITION_PCT` | `0.30` | per-asset concentration cap on buys |
| `TRIM_FRACTION` | `0.50` | fraction of a weak holding sold per cycle |
| `MIN_STABLE_RESERVE_PCT` | `0.10` | stables never spent below this |
| `WEAK_SCORE` / `STRONG_SCORE` | `-25` / `35` | trim and add thresholds |
| `MIN_ORDER_USD` | `12` | skip orders smaller than this |
| `DUST_USD` | `1.0` | holdings below this are never traded |
| `PM_STATE_DIR` | script dir | where `hwm.json` and logs live |

## 8. Files it writes

| File | Purpose |
|---|---|
| `hwm.json` | high-water mark, sample count, last net worth |
| `KILL_SWITCH_FIRED.json` | sentinel; its existence blocks startup |
| `portfolio_manager.log` | full run log |
| `decisions.log` | append-only audit trail of every EXECUTE/SKIP/guard/order |

Back up `hwm.json` if the HWM matters to you — deleting it re-seeds from
current net worth, which silently resets your drawdown baseline.

## 9. Known limits

- **The command gate blocks.** While it waits for input the 4h timer is
  paused. Under `nohup`/`systemd`/`cron` there is no TTY, so the gate fails
  safe to `SKIP` — proposals will be logged and never executed. Run it in a
  terminal (or `tmux`) if you want to approve trades.
- **Binance Earn / staked balances** appear under `LD*` codes or not at all
  in the spot balance. They are not valued, not sold by the kill switch, and
  a non-dust `LD*` holding will hold guard G1 by design.
- **Market orders only.** In a real crash, market-selling a thin altcoin book
  gets a bad fill. That is inherent to "liquidate immediately"; the
  largest-first ordering limits it but does not remove it.
- **The 4h screen is a heuristic**, not a prediction — trend structure,
  momentum, and relative strength. It has no fundamental, flow, or
  correlation awareness, and it will happily propose buying strength into a
  top.
- **Isolated-margin and hedge-mode** futures accounts are handled but only
  lightly tested; rehearse on testnet first if you use either.
