import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart' show KLineEntity;

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../indicators/rsi.dart';
import '../../models/candle.dart';
import '../../models/spot_quote.dart';
import '../../services/market_data.dart';
import '../../services/spot_gold_data.dart';
import '../../state/signal_controller.dart';
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
  StreamSubscription<SpotQuote>? _quoteSub;
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
    // The XAU spot ticker (Swissquote native / gold-api web) updates faster
    // than the candle feed and is the price the trader actually watches —
    // fold each tick into the forming candle so the chart moves with spot.
    _quoteSub = MarketData.instance.quoteStream().listen(_onSpot);
    // Owned by the screen, not by _load: when a load failed, the throttle
    // used to never start, so the chart stayed frozen even after a retry.
    _throttle = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_dirty) {
        _dirty = false;
        _rebuild();
      }
      // The bar countdown has to tick every second whether or not price
      // moved, so it is driven here rather than by the quote stream.
      final left = _barTimeLeft();
      if (left != _timeLeft) setState(() => _timeLeft = left);
    });
  }

  /// Time until the forming bar closes, e.g. 07:12 on M15.
  Duration _barTimeLeft() {
    final now = DateTime.now().toUtc();
    final bar = timeframeDuration(_timeframe);
    final opened = floorToTimeframe(now, _timeframe);
    return opened.add(bar).difference(now);
  }

  Duration _timeLeft = Duration.zero;

  static String _formatCountdown(Duration d) {
    if (d.isNegative) return '00:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    two(int v) => v.toString().padLeft(2, '0');
    // Hours only when there are any — D1/W1 would be unreadable otherwise.
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _quoteSub?.cancel();
    _throttle?.cancel();
    super.dispose();
  }

  /// Latest live spot. Spot is the single authority for the forming
  /// candle's close: the candle feed and the ticker are different vendors,
  /// and letting both write the close made the bar flip between two price
  /// levels and paint red candles on green moves.
  double? _spotPrice;

  /// Live spot → the last (forming) candle's close, extending its high/low.
  /// Coalesced into the throttled rebuild like the candle-stream updates.
  void _onSpot(SpotQuote q) {
    if (!mounted) return;
    _spotPrice = q.price;
    if (_applySpot()) _dirty = true;
  }

  /// Folds the latest spot into the forming candle. Returns whether anything
  /// changed. Re-applied after every candle-stream merge so the live close
  /// never regresses to the feed's own price between ticks.
  bool _applySpot() {
    final price = _spotPrice;
    if (price == null || _candles.isEmpty) return false;
    final last = _candles.last;
    if (price == last.close) return false;
    _candles = [
      ..._candles.sublist(0, _candles.length - 1),
      Candle(
        time: last.time,
        open: last.open,
        high: price > last.high ? price : last.high,
        low: price < last.low ? price : last.low,
        close: price,
        volume: last.volume,
      ),
    ];
    return true;
  }

  Future<void> _load(String tf) async {
    unawaited(_sub?.cancel());
    _sub = null;
    // Drop any pending update from the timeframe we're leaving, so the
    // throttle can't rebuild the outgoing series mid-load.
    _dirty = false;
    setState(() {
      _datas = null;
      _error = null;
    });
    try {
      final candles = await _loader(tf);
      if (!mounted || _timeframe != tf) return;
      // A fresh series carries its own alignment; drop the previous
      // timeframe's spot so it can't be folded into the wrong bar.
      _spotPrice = null;
      _candles = candles;
      _rebuild();
      // Forming-candle updates arrive several times a second; just mark
      // dirty and coalesce them into ~1 rebuild/sec (the recompute spans
      // the whole candle set, so running it per tick starves the UI).
      _sub = _streamer(tf).listen((update) {
        if (!mounted) return;
        _candles = mergeCandle(_candles, update);
        // Spot wins for the live close — see _applySpot.
        _applySpot();
        _dirty = true;
      });
    } catch (e) {
      if (!mounted || _timeframe != tf) return;
      setState(() => _error = 'Could not load candles: $e');
    }
  }

  /// Recompute chart entities, the StochRSI read-out and the recent-
  /// divergence pill from [_candles].
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
      appBar: AppBar(
        title: Text('${AppConstants.symbol} · $_timeframe'),
        actions: [
          // Time left on the forming bar. Without it there is no way to tell
          // a bar that is still filling out from one that has closed.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 13, color: AppTheme.gold),
                    const SizedBox(width: 5),
                    Text(
                      _formatCountdown(_timeLeft),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: AppTheme.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
      // Rebuild as the controller changes so a ratcheting stop moves its
      // line; the chart is only redrawn when the signal object itself
      // changes, so a quiet tick costs nothing.
      return AnimatedBuilder(
        animation: SignalController.instance,
        builder: (context, _) => ChartWidget(
          candles: _candles,
          timeframe: _timeframe,
          showStochRsi: _showStochRsi,
          showDivergence: _showDivergence,
          signal: SignalController.instance.active,
          onEngineFailed: _onTvEngineFailed,
        ),
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
