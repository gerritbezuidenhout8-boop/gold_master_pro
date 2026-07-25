# Known issues

Open problems and environment traps, kept here because the repo has no
issue tracker configured (no `gh` CLI on the dev box). Fix or delete an
entry when it stops being true.

## DEV-1 — Browser-pane screenshots fail: "not compositing frames"

**Status:** open · **Impact:** verification only, not a product bug

When verifying the web build in an in-app browser pane (Claude Code's
Browser pane / preview), `screenshot` fails with:

> the Browser pane is not displayed, so the page is not compositing frames

Flutter web renders through CanvasKit, which only paints frames while its
surface is actually visible. If the pane is hidden or collapsed the page
keeps running but produces no frames, so screenshots time out and
coordinate-based clicking is unusable. Nothing is wrong with the app.

**Workarounds**

- Display/expand the browser pane, then retry the screenshot.
- Verify without pixels — these all work while hidden:
  - `read_console_messages` for runtime errors,
  - `preview_logs` for what the server actually served,
  - `javascript_tool` for DOM/state probes, e.g.
    `!!document.querySelector('flt-glass-pane')` to confirm the engine
    booted.
- Prefer widget tests for behaviour. Every screen in `lib/screens/` has
  one; they assert real widget trees and never depend on compositing.

**Related traps**

- `read_network_requests` does **not** record cross-origin fetches. Use
  in-page resource timing instead:
  `performance.getEntriesByType('resource').map(r => r.name)`.
- A static file server plus browser cache will happily serve a stale
  `assets/tv/chart.html`. Hard-refresh (Ctrl+Shift+R) after editing it, or
  the chart looks unchanged. This is why the live StochRSI read-out is
  rendered by Flutter in `IndicatorBar` as well as inside the chart.
- Flutter web's first frame waits on `canvaskit.wasm` and fonts; DOM probes
  fired immediately after navigation can race it. Re-probe rather than
  concluding the app is broken.
