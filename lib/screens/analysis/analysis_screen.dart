import 'package:flutter/material.dart';

import '../../ai/gold_master_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../indicators/candlestick_ai.dart';
import '../../indicators/fibonacci.dart';
import '../../indicators/key_levels.dart';
import '../../indicators/rsi.dart';
import '../../indicators/smma.dart';
import '../../models/candle.dart';
import '../../services/market_data.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/section_card.dart' show KvRow;

/// Deep-dive analysis (spec: Analysis Screen). Runs the full engine on
/// each intraday timeframe from 5m to 1h — a tappable multi-timeframe
/// consensus strip up top, with the detail cards driven by the selected
/// timeframe. Key levels stay daily (they are timeframe-independent).
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  /// The 5m → 1h analysis range.
  static const List<String> _tfs = ['M5', 'M15', 'M30', 'H1'];

  List<Candle> _daily = const [];
  final Map<String, List<Candle>> _intraday = {};
  final Map<String, GoldMasterAnalysis> _analyses = {};
  String _selectedTf = 'H1';

  // Derived values for the currently selected timeframe.
  GoldMasterAnalysis? _analysis;
  KeyLevelsResult? _levels;
  AutoFibResult? _fib;
  List<(DateTime, CandlePattern)> _patterns = const [];
  double? _lastClose;
  double? _smma21, _smma50, _smma200;
  double? _rsi, _stochK, _stochD;
  DivergenceEvent? _recentDiv;
  DateTime? _computedAt;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        MarketData.instance.fetchCandles('D1'),
        for (final tf in _tfs) MarketData.instance.fetchCandles(tf),
      ]);
      if (!mounted) return;

      _daily = results[0];
      _intraday.clear();
      _analyses.clear();
      for (var i = 0; i < _tfs.length; i++) {
        final tf = _tfs[i];
        final candles = results[i + 1];
        _intraday[tf] = candles;
        if (candles.isNotEmpty && _daily.isNotEmpty) {
          _analyses[tf] = GoldMasterEngine.analyze(
            h1: candles,
            d1: _daily,
            intradayName: '$tf trend',
            intradayWord: tf,
          );
        }
      }
      _levels = KeyLevels.compute(_daily);
      _computedAt = DateTime.now().toUtc();
      _applyTf(_selectedTf);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not compute analysis: $e';
        _loading = false;
      });
    }
  }

  /// Recomputes the detail-card values for [tf] from already-fetched
  /// candles (no network) and selects it.
  void _applyTf(String tf) {
    final candles = _intraday[tf] ?? const [];
    final closes = [for (final c in candles) c.close];
    final found = <(DateTime, CandlePattern)>[];
    final start = candles.length > 20 ? candles.length - 20 : 1;
    for (var i = start; i < candles.length; i++) {
      for (final p in CandlestickDetector.detect(candles.sublist(0, i + 1))) {
        found.add((candles[i].time, p));
      }
    }
    final sr = StochRsi.compute(closes);
    final divs = RsiDivergence.detect(candles);
    setState(() {
      _selectedTf = tf;
      _analysis = _analyses[tf];
      _fib = candles.isEmpty ? null : Fibonacci.auto(candles);
      _patterns = found.reversed.take(6).toList();
      _lastClose = closes.isEmpty ? null : closes.last;
      _smma21 = closes.length >= 21 ? Smma.compute(closes, 21).last : null;
      _smma50 = closes.length >= 50 ? Smma.compute(closes, 50).last : null;
      _smma200 = closes.length >= 200 ? Smma.compute(closes, 200).last : null;
      _rsi = _lastNonNull(Rsi.compute(closes));
      _stochK = _lastNonNull(sr.k);
      _stochD = _lastNonNull(sr.d);
      _recentDiv = divs.isNotEmpty && divs.last.index >= candles.length - 10
          ? divs.last
          : null;
      _loading = false;
    });
  }

  Color _biasColor(MarketBias b) => switch (b) {
        MarketBias.bullish => AppTheme.bull,
        MarketBias.bearish => AppTheme.bear,
        MarketBias.neutral => AppTheme.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.gold),
            tooltip: 'Recompute',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error, style: const TextStyle(color: AppTheme.textSecondary)),
          TextButton(onPressed: _refresh, child: const Text('Retry')),
        ]),
      );
    }
    final levels = _levels;
    final a = _analysis;
    if (levels == null || a == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final fib = _fib;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (_computedAt != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Text(
              'Computed ${formatUtcStamp(_computedAt!)} UTC · '
              'D1 + $_selectedTf',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        _multiTimeframeCard(),
        _trendCard(a),
        _keyLevelsCard(levels),
        _indicatorSummaryCard(a),
        _momentumCard(),
        if (fib != null) _fibCard(fib),
        _smmaCard(),
        _patternsCard(),
      ],
    );
  }

  Widget _multiTimeframeCard() {
    final analyses = _analyses.values;
    final bull =
        analyses.where((a) => a.bias == MarketBias.bullish).length;
    final bear =
        analyses.where((a) => a.bias == MarketBias.bearish).length;
    final neutral = analyses.length - bull - bear;
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Multi-Timeframe (5m → 1h)'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final tf in _tfs)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _mtfTile(tf),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Consensus: $bull bullish · $neutral neutral · $bear bearish · '
            'tap a timeframe to drill in',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _mtfTile(String tf) {
    final a = _analyses[tf];
    final selected = tf == _selectedTf;
    final color = a == null ? AppTheme.textSecondary : _biasColor(a.bias);
    return GestureDetector(
      onTap: () => _applyTf(tf),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.gold : AppTheme.hairline,
            width: selected ? 1.4 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Text(tf,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 3),
            Text(
              a?.bias.label.toUpperCase() ?? '—',
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: color),
            ),
            Text(
              a == null ? '—' : '${a.score}',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendCard(GoldMasterAnalysis a) {
    final color = _biasColor(a.bias);
    final strength =
        a.clarity >= 50 ? 'Strong' : a.clarity >= 25 ? 'Moderate' : 'Weak';
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Trend Analysis · $_selectedTf'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Primary trend',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(height: 2),
                    Text(a.bias.label,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Strength',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 2),
                  Text('$strength · ${a.clarity}%',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyLevelsCard(KeyLevelsResult l) {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Key Levels (UTC days)'),
          const SizedBox(height: 10),
          KvRow(label: 'Daily Open', value: formatPrice(l.dailyOpen)),
          KvRow(label: 'Daily High', value: formatPrice(l.dailyHigh)),
          KvRow(label: 'Daily Low', value: formatPrice(l.dailyLow)),
          KvRow(label: 'Prev Day High', value: _opt(l.prevDayHigh)),
          KvRow(label: 'Prev Day Low', value: _opt(l.prevDayLow)),
          KvRow(label: 'Week High', value: formatPrice(l.weekHigh)),
          KvRow(label: 'Week Low', value: formatPrice(l.weekLow)),
          KvRow(label: 'Prev Week High', value: _opt(l.prevWeekHigh)),
          KvRow(label: 'Prev Week Low', value: _opt(l.prevWeekLow)),
          KvRow(label: 'All-Time High*', value: formatPrice(l.allTimeHigh)),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('*highest within the loaded 500-day history',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _indicatorSummaryCard(GoldMasterAnalysis a) {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Indicator Summary · $_selectedTf'),
          const SizedBox(height: 10),
          for (final c in a.components)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(c.name,
                        style: const TextStyle(color: AppTheme.textPrimary)),
                  ),
                  _signalPill(c.signal),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _signalPill(double signal) {
    final (text, color) = signal > 0.15
        ? ('Bullish', AppTheme.bull)
        : signal < -0.15
            ? ('Bearish', AppTheme.bear)
            : ('Neutral', AppTheme.gold);
    return GmpPill(text: text, color: color);
  }

  Widget _momentumCard() {
    final rsi = _rsi;
    final k = _stochK;
    final d = _stochD;
    (String, Color) rsiTag = rsi == null
        ? ('—', AppTheme.textSecondary)
        : rsi >= 70
            ? ('Overbought', AppTheme.bear)
            : rsi <= 30
                ? ('Oversold', AppTheme.bull)
                : rsi >= 50
                    ? ('Bullish', AppTheme.bull)
                    : ('Bearish', AppTheme.bear);
    final stochBull = (k != null && d != null) ? k >= d : null;
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Momentum · $_selectedTf'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RSI (14)  ${rsi?.toStringAsFixed(1) ?? '—'}',
                  style: const TextStyle(color: AppTheme.textPrimary)),
              GmpPill(text: rsiTag.$1, color: rsiTag.$2),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stoch RSI  %K ${k?.toStringAsFixed(1) ?? '—'} · '
                '%D ${d?.toStringAsFixed(1) ?? '—'}',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              if (stochBull != null)
                GmpPill(
                    text: stochBull ? 'Bullish' : 'Bearish',
                    color: stochBull ? AppTheme.bull : AppTheme.bear),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('RSI Divergence',
                  style: TextStyle(color: AppTheme.textPrimary)),
              _recentDiv == null
                  ? const Text('none',
                      style: TextStyle(color: AppTheme.textSecondary))
                  : GmpPill(
                      text: _recentDiv!.type == DivergenceType.bullish
                          ? 'Bullish'
                          : 'Bearish',
                      color: _recentDiv!.type == DivergenceType.bullish
                          ? AppTheme.bull
                          : AppTheme.bear),
            ],
          ),
        ],
      ),
    );
  }

  double? _lastNonNull(List<double?> xs) {
    for (var i = xs.length - 1; i >= 0; i--) {
      if (xs[i] != null) return xs[i];
    }
    return null;
  }

  Widget _fibCard(AutoFibResult fib) {
    final nearest = _nearestRatio(fib);
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Auto Fibonacci · $_selectedTf'),
          const SizedBox(height: 8),
          Text(
            '${fib.isUpLeg ? 'Up' : 'Down'} leg · '
            '${formatPrice(fib.swingLow)} → ${formatPrice(fib.swingHigh)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          for (final r in Fibonacci.ratios)
            KvRow(
              label: _ratioLabel(r),
              value: formatPrice(fib.levels[r]!),
              highlight: r == nearest,
            ),
          if (nearest != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Price is nearest the ${_ratioLabel(nearest)} level',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _smmaCard() {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Moving Averages · $_selectedTf'),
          const SizedBox(height: 8),
          KvRow(label: 'SMMA 21', value: _smmaText(_smma21)),
          KvRow(label: 'SMMA 50', value: _smmaText(_smma50)),
          KvRow(label: 'SMMA 200', value: _smmaText(_smma200)),
        ],
      ),
    );
  }

  Widget _patternsCard() {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Candlestick Detection · $_selectedTf'),
          const SizedBox(height: 8),
          if (_patterns.isEmpty)
            const Text('No patterns detected',
                style: TextStyle(color: AppTheme.textSecondary))
          else
            for (final (t, p) in _patterns) _patternRow(t, p),
        ],
      ),
    );
  }

  String _opt(double? v) => v == null ? '—' : formatPrice(v);

  String _smmaText(double? v) {
    if (v == null) return '—';
    final close = _lastClose;
    final rel =
        close == null ? '' : (close > v ? ' · price above' : ' · price below');
    return '${formatPrice(v)}$rel';
  }

  String _ratioLabel(double r) =>
      r == 0 ? '0%' : r == 1 ? '100%' : '${(r * 100).toStringAsFixed(1)}%';

  double? _nearestRatio(AutoFibResult fib) {
    final close = _lastClose;
    if (close == null) return null;
    double? best;
    var bestDist = double.infinity;
    for (final e in fib.levels.entries) {
      final d = (e.value - close).abs();
      if (d < bestDist) {
        bestDist = d;
        best = e.key;
      }
    }
    return best;
  }

  Widget _patternRow(DateTime t, CandlePattern p) {
    final color = p.isBullishSignal
        ? AppTheme.bull
        : p.isBearishSignal
            ? AppTheme.bear
            : AppTheme.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${formatUtcStamp(t)} UTC',
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(p.label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
