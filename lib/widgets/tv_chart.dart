// TradingView Lightweight Charts renderer — platform-conditional:
// Android drives a WebView (tv_chart_io.dart); web embeds a same-origin
// iframe (tv_chart_web.dart). Payload building is shared (tv_payload.dart).
export 'tv_chart_io.dart' if (dart.library.js_interop) 'tv_chart_web.dart';
