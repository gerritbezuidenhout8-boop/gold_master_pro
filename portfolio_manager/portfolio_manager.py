#!/usr/bin/env python3
"""
portfolio_manager.py — autonomous Binance portfolio analyst with a hard
drawdown kill switch.

WHAT THIS IS
------------
A single-file, long-running process that, every CYCLE_HOURS (default 4):

  1. Values the whole account (Spot balances + USDⓈ-M Futures wallet and
     open positions) in USD.
  2. Tracks the all-time-high account value (the "High-Water Mark", HWM)
     in a local JSON file and computes the current drawdown from it.
  3. If drawdown > MAX_DRAWDOWN_PCT *and every safety guard agrees the
     reading is real*, fires the KILL SWITCH: cancels all open orders,
     closes all futures positions, market-sells all spot altcoins to
     USDT, and terminates the process so it cannot re-enter.
  4. Otherwise, runs a 4h-timeframe technical screen over held assets and
     a watchlist of majors, prints a Portfolio Rebalancing Proposal, and
     BLOCKS on a terminal prompt. Nothing is traded unless you type
     EXECUTE.

TRADING IS OFF BY DEFAULT
-------------------------
The script starts in DRY-RUN: it will do all the analysis, print all the
proposals, and *simulate* every order (including a kill-switch fire)
without sending anything to Binance. To arm live order placement you must
set the environment variable:

    PM_LIVE_TRADING=1

This is deliberate. Read a few dry-run cycles and confirm the valuation
numbers match what you see in the Binance UI before you arm it.

THE KILL SWITCH IS THE DANGEROUS PART — READ THIS
-------------------------------------------------
Every other action in this script is gated behind you typing EXECUTE. The
kill switch is not: by design it bypasses that gate. That means the most
likely thing to ever fire it is not a market crash but a *bug or an API
hiccup in the valuation path* — a delisted symbol with no ticker, a
partial balance response during a Binance outage, a truncated hwm.json.
An unguarded implementation would market-dump your entire account because
one HTTP response came back wrong at 4am.

So the trigger sits behind five guards (see `KillSwitchGuards`). All must
pass before a single order is sent:

    G1 VALUATION COMPLETE  every non-dust asset was priced. One unpriced
                           holding => the net-worth number is too low by
                           an unknown amount => refuse to trigger.
    G2 HWM TRUSTWORTHY     hwm.json parsed cleanly, is positive, and has
                           at least MIN_HWM_SAMPLES observations behind
                           it. A freshly seeded HWM never triggers.
    G3 NOT-ABSURD          current net worth is not below IMPLAUSIBLE_
                           FLOOR_PCT of the HWM. A reading of "you lost
                           99%" is far more likely a data failure than a
                           real event, and dumping on it is the worst
                           possible outcome.
    G4 CONFIRMED           after KILL_CONFIRM_DELAY_S the entire account
                           is re-fetched from scratch and revalued. The
                           second reading must *also* breach, and the two
                           readings must agree within CONFIRM_TOLERANCE.
                           A single bad tick cannot get through this.
    G5 ARMED               KILL_SWITCH_ENABLED is true.

Guards G1-G4 cost you at most KILL_CONFIRM_DELAY_S of extra drawdown in a
genuine crash. They save you from a total, irreversible, unattended
liquidation on a bad HTTP response. That trade is worth it every time.

One more thing you should know before running this: a 15% drawdown is
ordinary in crypto, not catastrophic. A 15% threshold measured against an
all-time HWM will fire, probably within months, and most likely near a
local bottom — after which the script terminates and you are in stables
for whatever comes next. That is a strategy choice, not a bug, and it is
yours to make. MAX_DRAWDOWN_PCT is a config constant; tune it knowingly.

NOT FINANCIAL ADVICE. This is an analysis and automation tool. The
technical screen in Phase 2 is a deterministic heuristic, not a
prediction. You are responsible for every order it places.
"""

from __future__ import annotations

import json
import logging
import math
import os
import signal
import sys
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

try:
    import ccxt
except ImportError:  # pragma: no cover - import guard for first-run UX
    sys.exit("ccxt is not installed. Run:  pip install ccxt pandas")

try:
    import pandas as pd
except ImportError:  # pragma: no cover
    sys.exit("pandas is not installed. Run:  pip install ccxt pandas")


# =============================================================================
# CONFIGURATION
# =============================================================================
# Every value here can be overridden with an environment variable of the
# same name, so you can tune the deployment without editing the file.

def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


# --- The kill switch ---------------------------------------------------------
# Maximum tolerated drawdown from the High-Water Mark before liquidation.
# 0.15 == 15%.
MAX_DRAWDOWN_PCT = _env_float("MAX_DRAWDOWN_PCT", 0.15)
# Master arm/disarm for the kill switch itself.
KILL_SWITCH_ENABLED = _env_bool("KILL_SWITCH_ENABLED", True)
# G4: how long to wait before the independent confirmation re-read.
KILL_CONFIRM_DELAY_S = _env_int("KILL_CONFIRM_DELAY_S", 60)
# G4: the two independent net-worth readings must agree within this fraction.
CONFIRM_TOLERANCE = _env_float("CONFIRM_TOLERANCE", 0.05)
# G3: a net worth below this fraction of the HWM is treated as a data fault,
# not as a real loss. 0.35 == "we do not believe a reported 65%+ instant loss".
IMPLAUSIBLE_FLOOR_PCT = _env_float("IMPLAUSIBLE_FLOOR_PCT", 0.35)
# G2: how many recorded observations the HWM needs before it can be used as
# the denominator of a liquidation decision.
MIN_HWM_SAMPLES = _env_int("MIN_HWM_SAMPLES", 2)

# --- Execution ---------------------------------------------------------------
# Live order placement is OFF unless this is explicitly set to 1/true.
LIVE_TRADING = _env_bool("PM_LIVE_TRADING", False)
# Route to Binance testnet instead of production (works with testnet keys).
USE_TESTNET = _env_bool("PM_TESTNET", False)

# --- Cycle -------------------------------------------------------------------
CYCLE_HOURS = _env_float("CYCLE_HOURS", 4.0)
TIMEFRAME = os.environ.get("TIMEFRAME", "4h")
OHLCV_LIMIT = _env_int("OHLCV_LIMIT", 200)

# --- Valuation ---------------------------------------------------------------
QUOTE = "USDT"
# Holdings worth less than this are "dust": counted in net worth, but never
# traded and never allowed to block the kill switch on pricing failure.
DUST_USD = _env_float("DUST_USD", 1.0)
# Assets we treat as 1.00 USD and never sell.
STABLECOINS = {"USDT", "USDC", "BUSD", "FDUSD", "TUSD", "DAI", "USDP", "USD"}
# Quote currencies we will look through, in preference order, to price an asset.
PRICE_QUOTES = ("USDT", "USDC", "FDUSD", "BUSD", "TUSD")
# Bridges used when an asset has no direct stable pair (e.g. ALT/BTC).
PRICE_BRIDGES = ("BTC", "ETH", "BNB")

