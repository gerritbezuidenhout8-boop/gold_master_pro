import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import '../models/candle.dart';
import 'tv_payload.dart';

/// TradingView Lightweight Charts renderer for Android (WebView). The
/// page is a bundled asset; candles and overlays are pushed as JSON.
/// Engine errors are reported through [onEngineFailed] so the caller can
/// fall back to the native renderer.
class ChartWidget extends StatefulWidget {
  const ChartWidget({
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
  State<ChartWidget> createState() => _ChartWidgetState();
}

class _ChartWidgetState extends State<ChartWidget> {
  late final WebViewController _controller;
  bool _pageReady = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..addJavaScriptChannel('GmpErr', onMessageReceived: (msg) {
        if (_failed) return;
        _failed = true;
        widget.onEngineFailed?.call();
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _pageReady = true;
          _push(fit: true);
        },
        onWebResourceError: (error) {
          if (_failed || !error.isForMainFrame!) return;
          _failed = true;
          widget.onEngineFailed?.call();
        },
      ))
      ..loadFlutterAsset('assets/tv/chart.html');
  }

  @override
  void didUpdateWidget(ChartWidget old) {
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
    if (!_pageReady || _failed || widget.candles.isEmpty) return;
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
