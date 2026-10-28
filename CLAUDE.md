# Gold Master Pro (GMP)

AI-assisted **gold (XAUUSD) trading-analysis** Flutter app, zero-cost stack.
Owner: Gerrit Bezuidenhout; tester: Luan (luanrohm34@gmail.com). Distributed
as a GitHub Releases APK from `gerritbezuidenhout8-boop/gold_master_pro`.
**Outputs are education/analysis, not financial advice.** Never frame signals
as recommendations to trade. Notification copy: "setup detected … analysis only".

**Full design history and the reasons behind each rule: `docs/history.md`.
Read the section for an area before changing it.**

## Environment (Windows PC)
- Repo: `C:\dev\gold_master_pro`. The OneDrive copy is a **stale duplicate**, so never work there.
- Flutter `C:\dev\flutter` · JDK `C:\dev\java\jdk-21.0.11+10` (JAVA_HOME) · SDK `C:\dev\Android\Sdk` (ANDROID_HOME).
- Keep `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` (Gradle/sdkmanager fail without it).
- "Enable Developer Mode" on `analyze`/`pub get`/windows build is noise. Re-run it.
- No `gh` CLI. Read CI via `api.github.com/repos/<owner>/<repo>/commits/<sha>/check-runs`.
- Stale `.git/index.lock`: check for a running git.exe before deleting it.

## Commands
| | |
|---|---|
| `flutter analyze` / `flutter test` | keep both green; **252 tests** (v1.1.6) |
| `flutter build apk --release` | needs the env vars above |
| `flutter build web` | web preview |
| `dart run tool/prepare_logo.dart` / `dart run flutter_launcher_icons` | branding / icons |

**Release:** bump `version:` in pubspec **and** `AppConstants.appVersion`, commit,
push, then `git tag vX.Y.Z && git push origin vX.Y.Z` (`release.yml`, ~6 min).
**Always run `flutter analyze && flutter test` locally before tagging.** CI pins
Flutter **3.44.7**, so check new deps against it. `deploy-web.yml` is
`workflow_dispatch`-only until Pages is enabled.

## Architecture (lib/)
- `services/market_data.dart`: `MarketData.instance` facade; Binance PAXG + snapshot fallback; `floorToTimeframe`/`bucketCandle`/`normalizeCandles`.
- `services/spot_gold_data.dart`: live default. GC=F candles (Yahoo; H4 aggregated from H1), spot from Swissquote/gold-api; on web, PAXG + gold-api.
- `indicators/`: pure, tested (SMMA, RSI/StochRSI/divergence, MACD, ADX, ATR, KeyLevels, Fibonacci, candlestick patterns).
- `ai/gold_master_engine.dart`: deterministic 0-100 score. `ai/trade_plan_engine.dart`: plans + **all tuning constants**. `ai/signal_engine.dart`: pure resolve rules. `ai/news_guard.dart`: USD news blackout.
- `state/`: `AlertsController`, `SignalController` (one trade at a time), `PlanScout` (background scan + settle). Singleton ChangeNotifiers, no Riverpod.
- `services/notifications.dart`: `Notifications.instance` seam (Noop default, `LocalNotifications` in main, `RecordingNotifications` in tests).
- Chart: Android = TradingView Lightweight Charts v5.2.0 (`assets/tv/`, `widgets/chart_widget.dart`); other platforms = `widgets/gmp_chart.dart` (indicator instances static, Expando cache). Hard-refresh after editing `chart.html`.
- Screens: onboarding, about (`AppConstants.author`/`appVersion`), calendar, trade_plan, signal_journal. Stores: shared_preferences `.instance` seams.
- Theme `core/theme/app_theme.dart`: black `#0A0A0B` + gold `#E3B84C`.

## Hard rules
- Never let two vendors write one bar. `_spotQuote()` is the single spot source for `quoteStream` and `_alignToSpot`, and `anchorCandleToSpot` re-anchors live bars.
- Never emit a candle whose time is not a bar boundary (W1 = Monday 00:00 UTC, D1 = UTC midnight). KeyLevels use UTC days, never NY-5pm.
- `TradePlanEngine.generate()` is the only plan entry point: LONG ≥ 80, SHORT ≤ 20, flat is valid. Never add an always-directional variant.
- `maxStopPips` (500) is applied last. The intraday TP cap (2000 pips) covers M1–**H1**; H4/D1/W1 are exempt. TP floor 1R.
- Tuning constants live only in `trade_plan_engine.dart`; callers default to them.
- Settlement (`SignalController.onPrice`, `PlanScout.settle`) is **never** gated by alert/notification toggles.
- Keep `AlertWatcher.initState`'s `requestPermission()` call (Android 13+ runtime permission).
- In candle replay a bar counts when its **end** is after `openedAt`. Exits book at the level, and a bar touching both levels counts as the stop.
- Trailing stop ratchets via `withPeak` only. Signals store their plan by value.
- `PlanScout`/news code catches `Error` as well as `Exception`, because it runs in a stream listener that must not die.
- Any LLM layer narrates computed numbers and never invents them.

## Gotchas
- Perf: ChartScreen runs offstage in an IndexedStack. Keep per-tick work behind the ~1 s `_dirty` throttle.
- Tests: swap `MarketData.instance`, `Watchlist.fetch`, `AlertsController.instance`; pass `calendar:` to `PlanScout`; set `SharedPreferences.setMockInitialValues`; dispose with `pumpWidget(SizedBox())`; `scrollUntilVisible` below the fold; `SectionLabel`/`GmpPill` uppercase their text; chart throttle needs `pump(Duration(seconds: 1))`.
- Markets auto-refresh (default 1 s) sends 5 parallel gold-api requests. If it 429s, raise the interval; don't go below 1 s.