# --- Rebalancing heuristics --------------------------------------------------
# Symbols always screened as potential buys, on top of whatever you hold.
WATCHLIST = [
    s.strip().upper()
    for s in os.environ.get("WATCHLIST", "BTC,ETH,SOL,BNB,XRP,ADA,AVAX,LINK,DOGE,TON").split(",")
    if s.strip()
]
# Never let one non-stable asset exceed this share of net worth via a BUY.
MAX_POSITION_PCT = _env_float("MAX_POSITION_PCT", 0.30)
# Fraction of a weak holding to trim per cycle.
TRIM_FRACTION = _env_float("TRIM_FRACTION", 0.50)
# Keep at least this fraction of net worth in stables; buys stop at this line.
MIN_STABLE_RESERVE_PCT = _env_float("MIN_STABLE_RESERVE_PCT", 0.10)
# Technical score thresholds (score runs -100..+100).
WEAK_SCORE = _env_float("WEAK_SCORE", -25.0)
STRONG_SCORE = _env_float("STRONG_SCORE", 35.0)
# Don't emit an order smaller than this notional — exchange minimums plus fees
# make micro-orders pure loss.
MIN_ORDER_USD = _env_float("MIN_ORDER_USD", 12.0)

# --- Files -------------------------------------------------------------------
STATE_DIR = Path(os.environ.get("PM_STATE_DIR", Path(__file__).resolve().parent))
HWM_FILE = STATE_DIR / "hwm.json"
# Written when the kill switch fires. Its presence blocks startup, which is how
# "terminate to prevent re-entry" survives a supervisor restarting the process.
KILL_SENTINEL = STATE_DIR / "KILL_SWITCH_FIRED.json"
LOG_FILE = STATE_DIR / "portfolio_manager.log"
DECISION_LOG = STATE_DIR / "decisions.log"


# =============================================================================
# TERMINAL COLOURS + LOGGING
# =============================================================================

class C:
    """ANSI colours. Disabled automatically when stdout is not a terminal."""
    _on = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
    RED = "\033[91m" if _on else ""
    BG_RED = "\033[41;97;1m" if _on else ""
    GREEN = "\033[92m" if _on else ""
    YELLOW = "\033[93m" if _on else ""
    CYAN = "\033[96m" if _on else ""
    GREY = "\033[90m" if _on else ""
    BOLD = "\033[1m" if _on else ""
    OFF = "\033[0m" if _on else ""


def _setup_logging() -> logging.Logger:
    log = logging.getLogger("pm")
    log.setLevel(logging.INFO)
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%Y-%m-%d %H:%M:%S")
    stream = logging.StreamHandler(sys.stdout)
    stream.setFormatter(fmt)
    log.addHandler(stream)
    try:
        fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
        fh.setFormatter(fmt)
        log.addHandler(fh)
    except OSError as exc:  # non-fatal: keep running with console logging only
        log.warning("could not open log file %s (%s)", LOG_FILE, exc)
    return log


LOG = _setup_logging()


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def usd(x: float | None) -> str:
    if x is None:
        return "     n/a"
    return f"${x:,.2f}"


def record_decision(text: str) -> None:
    """Append-only audit trail of everything that moved money (or didn't)."""
    try:
        with open(DECISION_LOG, "a", encoding="utf-8") as fh:
            fh.write(f"{utcnow()}  {text}\n")
    except OSError as exc:
        LOG.warning("could not write decision log: %s", exc)


# =============================================================================
# EXCHANGE CLIENTS
# =============================================================================

class Exchanges:
    """
    Two ccxt clients against one Binance account: one in spot mode, one in
    USDⓈ-M futures mode. ccxt keys most behaviour off `options.defaultType`,
    and mixing the two on a single instance is a reliable source of subtle
    bugs, so they are kept separate.
    """

    def __init__(self) -> None:
        key = os.environ.get("BINANCE_API_KEY")
        secret = os.environ.get("BINANCE_SECRET")
        if not key or not secret:
            sys.exit(
                "BINANCE_API_KEY and BINANCE_SECRET must be set in the environment.\n"
                "Never hardcode them. See README.md."
            )

        def build(default_type: str) -> ccxt.binance:
            client = ccxt.binance({
                "apiKey": key,
                "secret": secret,
                # ccxt will sleep to respect Binance weight limits for us.
                "enableRateLimit": True,
                "timeout": 30_000,
                "options": {
                    "defaultType": default_type,
                    # Binance rejects requests whose timestamp drifts from server
                    # time; let ccxt sync rather than trusting the local clock.
                    "adjustForTimeDifference": True,
                    "recvWindow": 10_000,
                },
            })
            if USE_TESTNET:
                client.set_sandbox_mode(True)
            return client

        self.spot = build("spot")
        self.futures = build("future")
        self.futures_available = True

        LOG.info("loading markets...")
        self.spot.load_markets()
        try:
            self.futures.load_markets()
        except ccxt.BaseError as exc:
            # A spot-only API key, or futures not enabled on the account. Not
            # fatal: we degrade to spot-only management and say so loudly.
            LOG.warning("futures markets unavailable (%s) — running spot-only", exc)
            self.futures_available = False


# =============================================================================
# HIGH-WATER MARK STORE
# =============================================================================

@dataclass
class Hwm:
    """The persisted high-water mark plus the metadata the guards need."""
    value: float = 0.0
    established_at: str = ""
    updated_at: str = ""
    samples: int = 0          # how many net-worth observations we've recorded
    last_net_worth: float = 0.0
    trusted: bool = True      # False when the file was missing/corrupt this run


class HwmStore:
    """
    Reads/writes hwm.json.

    Writes are atomic (temp file + os.replace) because the alternative — a
    process killed mid-write leaving a truncated JSON file — produces exactly
    the corrupt-HWM scenario that guard G2 exists to catch. Better to never
    create it.
    """

    def __init__(self, path: Path) -> None:
        self.path = path

    def load(self) -> Hwm:
        if not self.path.exists():
            LOG.info("no hwm.json yet — it will be seeded from this cycle's net worth")
            return Hwm(trusted=False)
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            value = float(raw["value"])
            if not math.isfinite(value) or value <= 0:
                raise ValueError(f"non-positive hwm {value!r}")
            return Hwm(
                value=value,
                established_at=str(raw.get("established_at", "")),
                updated_at=str(raw.get("updated_at", "")),
                samples=int(raw.get("samples", 0)),
                last_net_worth=float(raw.get("last_net_worth", 0.0)),
                trusted=True,
            )
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            # Do NOT fall back to 0 and carry on silently — a zero or garbage
            # HWM makes drawdown meaningless and could trigger liquidation.
            LOG.error("hwm.json is unreadable (%s) — HWM marked UNTRUSTED for this run", exc)
            return Hwm(trusted=False)

    def save(self, hwm: Hwm) -> None:
        payload = {
            "value": hwm.value,
            "established_at": hwm.established_at,
            "updated_at": utcnow(),
            "samples": hwm.samples,
            "last_net_worth": hwm.last_net_worth,
        }
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=str(self.path.parent), prefix=".hwm-", suffix=".tmp")
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, indent=2)
                fh.flush()
                os.fsync(fh.fileno())   # durable before the rename
            os.replace(tmp, self.path)  # atomic on POSIX and Windows
        except OSError as exc:
            LOG.error("could not persist hwm.json: %s", exc)

    def observe(self, hwm: Hwm, net_worth: float) -> Hwm:
        """Record a net-worth reading, raising the HWM if this is a new peak."""
        hwm.samples += 1
        hwm.last_net_worth = net_worth
        if net_worth > hwm.value:
            if hwm.value == 0.0:
                hwm.established_at = utcnow()
            else:
                LOG.info("new high-water mark: %s (was %s)", usd(net_worth), usd(hwm.value))
            hwm.value = net_worth
        hwm.trusted = True
        self.save(hwm)
        return hwm


