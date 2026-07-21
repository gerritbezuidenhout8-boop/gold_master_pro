import 'dart:async';

import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart' show KLineEntity;

import '../../core/constants/app_constants.dart';
import '../../models/candle.dart';
import '../../services/market_data.dart';
import '../../widgets/gmp_chart.dart';

typedef CandleLoader = Future<List<Candle>> Function(String timeframe);
typedef CandleStreamer = Stream<Candle> Function(String timeframe);

/// Full-screen chart (spec: Chart Screen), running on the zero-cost
/// stack: k_chart_plus rendering + live Binance PAXG candles (REST
/// backfill + WebSocket updates) with GMP's own SMMA 21/50/200 overlay.
///
/// [loadCandles]/[streamCandles] are injection seams for tests; they
/// default to [BinanceMarketData], which falls back to the bundled
/// snapshots when offline.
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

  late final CandleLoader _loader =
      widget.loadCandles ?? MarketData.instance.fetchCandles;
  late final CandleStreamer _streamer =
      widget.streamCandles ?? MarketData.instance.candleStream;

  @override
  void initState() {
    super.initState();
    _load(_timeframe);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load(String tf) async {
    unawaited(_sub?.cancel());
    _sub = null;
    setState(() {
      _datas = null;
      _error = null;
    });
    try {
      final candles = await _loader(tf);
      if (!mounted || _timeframe != tf) return;
      _candles = candles;
      setState(() => _datas = GmpChart.prepare(candles));
      _sub = _streamer(tf).listen((update) {
        if (!mounted) return;
        _candles = mergeCandle(_candles, update);
        setState(() => _datas = GmpChart.prepare(_candles));
      });
    } catch (e) {
      if (!mounted || _timeframe != tf) return;
      setState(() => _error = 'Could not load candles: $e');
    }
  }

  void _selectTimeframe(String tf) {
    if (tf == _timeframe) return;
    setState(() => _timeframe = tf);
    _load(tf);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${AppConstants.symbol} · $_timeframe')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final tf in AppConstants.timeframes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tf),
                      selected: _timeframe == tf,
                      onSelected: (_) => _selectTimeframe(tf),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildChartArea(theme)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              'Candles: PAXG/USD (tracks gold) · Binance public data · live',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartArea(ThemeData theme) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, style: theme.textTheme.bodySmall),
            TextButton(
              onPressed: () => _load(_timeframe),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final datas = _datas;
    if (datas == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GmpChart(
      datas: datas,
      intraday: _intradayTimeframes.contains(_timeframe),
    );
  }
}
