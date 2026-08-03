# Gold Master Pro (GMP)

AI-assisted **gold (XAUUSD) trading-analysis** app — Flutter, zero-cost
stack. Standalone project (no relation to any other repo on this machine).
Owner: Gerrit Bezuidenhout; tester: Luan (luanrohm34@gmail.com).
Distribution: GitHub Releases APK (sideload) from
`gerritbezuidenhout8-boop/gold_master_pro`.

Positioning rule: outputs are **education/analysis, not financial advice**
— the disclaimer on Home and in test emails is deliberate; never frame
signals as recommendations to trade.

## Environment (this Windows PC)

- **The repo lives at `C:\dev\gold_master_pro`** — alongside the toolchain,
  deliberately *off* OneDrive. A second working copy exists under
  `OneDrive\Documents\Claude\Claude coding projects\Gold master pro\` and is
  a **stale duplicate, not a mirror**: it was already a commit behind. Work
  there and you will diverge silently. OneDrive also syncs `build/` and
  `.dart_tool/` for no benefit and can leave files as cloud placeholders
  that Gradle reads as empty.
- Flutter `C:\dev\flutter` (on PATH) · JDK `C:\dev\java\jdk-21.0.11+10`
  (JAVA_HOME) · Android SDK `C:\dev\Android\Sdk` (ANDROID_HOME)
- **Keep `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true`** (user env
  var): this network's DNS breaks Java's dual-stack resolver; Gradle and
  sdkmanager fail without it.
- `flutter build windows`, `pub get`/`pub add`, **and now `flutter analyze`**
  hit "enable Developer Mode" (plugin symlinks). Since v1.1.2 this fires on
  a plain `analyze` too, because `flutter_local_notifications` ships a
  Windows implementation that pulls desktop plugin registration into every
  resolve. **Android/web builds and tests are unaffected** — treat it as
  noise unless targeting Windows desktop, and just re-run: once dependencies
  resolve, `analyze` completes normally.
- No `gh` CLI. Git pushes work via Git Credential Manager. Read CI results
  from the public API instead:
  `api.github.com/repos/<owner>/<repo>/commits/<sha>/check-runs`.
- **Stale `.git/index.lock`:** if git reports "Another git process seems to
  be running", check for a real one (`Get-CimInstance Win32_Process -Filter
  "Name='git.exe'"`) before deleting the lock. A crashed git run on
  2026-08-01 left a 0-byte lock that got copied into both working trees.

## Commands

| | |
|---|---|
| `flutter analyze` / `flutter test` | keep both green; **185 tests** (v1.1.2) |
| `flutter build apk --release` | needs the three env vars above |
| `flutter build web` | web preview build |
| `dart run tool/prepare_logo.dart` | regenerate branding from source jpeg |
| `dart run flutter_launcher_icons` | regenerate launcher icons |

**Release = tag push:** bump `version:` in pubspec **and
`AppConstants.appVersion`**, commit, push, then
`git tag vX.Y.Z && git push origin vX.Y.Z` → `.github/workflows/release.yml`
builds and attaches `app-release.apk` + `gmp-web.zip` (~6 min). Download
URL pattern: `releases/download/vX.Y.Z/app-release.apk`. Verify via the
public `releases/expanded_assets/<tag>` page. Deleting a tag turns its
release into an unpublished draft. `deploy-web.yml` needs Pages enabled
(currently not) and is therefore **`workflow_dispatch`-only since v1.1.2** —
it no longer runs on push, because a permanently red check trains you to
ignore red checks. Re-enable the push trigger when Pages is turned on.
CI pins Flutter
**3.44.7** — check new deps against that, not just against local Flutter.

**Always run `flutter analyze && flutter test` before tagging.** Two
workflows check this, but neither removes the need to run it locally:
`ci.yml` (analyze + test + web build) guards pushes to `main`, and **since
v1.1.2 `release.yml` runs analyze + test before it builds**, so a tag can no
longer publish an APK from red code. The trap the local run still catches:
a tag is normally pushed seconds after the commit, *before* `ci.yml`
reports — so without checking locally you learn it was broken only from the
failed release run, which costs a tag deletion that leaves an unpublished
draft release behind.

## Architecture (lib/)

- `services/market_data.dart` — swappable `MarketData.instance` facade
  (candles, candle stream, quote stream, XAU spot). `BinanceMarketData` =
  PAXG/USD via keyless Binance REST + WebSocket, bundled snapshot fallback
  in `assets/candles/`.
- `services/spot_gold_data.dart` — **the live default** (set in `main()`):
  candles from COMEX **GC=F futures** (Yahoo v8 chart API, keyless, needs
  a Mozilla User-Agent; ~0.1% from spot; **no 4h interval → H4 aggregated
  from H1** via `aggregateCandles`); ticker/alerts from **Swissquote**
  public XAU/USD bbo (mid of first spread profile) with gold-api.com
  fallback. **On web (Yahoo / Swissquote block CORS): candles fall back to
  Binance PAXG, live quotes poll gold-api.com's real XAU spot** (v1.0.9).
  **v1.1.0: `_alignToSpot()` rebases every candle series (GC=F or PAXG) by
  `spot − lastClose` so the chart reads at true gold-api XAU spot levels;
  `_spotOffset` is reused to shift streamed bars. gold-api has no OHLC, so a
  proxy still supplies bar *shapes* — only levels are spot (shift-invariant
  for RSI/MACD/StochRSI).** **v1.1.2 — the jumping-chart fix: never let two
  vendors write one bar.** The ticker was Swissquote, the candle alignment
  was gold-api, and `_spotOffset` was frozen at load, so the forming bar
  flipped between two levels and painted red candles on green moves (open
  from one source, close from the other). Now `_spotQuote()` is the single
  spot source for **both** `quoteStream` and `_alignToSpot`; every tick
  records `_lastSpot`; and `anchorCandleToSpot` (pure, tested) re-anchors
  each streamed bar so its close lands on live spot with open/high/low
  shifted by the same delta — level from spot, shape (and therefore colour)
  from the proxy. ChartScreen mirrors this: `_applySpot()` re-runs after
  every `mergeCandle`, so spot always wins for the live close. Yahoo
  delisted `XAUUSD=X` — GC=F is the only gold symbol. Chart caption reads
  `SpotGoldMarketData.candleSource`. True spot XAUUSD *candles* are
  paid-only; this is the free ceiling.
- `indicators/` — pure, tested Dart: `Smma`, `Rsi`/`StochRsi`/
  `RsiDivergence` (pivot-based), `Macd` (EMA 12/26/9 → line/signal/
  histogram), `Adx` + ±DI (Wilder, trend strength), `Atr` (Wilder),
  `KeyLevels` (**UTC midnight days, weeks start Monday 00:00 UTC** — never
  mix with NY-5pm), `Fibonacci.auto` (pivot strength 5, lookback 120),
  `CandlestickDetector` (14 threshold patterns, geometric only). MACD/ADX
  surface in the Analysis Momentum + Trend-Strength cards.
- `ai/gold_master_engine.dart` — deterministic weighted rubric (5
  components → score 0-100, bias at 60/40, confidence, clarity, template
  narrative). No Flutter imports, no network. Any future LLM layer
  narrates computed numbers, never invents them. `analyze()` takes
  `intradayName`/`intradayWord` so it can run on any intraday TF (Analysis
  screen runs it across M5/M15/M30/H1; Home keeps hourly defaults).
- `ai/trade_plan_engine.dart` — turns a high-conviction score into a
  concrete plan: LONG at score ≥ 80, SHORT at ≤ 20, else null (no signal).
  Entry near price, stop = recent swing ± buffer clamped to [0.8,3]×ATR
  (`indicators/atr.dart`, Wilder), TP1/TP2 = nearest key levels beyond
  entry with R-multiple fallback. `screens/trade_plan/` renders it
  (mockup screen 8); reached by tapping Home's AI Recommendation card.
  Education/analysis only — disclaimer on the screen. **`generate()` is the
  only entry point: the 80/20 gate is deliberate and flat is a valid state
  — never add an always-directional variant (v1.1.0 shipped one, and it was
  removed in v1.1.1 at the owner's request). Both the Trade Plan screen and
  the Analysis "Trade Signal" card use it and show a "no high-conviction
  signal" state in the middle.** `TradePlan` also carries
  `conviction`/`convictionLabel`/`isHighConviction` and `toMap`/`fromMap`
  (a signal persists its plan by value).
- **Chart renderer:** Android = TradingView **Lightweight Charts v5.2.0**
  (`assets/tv/` bundled standalone JS + chart.html; `widgets/chart_widget.dart`
  WebView + `tvChartPayload` serializer; refit only on timeframe change;
  StochRSI uses the v5 panes API). All other platforms fall back to
  `widgets/gmp_chart.dart` + `widgets/indicators/` — k_chart_plus with
  custom indicators (SMMA overlay, StochRSI subpane, divergence markers).
  Custom indicators cache per-candle values in an **Expando keyed by
  entity**, so the indicator instances MUST be the same objects in
  `prepare()` (calc) and the widget (draw) — they're static on GmpChart.
  **v1.1.0: ChartScreen folds each live spot tick into the forming candle
  (`_onSpot`, throttled); StochRSI value shows both on the `IndicatorBar`
  and as an on-chart `#readout` overlay in chart.html.** Gotcha: the browser
  caches `chart.html` — hard-refresh after editing it.
