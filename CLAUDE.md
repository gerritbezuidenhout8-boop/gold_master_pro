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

- Flutter `C:\dev\flutter` (on PATH) · JDK `C:\dev\java\jdk-21.0.11+10`
  (JAVA_HOME) · Android SDK `C:\dev\Android\Sdk` (ANDROID_HOME)
- **Keep `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true`** (user env
  var): this network's DNS breaks Java's dual-stack resolver; Gradle and
  sdkmanager fail without it.
- `flutter build windows` and some `pub add`s hit "enable Developer Mode"
  (plugin symlinks). **Android/web builds and tests are unaffected** —
  treat the message as noise unless targeting Windows desktop.
- No `gh` CLI. Git pushes work via Git Credential Manager.

## Commands

| | |
|---|---|
| `flutter analyze` / `flutter test` | keep both green; ~103 tests |
| `flutter build apk --release` | needs the three env vars above |
| `flutter build web` | web preview build |
| `dart run tool/prepare_logo.dart` | regenerate branding from source jpeg |
| `dart run flutter_launcher_icons` | regenerate launcher icons |

**Release = tag push:** bump `version:` in pubspec, commit, push, then
`git tag v1.0.x && git push origin v1.0.x` → `.github/workflows/release.yml`
builds and attaches `app-release.apk` + `gmp-web.zip` (~6 min). Download
URL pattern: `releases/download/v1.0.x/app-release.apk`. Verify via the
public `releases/expanded_assets/<tag>` page. Deleting a tag turns its
release into an unpublished draft. `deploy-web.yml` needs Pages enabled
(currently not) — its failure on push is expected.

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
  fallback. **`kIsWeb` ⇒ everything falls back to Binance** (Yahoo /
  Swissquote block CORS). Yahoo delisted `XAUUSD=X` — GC=F is the only
  gold symbol. Chart caption reads `SpotGoldMarketData.candleSource`.
  True spot XAUUSD *candles* are paid-only; this is the free ceiling.
- `indicators/` — pure, tested Dart: `Smma`, `Rsi`/`StochRsi`/
  `RsiDivergence` (pivot-based), `KeyLevels` (**UTC midnight days, weeks
  start Monday 00:00 UTC** — never mix with NY-5pm), `Fibonacci.auto`
  (pivot strength 5, lookback 120), `CandlestickDetector` (14 threshold
  patterns, geometric only).
- `ai/gold_master_engine.dart` — deterministic weighted rubric (5
  components → score 0-100, bias at 60/40, confidence, clarity, template
  narrative). No Flutter imports, no network. Any future LLM layer
  narrates computed numbers, never invents them.
- `widgets/gmp_chart.dart` + `widgets/indicators/` — k_chart_plus with
  custom indicators (SMMA overlay, StochRSI subpane, divergence markers).
  Custom indicators cache per-candle values in an **Expando keyed by
  entity**, so the indicator instances MUST be the same objects in
  `prepare()` (calc) and the widget (draw) — they're static on GmpChart.
- `state/alerts_controller.dart` — app-wide singleton ChangeNotifier
  (deliberately no Riverpod). `widgets/alert_watcher.dart` wraps the
  shell, evaluates `AlertEngine.fires` crossings, one-shot until re-armed.
- `services/journal_store.dart` / `alert_store.dart` / `app_settings.dart`
  — local-first via shared_preferences, swappable `.instance` seams.
  Firebase/cloud runbooks: `docs/firebase_setup.md`,
  `docs/alerts_backend.md` (Cloudflare Worker skeleton).
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
  (default 5 s, persisted) from gold-api.com (also Silver/Copper/BTC/ETH).