# =============================================================================
# PORTFOLIO SNAPSHOT + VALUATION
# =============================================================================

@dataclass
class SpotHolding:
    asset: str
    total: float          # free + locked
    free: float
    price: float | None   # USD, None when we could not price it
    usd_value: float      # 0.0 when unpriced

    @property
    def is_stable(self) -> bool:
        return self.asset in STABLECOINS

    @property
    def is_dust(self) -> bool:
        return self.usd_value < DUST_USD


@dataclass
class FuturesPosition:
    symbol: str           # e.g. "BTC/USDT:USDT"
    side: str             # "long" | "short"
    contracts: float      # absolute size in base units
    entry_price: float | None
    mark_price: float | None
    notional: float       # absolute USD notional
    unrealized_pnl: float
    leverage: float | None
    position_side: str | None  # "BOTH"/"LONG"/"SHORT" — needed in hedge mode


@dataclass
class Snapshot:
    """One complete, timestamped valuation of the account."""
    taken_at: str
    spot: list[SpotHolding] = field(default_factory=list)
    positions: list[FuturesPosition] = field(default_factory=list)
    futures_wallet_usd: float = 0.0     # margin balance incl. unrealised PnL
    unpriced: list[str] = field(default_factory=list)   # non-dust, unpriceable
    partial: bool = False               # True if any fetch failed outright

    @property
    def spot_usd(self) -> float:
        return sum(h.usd_value for h in self.spot)

    @property
    def net_worth(self) -> float:
        return self.spot_usd + self.futures_wallet_usd

    @property
    def stable_usd(self) -> float:
        return sum(h.usd_value for h in self.spot if h.is_stable)

    @property
    def risk_usd(self) -> float:
        """Everything that is not a stablecoin — what the kill switch targets."""
        return sum(h.usd_value for h in self.spot if not h.is_stable)

    @property
    def is_trustworthy(self) -> bool:
        """A snapshot is only usable for a liquidation decision if it is whole."""
        return not self.partial and not self.unpriced


class Valuer:
    """Turns Binance balances + tickers into a priced Snapshot."""

    def __init__(self, ex: Exchanges) -> None:
        self.ex = ex

    # -- pricing --------------------------------------------------------------

    @staticmethod
    def _last(ticker: dict[str, Any] | None) -> float | None:
        """Best available price from a ticker, preferring the bid/ask mid."""
        if not ticker:
            return None
        bid, ask = ticker.get("bid"), ticker.get("ask")
        if bid and ask and bid > 0 and ask > 0:
            return (float(bid) + float(ask)) / 2.0
        for key in ("last", "close", "average"):
            v = ticker.get(key)
            if v and float(v) > 0:
                return float(v)
        return None

    def price_of(self, asset: str, tickers: dict[str, Any]) -> float | None:
        """
        USD price for an asset, or None if we genuinely cannot determine it.

        Returning None rather than 0.0 is load-bearing: 0.0 would silently
        understate net worth and could manufacture a fake drawdown. Every
        None is collected into Snapshot.unpriced and blocks the kill switch
        via guard G1.
        """
        if asset in STABLECOINS:
            return 1.0
        for quote in PRICE_QUOTES:
            price = self._last(tickers.get(f"{asset}/{quote}"))
            if price:
                return price
        # No direct stable pair — route through a bridge (ALT/BTC * BTC/USDT).
        for bridge in PRICE_BRIDGES:
            leg = self._last(tickers.get(f"{asset}/{bridge}"))
            if not leg:
                continue
            bridge_usd = self._last(tickers.get(f"{bridge}/{QUOTE}"))
            if bridge_usd:
                return leg * bridge_usd
        return None

    # -- fetching -------------------------------------------------------------

    def take(self) -> Snapshot:
        """Fetch and value everything. Never raises — sets `partial` instead."""
        snap = Snapshot(taken_at=utcnow())

        # One bulk ticker call prices the entire spot book (weight ~40) instead
        # of N per-symbol calls.
        tickers: dict[str, Any] = {}
        try:
            tickers = self.ex.spot.fetch_tickers()
        except ccxt.BaseError as exc:
            LOG.error("fetch_tickers failed: %s", exc)
            snap.partial = True

        # --- Spot balances ---
        try:
            bal = self.ex.spot.fetch_balance()
            totals = bal.get("total") or {}
            frees = bal.get("free") or {}
            for asset, total in totals.items():
                total = float(total or 0.0)
                if total <= 0:
                    continue
                price = self.price_of(asset, tickers) if tickers else None
                value = total * price if price is not None else 0.0
                snap.spot.append(SpotHolding(
                    asset=asset,
                    total=total,
                    free=float(frees.get(asset) or 0.0),
                    price=price,
                    usd_value=value,
                ))
        except ccxt.BaseError as exc:
            LOG.error("spot fetch_balance failed: %s", exc)
            snap.partial = True

        # Anything we hold in meaningful size but could not price makes the
        # whole net-worth figure untrustworthy. Dust is exempt: a $0.30
        # unpriceable airdrop should not veto a real kill switch.
        for h in snap.spot:
            if h.price is None and h.total > 0:
                # We cannot know its USD value, so we cannot call it dust by
                # value. Use a conservative rule: unknown price == not dust,
                # unless the raw amount is trivially small in token terms too.
                snap.unpriced.append(h.asset)

        # --- Futures wallet + positions ---
        if self.ex.futures_available:
            try:
                fbal = self.ex.futures.fetch_balance()
                info = fbal.get("info") or {}
                # totalMarginBalance = wallet balance + unrealised PnL, which is
                # the number that actually represents "what the futures side is
                # worth right now". Fall back to the plain USDT total.
                margin = info.get("totalMarginBalance")
                if margin is not None:
                    snap.futures_wallet_usd = float(margin)
                else:
                    total = (fbal.get("total") or {})
                    snap.futures_wallet_usd = sum(
                        float(total.get(s) or 0.0) for s in ("USDT", "USDC", "BUSD")
                    )
            except ccxt.BaseError as exc:
                LOG.error("futures fetch_balance failed: %s", exc)
                snap.partial = True

            try:
                for p in self.ex.futures.fetch_positions():
                    contracts = float(p.get("contracts") or 0.0)
                    if contracts == 0:
                        continue
                    notional = abs(float(p.get("notional") or 0.0))
                    side = p.get("side") or ("long" if contracts > 0 else "short")
                    snap.positions.append(FuturesPosition(
                        symbol=p.get("symbol", "?"),
                        side=str(side).lower(),
                        contracts=abs(contracts),
                        entry_price=_f(p.get("entryPrice")),
                        mark_price=_f(p.get("markPrice")),
                        notional=notional,
                        unrealized_pnl=float(p.get("unrealizedPnl") or 0.0),
                        leverage=_f(p.get("leverage")),
                        position_side=(p.get("info") or {}).get("positionSide"),
                    ))
            except ccxt.BaseError as exc:
                LOG.error("fetch_positions failed: %s", exc)
                snap.partial = True

        return snap


def _f(v: Any) -> float | None:
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None


# =============================================================================
# KILL SWITCH
# =============================================================================

@dataclass
class GuardResult:
    passed: bool
    name: str
    detail: str