- `screens/onboarding/` — one-time intro (3 slides), gated by
  `AppSettings.onboardingComplete`; `main.dart` shows it before the shell.
- `screens/about/` — About Gold Master Pro (Home drawer): positioning,
  feature summary, credits and the not-financial-advice disclaimer. Credits
  **Luan Rohm** as designer and maker via `AppConstants.author`. Version
  text comes from `AppConstants.appVersion` — **bump it alongside
  `version:` in pubspec** (a test asserts the format, not the value).
- `services/economic_calendar.dart` + `screens/calendar/` — this-week
  ForexFactory calendar (nfs.faireconomy.media weekly JSON, keyless; live
  native, bundled `assets/calendar/ff_thisweek.json` snapshot on web/offline
  — no CORS). Reached from the Home drawer.
- `state/alerts_controller.dart` — app-wide singleton ChangeNotifier
  (deliberately no Riverpod). `widgets/alert_watcher.dart` wraps the
  shell, evaluates `AlertEngine.fires` crossings, one-shot until re-armed.
- **Notifications (v1.1.2).** `services/notifications.dart` — swappable
  `Notifications.instance` seam like `MarketData`: `NoopNotifications` is
  the default (so tests and unconfigured platforms never touch a platform
  channel), `main()` installs `LocalNotifications`
  (`flutter_local_notifications`, Android/iOS/macOS/Windows), and
  `RecordingNotifications` is the test double. Everything that fires posts
  an OS notification **and** an in-app SnackBar. Android needs
  `POST_NOTIFICATIONS` in the manifest plus **core library desugaring** in
  `android/app/build.gradle.kts` — the plugin does not link without it.
  Ids live in `GmpNotificationIds` so a newer notification of a kind
  replaces the older one. Notification copy follows the positioning rule:
  "setup detected … analysis only", never an instruction to trade.
