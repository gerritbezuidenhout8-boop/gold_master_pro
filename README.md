# Gold Master Pro

AI-assisted Gold (XAUUSD) market analysis app — live price, Gold Master
Score, candlestick recognition, Fibonacci, key levels, SMMA overlays,
alerts and a trading journal. Flutter, targeting Android, Web and
Windows (iOS later via a Mac or CI).

> Analysis output is educational only and is not financial advice.

## Status — zero-cost build

| Step | Status |
|------|--------|
| 1. Chart engine (k_chart_plus + custom SMMA overlay) | ✅ |
| 2. Live data (Binance PAXG REST+WebSocket, gold-api spot, offline fallback) | ✅ |
| 3. Indicator engine (key levels · auto-Fibonacci · 14 candle patterns) | ✅ |
| 4. Gold Master Score (deterministic rubric + narrative, Home dashboard) | ✅ |
| 5. Trading journal (local-first; Firebase sync optional — docs/firebase_setup.md) | ✅ |
| 6. Alerts (in-app live; Cloudflare Worker + FCM for background — docs/alerts_backend.md) | ✅ |
| 7. Ship free (GitHub + Actions CI + Pages + APK releases) | ✅ |

Candles are PAXG/USD (tokenized gold, tracks spot) from Binance's
keyless public API; true XAU spot shown from gold-api.com. Swap in a
licensed XAUUSD feed via `lib/services/market_data.dart` when the app
ever commercializes.

Everything above runs on **$0**: keyless market data, on-device storage,
free GitHub Actions/Pages. Optional cloud features (Firebase sign-in,
background push) also fit inside free tiers — see `docs/`.

## Run

```sh
flutter run -d chrome    # web
flutter run -d windows   # desktop
flutter run              # attached Android device
```

Tooling on this machine lives outside OneDrive: Flutter at
`C:\dev\flutter`, Android SDK at `C:\dev\Android\Sdk`, JDK 21 at
`C:\dev\java`. `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` is
set (user scope) because this network's DNS breaks Java's dual-stack
resolver.

## Tests

```sh
flutter test
```

## CI / CD (GitHub Actions, free for public repos)

| Workflow | Trigger | Does |
|----------|---------|------|
| `.github/workflows/ci.yml` | push / PR to `main` | analyze · test · build web |
| `.github/workflows/deploy-web.yml` | push to `main` | deploy web to GitHub Pages |
| `.github/workflows/release.yml` | tag `v*` | build APK + web zip, attach to a Release |

First-time setup after pushing to GitHub: repo **Settings → Pages →
Source: GitHub Actions**. Then every push to `main` publishes the web
app; tag `git tag v1.0.0 && git push --tags` to cut an APK release.

## License

MIT (see `LICENSE`) — a permissive default; change it if you prefer.