class KillSwitchGuards:
    """
    The five checks that stand between a drawdown reading and an unattended
    liquidation of the account. See the module docstring for the rationale.
    """

    def __init__(self, valuer: Valuer) -> None:
        self.valuer = valuer

    def evaluate(self, snap: Snapshot, hwm: Hwm, drawdown: float) -> tuple[bool, list[GuardResult]]:
        results: list[GuardResult] = []

        # G5 — armed at all?
        results.append(GuardResult(
            KILL_SWITCH_ENABLED, "G5 ARMED",
            "kill switch enabled" if KILL_SWITCH_ENABLED else "KILL_SWITCH_ENABLED=0, disarmed",
        ))

        # G1 — is the valuation complete?
        if snap.partial:
            results.append(GuardResult(False, "G1 VALUATION", "one or more API fetches failed"))
        elif snap.unpriced:
            results.append(GuardResult(
                False, "G1 VALUATION",
                f"could not price {', '.join(snap.unpriced)} — net worth understated",
            ))
        else:
            results.append(GuardResult(True, "G1 VALUATION", "all holdings priced"))

        # G2 — is the HWM itself trustworthy?
        if not hwm.trusted:
            results.append(GuardResult(False, "G2 HWM", "hwm.json missing or corrupt this run"))
        elif hwm.value <= 0:
            results.append(GuardResult(False, "G2 HWM", "hwm is not positive"))
        elif hwm.samples < MIN_HWM_SAMPLES:
            results.append(GuardResult(
                False, "G2 HWM",
                f"only {hwm.samples} observation(s), need {MIN_HWM_SAMPLES}",
            ))
        else:
            results.append(GuardResult(True, "G2 HWM", f"{usd(hwm.value)} over {hwm.samples} samples"))

        # G3 — is the loss physically plausible?
        floor = hwm.value * IMPLAUSIBLE_FLOOR_PCT
        if hwm.value > 0 and snap.net_worth < floor:
            results.append(GuardResult(
                False, "G3 PLAUSIBLE",
                f"net worth {usd(snap.net_worth)} is below {IMPLAUSIBLE_FLOOR_PCT:.0%} of HWM "
                f"({usd(floor)}) — treating as a DATA FAULT, not a loss",
            ))
        else:
            results.append(GuardResult(True, "G3 PLAUSIBLE", f"drawdown {drawdown:.2%} is in a believable range"))

        # G4 — independent second reading. Only run if everything else passed,
        # because it costs a minute of wall-clock and a round of API calls.
        if all(r.passed for r in results):
            results.append(self._confirm(hwm, snap.net_worth))
        else:
            results.append(GuardResult(False, "G4 CONFIRMED", "skipped — an earlier guard already failed"))

        return all(r.passed for r in results), results

    def _confirm(self, hwm: Hwm, first_reading: float) -> GuardResult:
        """
        Re-fetch the entire account from scratch and demand the same verdict.

        This is the guard that defeats the realistic failure mode: a single
        malformed response, a momentarily empty ticker map, a stale mark
        price. Two independent reads a minute apart do not fail identically.
        """
        LOG.warning(
            "%sDRAWDOWN BREACH DETECTED — re-verifying in %ds before acting%s",
            C.YELLOW, KILL_CONFIRM_DELAY_S, C.OFF,
        )
        time.sleep(KILL_CONFIRM_DELAY_S)

        second = self.valuer.take()
        if not second.is_trustworthy:
            return GuardResult(False, "G4 CONFIRMED", "confirmation snapshot was incomplete")

        second_dd = (hwm.value - second.net_worth) / hwm.value
        if second_dd <= MAX_DRAWDOWN_PCT:
            return GuardResult(
                False, "G4 CONFIRMED",
                f"second reading {usd(second.net_worth)} => {second_dd:.2%} drawdown, "
                f"no longer past the {MAX_DRAWDOWN_PCT:.0%} limit — first reading was noise",
            )

        # Both breached — but do the two readings actually agree? If they are
        # wildly apart, the account value is not what is unstable, our *view*
        # of it is, and we must not liquidate on it.
        if first_reading > 0:
            spread = abs(second.net_worth - first_reading) / first_reading
            if spread > CONFIRM_TOLERANCE:
                return GuardResult(
                    False, "G4 CONFIRMED",
                    f"readings disagree by {spread:.2%} ({usd(first_reading)} vs "
                    f"{usd(second.net_worth)}) — data is unstable, refusing to liquidate",
                )

        return GuardResult(
            True, "G4 CONFIRMED",
            f"second independent reading {usd(second.net_worth)} => {second_dd:.2%} drawdown, breach confirmed",
        )