- **`state/plan_scout.dart` — why signals notify at all.** Before it, a
  plan was only generated inside the Trade Plan screen's refresh, so a
  score reaching 80 while you were anywhere else was silently missed.
  The scout runs the same `GoldMasterEngine` → `TradePlanEngine` →
  `SignalController.issue` chain off the live quote stream, throttled to
  `minInterval` (1 min — the score only moves on new candles) with daily
  candles cached for 15 min. Network-tolerant by design: it returns null
  rather than throwing, because it runs inside a stream listener that must
  not die. Gated by `AppSettings.scoreAlerts` ("Signal Alerts", default
  on).
- **Signal lifecycle — one trade at a time.** `state/signal_controller.dart`
  (2nd ChangeNotifier singleton) owns it: `canIssue` is the gate, so a new
  plan opens only when nothing is running, and the open trade closes *only*
  at its take-profit or stop — no expiry, and re-analysing never replaces
  it. `ai/signal_engine.dart` is the pure rule, applied two ways:
  `resolve()` on a live tick and `resolveFromCandles()` replayed on launch
  so a trade that completed while the app was shut still settles. Exits
  book **at the level** (clean +rr1 / −1R); a bar touching **both** levels
  counts as the stop, never flattering the record. `models/trade_signal.dart`
  stores the plan **by value** so a closed signal keeps the levels it was
  judged on. Persisted via `services/signal_store.dart`
  (`gmp-signals-v1`). `AlertWatcher` feeds prices to both controllers —
  signal resolution is deliberately **not** gated by the price-alerts
  toggle (it is state, not a notification). TP1 closes the trade; TP2 is
  displayed as an untracked runner.
- `services/journal_store.dart` / `alert_store.dart` / `app_settings.dart`
  — local-first via shared_preferences, swappable `.instance` seams.
  Firebase/cloud runbooks: `docs/firebase_setup.md`,
  `docs/alerts_backend.md` (Cloudflare Worker skeleton). Open environment
  traps (browser-pane screenshots, cross-origin request logging, stale
  `chart.html`): `docs/known_issues.md`.
- Theme `core/theme/app_theme.dart`: black `#0A0A0B` + gold `#E3B84C`
  system; reusable `GmpCard`/`SectionLabel`/`GmpPill`/`StatTile`/
  `GoldButton`/`ScoreGauge`. Branding assets `assets/branding/` from the
  source jpeg via `tool/prepare_logo.dart`.

## Hard-won gotchas

- **Perf:** ChartScreen lives in the RootShell `IndexedStack`, so its
  streams run even offstage. Whole-set recompute per tick froze the app
  once — stream updates are throttled to ~1 rebuild/sec (`_dirty` +
  periodic timer). Keep new per-tick work behind that throttle.
- **Tests:** widget tests must swap `MarketData.instance`,
  `Watchlist.fetch`, `AlertsController.instance` (real sockets/timers
  fail the pending-timer invariant) and set
  `SharedPreferences.setMockInitialValues`. Dispose trees with
  `pumpWidget(SizedBox())`. ListViews virtualize — `scrollUntilVisible`
  before asserting below-fold. `SectionLabel`/`GmpPill` UPPERCASE their
  text. The chart-screen throttle needs `pump(Duration(seconds: 1))`.
- Markets tab auto-refreshes on `AppSettings.autoRefreshSeconds`
  (**default 1 s** since v1.1.2, persisted) from gold-api.com (also
  Silver/Copper/BTC/ETH). One refresh = **five parallel** keyless requests,
  and `_load()` skips a tick while a round is in flight, so the real ceiling
  is one round per round-trip. If gold-api starts 429ing, raise the interval
  or batch the five symbols — don't lower the floor below 1 s.
