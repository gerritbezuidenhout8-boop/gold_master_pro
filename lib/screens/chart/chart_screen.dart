import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart' show KLineEntity;

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../indicators/rsi.dart';
import '../../models/candle.dart';
import '../../services/market_data.dart';
import '../../services/spot_gold_data.dart';
import '../../widgets/bottom_trade_panel.dart';
import '../../widgets/chart_widget.dart';
import '../../widgets/gmp_chart.dart';
import '../../widgets/indicator_bar.dart';
import '../../widgets/timeframe_selector.dart';

typedef CandleLoader = Future<List<Candle>> Function(String timeframe);
typedef CandleStreamer = Stream<Candle> Function(String timeframe);

/// Full-screen chart (spec: Chart Screen): live Binance PAXG candles with
/// SMMA 21/50/200, a Stochastic RSI sub-pane and RSI-divergence markers.
class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key, this.loadCandles, this.streamCandles});

  final CandleLoader? loadCandles;
  final CandleStreamer? streamCandles;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  static const _intradayTimeframes = {'M5', 'M15', 'M30', 'H1', 'H4'};

  String _timeframe = 'H1';
  List<Candle> _candles = const [];
  List<KLineEntity>? _datas;
  String? _error;
  StreamSubscription<Candle>? _sub;
  Timer? _throttle;
  bool _dirty = false;

  bool _showStochRsi = true;
  bool _showDivergence = true;
  double? _stochK, _stochD;
  DivergenceEvent? _recentDiv;

  late final CandleLoader _loader =
      widget.loadCandles ?? MarketData.instance.fetchCandles;
  late final CandleStreamer _streamer =
      widget.streamCandles ?? MarketData.instance.candleStream;

  /// TradingView Lightweight Charts renders on Android (WebView) and web
  /// (iframe); desktop — and any engine failure — falls back to the
  /// native k_chart renderer.
  bool _tvFailed = false;
  bool get _useTv => !_tvFailed && (kIsWeb || Platform.isAndroid);

  void _onTvEngineFailed() {
    if (_tvFailed || !mounted) return;
    _tvFailed = true;
    _rebuild(); // recompute k_chart entities and swap renderers
  }

  @override
  void initState() {
    super.initState();
    _load(_timeframe);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _throttle?.cancel();
    super.dispose();
  }

  Future<void> _load(String tf) async {
    unawaited(_sub?.cancel());
    _sub = null;
    _throttle?.cancel();
    setState(() {
      _datas = null;
      _error = null;
    });
    try {
      final candles = await _loader(tf);
      if (!mounted || _timeframe != tf) return;
      _candles = candles;
      _rebuild();
      // Forming-candle updates arrive several times a second; just mark
      // dirty and coalesce them into ~1 rebuild/sec (the recompute spans
      // the whole candle set, so running it per tick starves the UI).
      _sub = _streamer(tf).listen((update) {
        if (!mounted) return;
        _candles = mergeCandle(_candles, update);
        _dirty = true;
      });
      _throttle = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_dirty && mounted) {
          _dirty = false;
          _rebuild();
        }
      });
    } catch (e) {
      if (!mounted || _timeframe != tf) return;
      setState(() => _error = 'Could not load candles: $e');
    }
  }

  /// Recompute chart entities and the momentum read-out from [_candles].
  void _rebuild() {
    final closes = [for (final c in _candles) c.close];
    final sr = StochRsi.compute(closes);
    _stochK = _lastNonNull(sr.k);
    _stochD = _lastNonNull(sr.d);
    final divs = RsiDivergence.detect(_candles);
    _recentDiv = divs.isNotEmpty && divs.last.index >= _candles.length - 8
        ? divs.last
        : null;
    setState(() => _datas = _useTv
        ? const <KLineEntity>[] // TvChart reads _candles directly
        : GmpChart.prepare(_candles,
            stochRsi: _showStochRsi, divergence: _showDivergence));
  }

  double? _lastNonNull(List<double?> xs) {
    for (var i = xs.length - 1; i >= 0; i--) {
      if (xs[i] != null) return xs[i];
    }
    return null;
  }

  void _selectTimeframe(String tf) {
    if (tf == _timeframe) return;
    setState(() => _timeframe = tf);
    _load(tf);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${AppConstants.symbol} · $_timeframe')),
      body: Column(
        children: [
          TimeframeSelector(
            selected: _timeframe,
            onSelected: _selectTimeframe,
          ),
          IndicatorBar(
            stochK: _stochK,
            stochD: _stochD,
            recentDivergence: _recentDiv,
            showStochRsi: _showStochRsi,
            showDivergence: _showDivergence,
            onStochRsiChanged: (v) => setState(() {
              _showStochRsi = v;
              _rebuild();
            }),
            onDivergenceChanged: (v) => setState(() {
              _showDivergence = v;
              _rebuild();
            }),
          ),
          Expanded(child: _buildChartArea()),
          const BottomTradePanel(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: ValueListenableBuilder<String>(
              valueListenable: SpotGoldMarketData.candleSource,
              builder: (context, source, _) => Text(
                'Candles: $source · live',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartArea() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error, style: const TextStyle(color: AppTheme.textSecondary)),
          TextButton(
              onPressed: () => _load(_timeframe), child: const Text('Retry')),
        ]),
      );
    }
    final datas = _datas;
    if (datas == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_useTv) {
      return ChartWidget(
        candles: _candles,
        timeframe: _timeframe,
        showStochRsi: _showStochRsi,
        showDivergence: _showDivergence,
        onEngineFailed: _onTvEngineFailed,
      );
    }
    return GmpChart(
      datas: datas,
      intraday: _intradayTimeframes.contains(_timeframe),
      showStochRsi: _showStochRsi,
      showDivergence: _showDivergence,
    );
  }
}
