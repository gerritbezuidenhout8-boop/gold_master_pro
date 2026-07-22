import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../models/candle.dart';
import 'tv_payload.dart';

/// TradingView Lightweight Charts renderer for Flutter web: the bundled
/// chart page runs in a same-origin iframe and is driven by calling its
/// `gmp.setAll` directly.
class TvChart extends StatefulWidget {
  const TvChart({
    super.key,
    required this.candles,
    required this.timeframe,
    required this.showStochRsi,
    required this.showDivergence,
    this.onEngineFailed,
  });

  final List<Candle> candles;
  final String timeframe;
  final bool showStochRsi;
  final bool showDivergence;
  final VoidCallback? onEngineFailed;

  @override
  State<TvChart> createState() => _TvChartState();
}

class _TvChartState extends State<TvChart> {
  static int _instances = 0;

  late final String _viewType = 'gmp-tv-chart-${_instances++}';
  late final web.HTMLIFrameElement _iframe;

  @override
  void initState() {
    super.initState();
    _iframe =
        web.document.createElement('iframe') as web.HTMLIFrameElement
          ..src = ui_web.assetManager.getAssetUrl('assets/tv/chart.html');
    _iframe.style.setProperty('border', 'none');
    _iframe.style.setProperty('width', '100%');
    _iframe.style.setProperty('height', '100%');
    _iframe.addEventListener(
      'load',
      ((web.Event e) => _push(fit: true)).toJS,
    );
    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int viewId) => _iframe);
  }

  @override
  void didUpdateWidget(TvChart old) {
    super.didUpdateWidget(old);
    final refit = old.timeframe != widget.timeframe;
    if (refit ||
        !identical(old.candles, widget.candles) ||
        old.showStochRsi != widget.showStochRsi ||
        old.showDivergence != widget.showDivergence) {
      _push(fit: refit);
    }
  }

  void _push({required bool fit}) {
    if (widget.candles.isEmpty) return;
    // Same-origin, so the page's API is directly reachable. If the page
    // hasn't finished loading yet, the next throttled update lands.
    final win = _iframe.contentWindow as JSObject?;
    final gmp = win?.getProperty('gmp'.toJS);
    if (gmp == null || !gmp.isA<JSObject>()) return;
    final json = jsonEncode(tvChartPayload(
      widget.candles,
      stochRsi: widget.showStochRsi,
      divergence: widget.showDivergence,
    ));
    (gmp as JSObject).callMethod('setAll'.toJS, json.toJS, fit.toJS);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
