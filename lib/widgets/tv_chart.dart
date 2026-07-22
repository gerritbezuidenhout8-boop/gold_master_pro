import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import '../indicators/rsi.dart';
import '../indicators/smma.dart';
import '../models/candle.dart';

/// Serializes candles + indicator overlays into the JSON shape consumed
/// by assets/tv/chart.html (TradingView Lightweight Charts v5).
Map<String, dynamic> tvChartPayload(
  List<Candle> candles, {
  bool stochRsi = true,
  bool divergence = true,
}) {
  int t(Candle c) => c.time.millisecondsSinceEpoch ~/ 1000;
  final closes = [for (final c in candles) c.close];

  final payload = <String, dynamic>{
    'candles': [
      for (final c in candles)
        {
          'time': t(c),
          'open': c.open,
          'high': c.high,
          'low': c.low,
          'close': c.close,
        },
    ],
    'volume': [
      for (final c in candles)
        {
          'time': t(c),
          'value': c.volume,
          'color': c.close >= c.open
              ? 'rgba(37,198,133,0.35)'
              : 'rgba(229,72,77,0.35)',
        },
    ],
    'smma': [
      for (final period in const [21, 50, 200])
        () {
          final s = Smma.compute(closes, period);
          return [
            for (var i = 0; i < candles.length; i++)
              if (s[i] != null) {'time': t(candles[i]), 'value': s[i]},
          ];
        }(),
    ],
  };

  if (stochRsi) {
    final sr = StochRsi.compute(closes);
    payload['stochK'] = [
      for (var i = 0; i < candles.length; i++)
        if (sr.k[i] != null) {'time': t(candles[i]), 'value': sr.k[i]},
    ];
    payload['stochD'] = [
      for (var i = 0; i < candles.length; i++)
        if (sr.d[i] != null) {'time': t(candles[i]), 'value': sr.d[i]},
    ];
  }

  if (divergence) {
    payload['markers'] = [
      for (final e in RsiDivergence.detect(candles))
        {
          'time': t(candles[e.index]),
          'position': e.type == DivergenceType.bullish
              ? 'belowBar'
              : 'aboveBar',
          'color':
              e.type == DivergenceType.bullish ? '#25C685' : '#E5484D',
          'shape': e.type == DivergenceType.bullish
              ? 'arrowUp'
              : 'arrowDown',
          'text': e.type == DivergenceType.bullish ? 'Bull div' : 'Bear div',
        },
    ];
  }

  return payload;
}

/// TradingView Lightweight Charts renderer (Android WebView). The page is
/// a bundled asset; candles and overlays are pushed as JSON. Non-Android
/// platforms keep the native GmpChart — the caller gates on platform.
class TvChart extends StatefulWidget {
  const TvChart({
    super.key,
    required this.candles,
    required this.timeframe,
    required this.showStochRsi,
    required this.showDivergence,
  });

  final List<Candle> candles;
  final String timeframe;
  final bool showStochRsi;
  final bool showDivergence;

  @override
  State<TvChart> createState() => _TvChartState();
}

class _TvChartState extends State<TvChart> {
  late final WebViewController _controller;
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _pageReady = true;
          _push(fit: true);
        },
      ))
      ..loadFlutterAsset('assets/tv/chart.html');
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
    if (!_pageReady || widget.candles.isEmpty) return;
    final json = jsonEncode(tvChartPayload(
      widget.candles,
      stochRsi: widget.showStochRsi,
      divergence: widget.showDivergence,
    ));
    // jsonEncode(json) turns the payload into a safely-escaped JS string
    // literal, so no manual escaping is needed.
    _controller.runJavaScript(
        'window.gmp && window.gmp.setAll(${jsonEncode(json)}, $fit)');
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