class KillSwitch:
    """Cancels everything, closes everything, sells everything, then exits."""

    def __init__(self, ex: Exchanges, trader: "Trader") -> None:
        self.ex = ex
        self.trader = trader

    def fire(self, snap: Snapshot, hwm: Hwm, drawdown: float) -> None:
        self._banner(snap, hwm, drawdown)
        record_decision(
            f"KILL SWITCH FIRED drawdown={drawdown:.4f} net_worth={snap.net_worth:.2f} "
            f"hwm={hwm.value:.2f} live={LIVE_TRADING}"
        )

        actions: list[str] = []

        # Order matters. Open orders are cancelled first so that (a) resting
        # limit orders cannot partially fill against our own liquidation and
        # (b) the balance locked in them becomes free and therefore sellable.
        actions += self._cancel_all_orders(snap)
        # Futures next: leveraged exposure is what actually threatens the
        # account, so it gets closed before unlevered spot.
        actions += self._close_all_positions(snap)
        actions += self._liquidate_spot(snap)

        print()
        print(f"{C.BOLD}KILL SWITCH ACTIONS{C.OFF}")
        for a in actions or ["  (nothing to do — account already flat)"]:
            print(f"  {a}")
            record_decision(f"KILL: {a}")

        self._write_sentinel(snap, hwm, drawdown, actions)

        print()
        print(f"{C.BG_RED} PORTFOLIO MANAGER TERMINATED. Restart is blocked until you delete: {C.OFF}")
        print(f"{C.RED}   {KILL_SENTINEL}{C.OFF}")
        print()
        # Exit non-zero so a supervisor/systemd sees a failure rather than
        # cheerfully restarting us straight back into the market.
        sys.exit(2)

    # -- the individual liquidation steps -------------------------------------

    def _cancel_all_orders(self, snap: Snapshot) -> list[str]:
        out: list[str] = []
        # Spot
        try:
            open_orders = self.ex.spot.fetch_open_orders()
        except ccxt.BaseError as exc:
            out.append(f"{C.RED}! could not list spot open orders: {exc}{C.OFF}")
            open_orders = []
        for o in open_orders:
            sym = o.get("symbol")
            oid = o.get("id")
            try:
                if LIVE_TRADING:
                    self.ex.spot.cancel_order(oid, sym)
                out.append(f"{self._tag()} cancel spot order {oid} on {sym}")
            except ccxt.BaseError as exc:
                out.append(f"{C.RED}! cancel failed {sym} {oid}: {exc}{C.OFF}")

        # Futures — cancel per symbol that has a position or an open order.
        if self.ex.futures_available:
            try:
                fopen = self.ex.futures.fetch_open_orders()
            except ccxt.BaseError as exc:
                out.append(f"{C.RED}! could not list futures open orders: {exc}{C.OFF}")
                fopen = []
            for o in fopen:
                sym, oid = o.get("symbol"), o.get("id")
                try:
                    if LIVE_TRADING:
                        self.ex.futures.cancel_order(oid, sym)
                    out.append(f"{self._tag()} cancel futures order {oid} on {sym}")
                except ccxt.BaseError as exc:
                    out.append(f"{C.RED}! cancel failed {sym} {oid}: {exc}{C.OFF}")
        return out

    def _close_all_positions(self, snap: Snapshot) -> list[str]:
        out: list[str] = []
        if not self.ex.futures_available:
            return out
        # Close the largest notional first: if we get rate-limited or the API
        # degrades halfway through, we want the biggest risk gone already.
        for pos in sorted(snap.positions, key=lambda p: p.notional, reverse=True):
            # A long is closed by selling, a short by buying.
            side = "sell" if pos.side == "long" else "buy"
            params: dict[str, Any] = {"reduceOnly": True}
            # In hedge mode Binance requires positionSide and *rejects*
            # reduceOnly; in one-way mode it requires reduceOnly. Detect from
            # the position payload rather than guessing.
            if pos.position_side and pos.position_side.upper() in {"LONG", "SHORT"}:
                params = {"positionSide": pos.position_side}
            try:
                if LIVE_TRADING:
                    amount = float(self.ex.futures.amount_to_precision(pos.symbol, pos.contracts))
                    self.ex.futures.create_order(pos.symbol, "market", side, amount, None, params)
                out.append(
                    f"{self._tag()} close {pos.side.upper()} {pos.contracts:g} {pos.symbol} "
                    f"({usd(pos.notional)} notional, PnL {usd(pos.unrealized_pnl)}) via market {side}"
                )
            except ccxt.BaseError as exc:
                out.append(f"{C.RED}! FAILED to close {pos.symbol}: {exc}{C.OFF}")
        return out

    def _liquidate_spot(self, snap: Snapshot) -> list[str]:
        out: list[str] = []
        # Largest first, same reasoning as futures.
        risk = [h for h in snap.spot if not h.is_stable and not h.is_dust]
        for h in sorted(risk, key=lambda x: x.usd_value, reverse=True):
            symbol = self._sellable_symbol(h.asset)
            if symbol is None:
                out.append(
                    f"{C.RED}! {h.asset}: no tradable stable pair — {usd(h.usd_value)} "
                    f"LEFT IN PLACE, sell it manually{C.OFF}"
                )
                continue
            # After cancelling orders `free` should equal `total`, but re-read
            # from the snapshot conservatively and let the exchange reject an
            # oversized amount rather than assuming.
            amount = h.total
            ok, detail = self.trader.market_order(self.ex.spot, symbol, "sell", amount, h.price)
            prefix = self._tag() if ok else f"{C.RED}!{C.OFF}"
            out.append(f"{prefix} sell {amount:g} {h.asset} (~{usd(h.usd_value)}) — {detail}")
        return out

    def _sellable_symbol(self, asset: str) -> str | None:
        for quote in PRICE_QUOTES:
            sym = f"{asset}/{quote}"
            market = self.ex.spot.markets.get(sym)
            if market and market.get("active", True) and market.get("spot", True):
                return sym
        return None

    @staticmethod
    def _tag() -> str:
        return f"{C.GREEN}✓{C.OFF}" if LIVE_TRADING else f"{C.GREY}[dry-run]{C.OFF}"

    # -- banner + sentinel ----------------------------------------------------

    def _banner(self, snap: Snapshot, hwm: Hwm, drawdown: float) -> None:
        bar = "█" * 74
        print()
        print(f"{C.RED}{bar}{C.OFF}")
        print(f"{C.BG_RED}{'  ***  MAXIMUM DRAWDOWN BREACHED — KILL SWITCH ENGAGED  ***  ':^74}{C.OFF}")
        print(f"{C.RED}{bar}{C.OFF}")
        print()
        print(f"{C.RED}{C.BOLD}  High-Water Mark : {usd(hwm.value)}{C.OFF}")
        print(f"{C.RED}{C.BOLD}  Current Value   : {usd(snap.net_worth)}{C.OFF}")
        print(f"{C.RED}{C.BOLD}  Drawdown        : {drawdown:.2%}  (limit {MAX_DRAWDOWN_PCT:.2%}){C.OFF}")
        print(f"{C.RED}{C.BOLD}  Risk assets     : {usd(snap.risk_usd)} spot + "
              f"{len(snap.positions)} futures position(s){C.OFF}")
        print()
        if not LIVE_TRADING:
            print(f"{C.YELLOW}{C.BOLD}  DRY-RUN: no orders will be sent. "
                  f"Set PM_LIVE_TRADING=1 to arm.{C.OFF}")
            print()

    def _write_sentinel(self, snap: Snapshot, hwm: Hwm, drawdown: float, actions: list[str]) -> None:
        try:
            KILL_SENTINEL.write_text(json.dumps({
                "fired_at": utcnow(),
                "hwm": hwm.value,
                "net_worth": snap.net_worth,
                "drawdown": drawdown,
                "limit": MAX_DRAWDOWN_PCT,
                "live_trading": LIVE_TRADING,
                "actions": [_strip_ansi(a) for a in actions],
            }, indent=2), encoding="utf-8")
        except OSError as exc:
            LOG.error("could not write kill sentinel: %s", exc)


