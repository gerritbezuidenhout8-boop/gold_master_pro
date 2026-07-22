// TradingView Lightweight Charts renderer (assets/tv/chart.html) —
// platform-conditional: Android drives a WebView (chart_widget_io.dart);
// web embeds a same-origin iframe (chart_widget_web.dart). Payload
// building is shared (tv_payload.dart).
export 'chart_widget_io.dart'
    if (dart.library.js_interop) 'chart_widget_web.dart';