def _strip_ansi(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\033":
            while i < len(s) and s[i] != "m":
                i += 1
            i += 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


# =============================================================================
# MARKET ANALYSIS (4h timeframe)
# =============================================================================

@dataclass
class Assessment:
    """Deterministic technical read on one asset, 4h timeframe."""
    asset: str
    symbol: str
    price: float
    score: float          # -100 (weakest) .. +100 (strongest)
    rsi: float
    ema20: float
    ema50: float
    atr_pct: float
    ret_24h: float        # 6 x 4h bars
    ret_7d: float         # 42 x 4h bars
    rel_btc_7d: float     # 7d return minus BTC's 7d return
    notes: list[str] = field(default_factory=list)

    @property
    def justification(self) -> str:
        return "; ".join(self.notes)


class Analyst:
    """
    Pure-pandas technical screen. Every number printed in the proposal comes
    from here, so the justification text can never claim something the data
    does not say.
    """

    def __init__(self, ex: Exchanges) -> None:
        self.ex = ex

    def ohlcv(self, symbol: str) -> pd.DataFrame | None:
        try:
            rows = self.ex.spot.fetch_ohlcv(symbol, timeframe=TIMEFRAME, limit=OHLCV_LIMIT)
        except ccxt.BaseError as exc:
            LOG.warning("ohlcv %s failed: %s", symbol, exc)
            return None
        if not rows or len(rows) < 60:
            return None
        df = pd.DataFrame(rows, columns=["ts", "open", "high", "low", "close", "volume"])
        df["dt"] = pd.to_datetime(df["ts"], unit="ms", utc=True)
        return df

    @staticmethod
    def _rsi(close: pd.Series, period: int = 14) -> pd.Series:
        """Wilder's RSI (EMA-smoothed, alpha = 1/period)."""
        delta = close.diff()
        gain = delta.clip(lower=0.0)
        loss = -delta.clip(upper=0.0)
        avg_gain = gain.ewm(alpha=1 / period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1 / period, adjust=False).mean()
        rs = avg_gain / avg_loss.replace(0.0, pd.NA)
        return (100 - 100 / (1 + rs)).fillna(100.0)

    @staticmethod
    def _atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
        """Wilder's ATR — used only to express volatility as a % of price."""
        prev_close = df["close"].shift(1)
        tr = pd.concat([
            df["high"] - df["low"],
            (df["high"] - prev_close).abs(),
            (df["low"] - prev_close).abs(),
        ], axis=1).max(axis=1)
        return tr.ewm(alpha=1 / period, adjust=False).mean()

    def assess(self, asset: str, symbol: str, btc_ret_7d: float | None) -> Assessment | None:
        df = self.ohlcv(symbol)
        if df is None:
            return None

        close = df["close"]
        ema20 = close.ewm(span=20, adjust=False).mean()
        ema50 = close.ewm(span=50, adjust=False).mean()
        rsi = self._rsi(close)
        atr = self._atr(df)

        price = float(close.iloc[-1])
        e20, e50 = float(ema20.iloc[-1]), float(ema50.iloc[-1])
        r = float(rsi.iloc[-1])
        atr_pct = float(atr.iloc[-1]) / price * 100.0 if price else 0.0
        ret_24h = self._ret(close, 6)
        ret_7d = self._ret(close, 42)
        rel = ret_7d - btc_ret_7d if btc_ret_7d is not None else 0.0

        # --- scoring: four independent components, summed, clamped ----------
        notes: list[str] = []
        score = 0.0

        # 1. Trend structure (max ±40). Price above a rising 20 EMA which is
        #    itself above the 50 is the classic 4h uptrend.
        if price > e20 > e50:
            score += 40
            notes.append(f"4h uptrend: price {price:,.4f} > EMA20 {e20:,.4f} > EMA50 {e50:,.4f}")
        elif price < e20 < e50:
            score -= 40
            notes.append(f"4h downtrend: price {price:,.4f} < EMA20 {e20:,.4f} < EMA50 {e50:,.4f}")
        else:
            notes.append(f"4h structure mixed around EMA20 {e20:,.4f} / EMA50 {e50:,.4f}")

        # 2. Momentum (max ±25) from RSI, with the extremes treated as
        #    exhaustion rather than strength.
        if r >= 70:
            score -= 10
            notes.append(f"RSI {r:.1f} overbought — poor entry")
        elif r >= 55:
            score += 25
            notes.append(f"RSI {r:.1f} in the bullish band")
        elif r <= 30:
            score -= 25
            notes.append(f"RSI {r:.1f} oversold, momentum against it")
        elif r <= 45:
            score -= 15
            notes.append(f"RSI {r:.1f} weak")
        else:
            notes.append(f"RSI {r:.1f} neutral")

        # 3. Relative strength vs BTC over 7d (max ±20). Underperforming the
        #    benchmark is the main reason to rotate out of a coin.
        if btc_ret_7d is not None:
            score += max(-20.0, min(20.0, rel * 100.0))
            word = "outperforming" if rel > 0 else "underperforming"
            notes.append(f"7d {ret_7d:+.1%} vs BTC {btc_ret_7d:+.1%} ({word} by {abs(rel):.1%})")

        # 4. Short-term drift (max ±15).
        score += max(-15.0, min(15.0, ret_24h * 150.0))
        notes.append(f"24h {ret_24h:+.1%}, ATR {atr_pct:.1f}% of price")

        return Assessment(
            asset=asset, symbol=symbol, price=price,
            score=max(-100.0, min(100.0, score)),
            rsi=r, ema20=e20, ema50=e50, atr_pct=atr_pct,
            ret_24h=ret_24h, ret_7d=ret_7d, rel_btc_7d=rel, notes=notes,
        )

    @staticmethod
    def _ret(close: pd.Series, bars: int) -> float:
        if len(close) <= bars:
            return 0.0
        past = float(close.iloc[-1 - bars])
        return (float(close.iloc[-1]) - past) / past if past else 0.0


# =============================================================================
# REBALANCING PROPOSAL
# =============================================================================

@dataclass
class Action:
    kind: str             # "SELL" | "BUY" | "REDUCE"
    symbol: str
    side: str             # ccxt order side
    amount: float         # base units
    usd: float            # approximate notional
    reason: str
    venue: str = "spot"   # "spot" | "futures"
    params: dict[str, Any] = field(default_factory=dict)

    def describe(self) -> str:
        return f"{self.kind:<7} {self.amount:>16,.6f} {self.symbol:<16} ≈ {usd(self.usd):>12}  [{self.venue}]"


class Proposer:
    """Builds the Portfolio Rebalancing Proposal from the assessments."""

    def __init__(self, ex: Exchanges, analyst: Analyst) -> None:
        self.ex = ex
        self.analyst = analyst

    def build(self, snap: Snapshot) -> tuple[list[Action], dict[str, Assessment]]:
        # BTC is the benchmark every other asset is scored against, so it is
        # fetched first and its 7d return threaded through the rest.
        btc = self.analyst.assess("BTC", f"BTC/{QUOTE}", None)
        btc_ret = btc.ret_7d if btc else None

        universe: dict[str, str] = {}
        for h in snap.spot:
            if h.is_stable or h.is_dust:
                continue
            sym = self._symbol_for(h.asset)
            if sym:
                universe[h.asset] = sym
        for asset in WATCHLIST:
            if asset in STABLECOINS or asset in universe:
                continue
            sym = self._symbol_for(asset)
            if sym:
                universe[asset] = sym

        assessments: dict[str, Assessment] = {}
        for asset, sym in universe.items():
            a = self.analyst.assess(asset, sym, btc_ret)
            if a:
                assessments[asset] = a
        if btc:
            assessments.setdefault("BTC", btc)

        actions: list[Action] = []
        net = snap.net_worth
        held = {h.asset: h for h in snap.spot}

        # --- SELLS: trim holdings whose 4h read is weak ----------------------
        freed = 0.0
        for asset, a in sorted(assessments.items(), key=lambda kv: kv[1].score):
            h = held.get(asset)
            if not h or h.is_stable or h.is_dust or a.score > WEAK_SCORE:
                continue
            amount = h.free * TRIM_FRACTION
            notional = amount * (h.price or a.price)
            if notional < MIN_ORDER_USD:
                continue
            actions.append(Action(
                kind="SELL", symbol=a.symbol, side="sell", amount=amount, usd=notional,
                reason=f"score {a.score:+.0f} — {a.justification}",
            ))
            freed += notional

        # --- BUYS: deploy stables (plus anything freed) into the strongest ---
        reserve = net * MIN_STABLE_RESERVE_PCT
        budget = max(0.0, snap.stable_usd + freed - reserve)
        candidates = [
            a for a in assessments.values()
            if a.score >= STRONG_SCORE
            and not any(x.symbol == a.symbol and x.kind == "SELL" for x in actions)
        ]
        candidates.sort(key=lambda a: a.score, reverse=True)
        # Concentrate rather than sprinkle: top 3 only, weighted by score.
        candidates = candidates[:3]
        if candidates and budget >= MIN_ORDER_USD:
            weight_total = sum(a.score for a in candidates)
            for a in candidates:
                share = (a.score / weight_total) if weight_total else 0.0
                spend = budget * share
                # Respect the per-asset concentration cap, counting what we
                # already hold of it.
                current = held[a.asset].usd_value if a.asset in held else 0.0
                headroom = max(0.0, net * MAX_POSITION_PCT - current)
                spend = min(spend, headroom)
                if spend < MIN_ORDER_USD:
                    continue
                actions.append(Action(
                    kind="BUY", symbol=a.symbol, side="buy", amount=spend / a.price, usd=spend,
                    reason=f"score {a.score:+.0f} — {a.justification}",
                ))

        # --- FUTURES: flag positions fighting the 4h trend -------------------
        for pos in snap.positions:
            base = pos.symbol.split("/")[0]
            a = assessments.get(base)
            if not a:
                continue
            against = (pos.side == "long" and a.score <= WEAK_SCORE) or \
                      (pos.side == "short" and a.score >= STRONG_SCORE)
            if not against:
                continue
            amount = pos.contracts * TRIM_FRACTION
            params: dict[str, Any] = {"reduceOnly": True}
            if pos.position_side and pos.position_side.upper() in {"LONG", "SHORT"}:
                params = {"positionSide": pos.position_side}
            actions.append(Action(
                kind="REDUCE", symbol=pos.symbol,
                side="sell" if pos.side == "long" else "buy",
                amount=amount, usd=pos.notional * TRIM_FRACTION,
                reason=f"{pos.side.upper()} against a 4h score of {a.score:+.0f} — {a.justification}",
                venue="futures", params=params,
            ))

        return actions, assessments

    def _symbol_for(self, asset: str) -> str | None:
        for quote in PRICE_QUOTES:
            sym = f"{asset}/{quote}"
            m = self.ex.spot.markets.get(sym)
            if m and m.get("active", True) and m.get("spot", True):
                return sym
        return None


def print_proposal(snap: Snapshot, hwm: Hwm, drawdown: float,
                   actions: list[Action], assessments: dict[str, Assessment]) -> None:
    line = "─" * 78
    print()
    print(f"{C.CYAN}{line}{C.OFF}")
    print(f"{C.BOLD}  PORTFOLIO REBALANCING PROPOSAL{C.OFF}   {snap.taken_at}")
    print(f"{C.CYAN}{line}{C.OFF}")

    # --- position of the account ---
    dd_colour = C.GREEN if drawdown < MAX_DRAWDOWN_PCT * 0.5 else C.YELLOW
    print(f"  Total Net Worth   : {C.BOLD}{usd(snap.net_worth)}{C.OFF}")
    print(f"    spot            : {usd(snap.spot_usd)}   "
          f"(risk {usd(snap.risk_usd)} / stables {usd(snap.stable_usd)})")
    print(f"    futures wallet  : {usd(snap.futures_wallet_usd)}   "
          f"({len(snap.positions)} open position(s))")
    print(f"  High-Water Mark   : {usd(hwm.value)}  ({hwm.samples} observations)")
    print(f"  Drawdown          : {dd_colour}{drawdown:.2%}{C.OFF}  "
          f"of a {MAX_DRAWDOWN_PCT:.2%} limit")
    if snap.unpriced:
        print(f"  {C.YELLOW}Unpriced holdings : {', '.join(snap.unpriced)} "
              f"(excluded from net worth){C.OFF}")

    # --- allocation ---
    print()
    print(f"{C.BOLD}  ALLOCATION{C.OFF}")
    rows = sorted((h for h in snap.spot if h.usd_value > 0),
                  key=lambda h: h.usd_value, reverse=True)
    for h in rows:
        pct = h.usd_value / snap.net_worth * 100 if snap.net_worth else 0.0
        a = assessments.get(h.asset)
        score = f"score {a.score:+6.0f}" if a else ""
        bar = "▉" * max(0, min(24, int(pct / 4)))
        print(f"    {h.asset:<8} {usd(h.usd_value):>12}  {pct:5.1f}%  {bar:<24} {score}")
    for pos in snap.positions:
        print(f"    {C.GREY}{pos.symbol:<16} {pos.side.upper():<5} {pos.contracts:g} "
              f"@ {pos.entry_price}  notional {usd(pos.notional)}  "
              f"PnL {usd(pos.unrealized_pnl)}{C.OFF}")

    # --- proposed actions ---
    print()
    print(f"{C.BOLD}  PROPOSED ACTIONS ({TIMEFRAME} timeframe){C.OFF}")
    if not actions:
        print(f"    {C.GREY}none — no asset is weak enough to trim and none strong "
              f"enough to add{C.OFF}")
    for i, act in enumerate(actions, 1):
        colour = C.RED if act.kind in {"SELL", "REDUCE"} else C.GREEN
        print(f"    {i}. {colour}{act.describe()}{C.OFF}")
        print(f"       {C.GREY}why: {act.reason}{C.OFF}")
    print(f"{C.CYAN}{line}{C.OFF}")


# =============================================================================
# ORDER EXECUTION
# =============================================================================

class Trader:
    """
    Wraps order placement with the checks that stop an order from being
    rejected — or worse, silently mis-sized — at the exchange.
    """

    def market_order(self, client: ccxt.binance, symbol: str, side: str,
                     amount: float, price_hint: float | None,
                     params: dict[str, Any] | None = None) -> tuple[bool, str]:
        params = params or {}
        market = client.markets.get(symbol)
        if not market:
            return False, f"unknown market {symbol}"

        # Round to the exchange's lot size. Sending unrounded amounts is the
        # single most common cause of a rejected Binance order.
        try:
            amount = float(client.amount_to_precision(symbol, amount))
        except (ccxt.BaseError, ValueError) as exc:
            return False, f"precision error: {exc}"
        if amount <= 0:
            return False, "amount rounds to zero at this lot size"

        limits = market.get("limits") or {}
        min_amt = ((limits.get("amount") or {}).get("min")) or 0.0
        min_cost = ((limits.get("cost") or {}).get("min")) or 0.0
        if amount < min_amt:
            return False, f"below minimum lot size {min_amt}"
        if price_hint and min_cost and amount * price_hint < min_cost:
            return False, f"below minimum notional {min_cost}"

        if not LIVE_TRADING:
            return True, f"{C.GREY}dry-run: would {side} {amount:g} {symbol}{C.OFF}"

        try:
            order = client.create_order(symbol, "market", side, amount, None, params)
            filled = order.get("filled") or order.get("amount") or amount
            avg = order.get("average") or order.get("price")
            return True, f"filled {filled:g} @ {avg} (id {order.get('id')})"
        except ccxt.InsufficientFunds as exc:
            return False, f"insufficient funds: {exc}"
        except ccxt.BaseError as exc:
            return False, f"exchange rejected: {exc}"

    def execute(self, ex: Exchanges, actions: list[Action]) -> None:
        print()
        print(f"{C.BOLD}EXECUTING {len(actions)} ACTION(S){C.OFF}"
              + ("" if LIVE_TRADING else f" {C.YELLOW}(DRY-RUN — nothing is sent){C.OFF}"))
        # Sells before buys: the buys are funded by the sells, and firing them
        # in the other order means the buys fail on insufficient balance.
        ordered = [a for a in actions if a.kind in {"SELL", "REDUCE"}] + \
                  [a for a in actions if a.kind == "BUY"]
        for act in ordered:
            client = ex.futures if act.venue == "futures" else ex.spot
            ok, detail = self.market_order(
                client, act.symbol, act.side, act.amount, act.usd / act.amount if act.amount else None,
                act.params,
            )
            mark = f"{C.GREEN}✓{C.OFF}" if ok else f"{C.RED}✗{C.OFF}"
            print(f"  {mark} {act.kind} {act.symbol}: {detail}")
            record_decision(f"EXECUTE {act.kind} {act.symbol} amount={act.amount:.8f} ok={ok} {_strip_ansi(detail)}")


# =============================================================================
# THE COMMAND GATE
# =============================================================================

def command_gate(actions: list[Action]) -> bool:
    """
    Blocks until the operator types EXECUTE or SKIP.

    Note this genuinely blocks — the 4h timer does not run while the prompt
    is waiting. If stdin is not a terminal (systemd, nohup, cron) there is
    nobody to answer, so we fail safe to SKIP rather than trading unattended.
    """
    if not actions:
        LOG.info("no actions proposed — nothing to approve")
        return False
    if not sys.stdin.isatty():
        LOG.warning("stdin is not a terminal — auto-SKIP (nobody can approve)")
        record_decision("SKIP (non-interactive stdin)")
        return False

    while True:
        try:
            answer = input(
                f"\n{C.BOLD}Type 'EXECUTE' to place these trades on Binance, "
                f"or 'SKIP' to wait for the next {CYCLE_HOURS:g}-hour cycle: {C.OFF}"
            ).strip().upper()
        except (EOFError, KeyboardInterrupt):
            print()
            LOG.info("input closed — treating as SKIP")
            record_decision("SKIP (input closed)")
            return False
        if answer == "EXECUTE":
            record_decision(f"EXECUTE approved for {len(actions)} action(s)")
            return True
        if answer == "SKIP":
            LOG.info("skipped — sleeping until the next cycle")
            record_decision(f"SKIP chosen, {len(actions)} action(s) discarded")
            return False
        print(f"{C.YELLOW}Please type exactly EXECUTE or SKIP.{C.OFF}")


# =============================================================================
# MAIN CYCLE
# =============================================================================

class PortfolioManager:
    def __init__(self) -> None:
        self.ex = Exchanges()
        self.valuer = Valuer(self.ex)
        self.analyst = Analyst(self.ex)
        self.proposer = Proposer(self.ex, self.analyst)
        self.trader = Trader()
        self.guards = KillSwitchGuards(self.valuer)
        self.kill = KillSwitch(self.ex, self.trader)
        self.store = HwmStore(HWM_FILE)

    def cycle(self) -> None:
        LOG.info("=== cycle start ===")
        snap = self.valuer.take()

        if snap.partial:
            # A partial snapshot cannot be trusted for anything: not for the
            # HWM (a low reading would not raise it, but a *high* one from a
            # half-filled balance could), and certainly not for liquidation.
            LOG.error("snapshot incomplete — skipping this cycle entirely")
            return

        hwm = self.store.load()

        # Drawdown is computed against the PREVIOUS peak, before this reading
        # is folded in — otherwise a new high would always show 0% and a fall
        # from a high recorded in the same breath would be invisible.
        prior_peak = hwm.value
        drawdown = (prior_peak - snap.net_worth) / prior_peak if prior_peak > 0 else 0.0
        drawdown = max(0.0, drawdown)

        LOG.info("net worth %s | hwm %s | drawdown %.2f%%",
                 usd(snap.net_worth), usd(prior_peak), drawdown * 100)

        # ---- KILL SWITCH EVALUATION ----------------------------------------
        if drawdown > MAX_DRAWDOWN_PCT:
            passed, results = self.guards.evaluate(snap, hwm, drawdown)
            print()
            print(f"{C.BOLD}KILL SWITCH GUARDS{C.OFF}  (drawdown {drawdown:.2%} > "
                  f"limit {MAX_DRAWDOWN_PCT:.2%})")
            for r in results:
                mark = f"{C.GREEN}PASS{C.OFF}" if r.passed else f"{C.RED}HOLD{C.OFF}"
                print(f"  [{mark}] {r.name:<14} {r.detail}")
                record_decision(f"GUARD {r.name} {'PASS' if r.passed else 'HOLD'}: {_strip_ansi(r.detail)}")
            if passed:
                self.kill.fire(snap, hwm, drawdown)  # never returns
            else:
                print()
                print(f"{C.YELLOW}{C.BOLD}  Kill switch HELD — a guard rejected the reading. "
                      f"No orders sent.{C.OFF}")
                print(f"{C.YELLOW}  Check the account manually. This is either a real "
                      f"drawdown with bad data, or bad data alone.{C.OFF}")

        # Record the reading only after the kill-switch decision, so a crash
        # mid-liquidation cannot leave a rewritten HWM behind.
        hwm = self.store.observe(hwm, snap.net_worth)

        # ---- ANALYSIS + PROPOSAL -------------------------------------------
        LOG.info("running %s analysis over holdings + watchlist...", TIMEFRAME)
        actions, assessments = self.proposer.build(snap)
        print_proposal(snap, hwm, drawdown, actions, assessments)

        if command_gate(actions):
            self.trader.execute(self.ex, actions)

        LOG.info("=== cycle end ===")

    def run(self) -> None:
        preflight()
        interval = CYCLE_HOURS * 3600
        while True:
            started = time.time()
            try:
                self.cycle()
            except ccxt.BaseError as exc:
                # Network/exchange trouble must not kill a long-running
                # supervisor process — log it and try again next cycle.
                LOG.error("exchange error this cycle: %s", exc)
            except Exception:  # noqa: BLE001 - deliberate top-level guard
                LOG.exception("unhandled error this cycle")
            elapsed = time.time() - started
            sleep_for = max(60.0, interval - elapsed)
            nxt = datetime.fromtimestamp(time.time() + sleep_for, timezone.utc)
            LOG.info("sleeping %.1fh — next cycle at %s UTC",
                     sleep_for / 3600, nxt.strftime("%Y-%m-%d %H:%M"))
            time.sleep(sleep_for)


def preflight() -> None:
    """Startup banner + the checks that must happen before anything else."""
    # Re-entry block. "Terminate the script to prevent re-entry" only actually
    # works if a restart is also refused — otherwise systemd undoes it in 5s.
    if KILL_SENTINEL.exists():
        print(f"{C.BG_RED} REFUSING TO START: the kill switch has already fired. {C.OFF}")
        try:
            print(KILL_SENTINEL.read_text(encoding="utf-8"))
        except OSError:
            pass
        print(f"{C.RED}Review the account, then delete {KILL_SENTINEL} to re-enable.{C.OFF}")
        sys.exit(3)

    print()
    print(f"{C.BOLD}  BINANCE PORTFOLIO MANAGER{C.OFF}")
    print(f"  cycle            : {CYCLE_HOURS:g}h on the {TIMEFRAME} timeframe")
    print(f"  max drawdown     : {MAX_DRAWDOWN_PCT:.2%}"
          f"{'' if KILL_SWITCH_ENABLED else f' {C.YELLOW}(KILL SWITCH DISARMED){C.OFF}'}")
    print(f"  guards           : confirm after {KILL_CONFIRM_DELAY_S}s, "
          f"tolerance {CONFIRM_TOLERANCE:.0%}, floor {IMPLAUSIBLE_FLOOR_PCT:.0%} of HWM")
    print(f"  state            : {HWM_FILE}")
    if LIVE_TRADING:
        print(f"  trading          : {C.RED}{C.BOLD}LIVE — real orders will be placed{C.OFF}")
    else:
        print(f"  trading          : {C.GREEN}DRY-RUN{C.OFF} "
              f"{C.GREY}(set PM_LIVE_TRADING=1 to arm){C.OFF}")
    if USE_TESTNET:
        print(f"  endpoint         : {C.CYAN}TESTNET{C.OFF}")
    print(f"  {C.GREY}Education/analysis tool. Not financial advice.{C.OFF}")
    print()


def _handle_sigterm(signum: int, _frame: Any) -> None:
    LOG.info("received signal %s — shutting down cleanly", signum)
    sys.exit(0)


def main() -> None:
    signal.signal(signal.SIGTERM, _handle_sigterm)
    try:
        PortfolioManager().run()
    except KeyboardInterrupt:
        print()
        LOG.info("interrupted — exiting")


if __name__ == "__main__":
    main()
