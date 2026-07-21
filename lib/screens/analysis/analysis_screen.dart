import 'package:flutter/material.dart';

import '../../ai/gold_master_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../indicators/candlestick_ai.dart';
import '../../indicators/fibonacci.dart';
import '../../indicators/key_levels.dart';
import '../../indicators/rsi.dart';
import '../../indicators/smma.dart';
import '../../services/market_data.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/section_card.dart' show KvRow;

/// Deep-dive analysis view (spec: Analysis Screen): trend, key levels,
/// an indicator summary from the engine's real signals, auto-Fibonacci,
/// SMMA read-out and candlestick detections — all from live candles.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
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
      final daily = await MarketData.instance.fetchCandles('D1');
      final h1 = await MarketData.instance.fetchCandles('H1');
      if (!mounted) return;

      final closes = [for (final c in h1) c.close];
      final found = <(DateTime, CandlePattern)>[];
      final start = h1.length > 20 ? h1.length - 20 : 1;
      for (var i = start; i < h1.length; i++) {
        for (final p in CandlestickDetector.detect(h1.sublist(0, i + 1))) {
          found.add((h1[i].time, p));
        }
      }

      setState(() {
        _analysis = GoldMasterEngine.analyze(h1: h1, d1: daily);
        _levels = KeyLevels.compute(daily);
        _fib = h1.isEmpty ? null : Fibonacci.auto(h1);
        _patterns = found.reversed.take(6).toList();
        _lastClose = closes.isEmpty ? null : closes.last;
        _smma21 = closes.length >= 21 ? Smma.compute(closes, 21).last : null;
        _smma50 = closes.length >= 50 ? Smma.compute(closes, 50).last : null;
        _smma200 =
            closes.length >= 200 ? Smma.compute(closes, 200).last : null;
        _rsi = _lastNonNull(Rsi.compute(closes));
        final sr = StochRsi.compute(closes);
        _stochK = _lastNonNull(sr.k);
        _stochD = _lastNonNull(sr.d);
        final divs = RsiDivergence.detect(h1);
        _recentDiv = divs.isNotEmpty && divs.last.index >= h1.length - 10
            ? divs.last
            : null;
        _computedAt = DateTime.now().toUtc();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not compute analysis: $e';
        _loading = false;
      });
    }
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
              'Computed ${formatUtcStamp(_computedAt!)} UTC · D1 + H1 · PAXG',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
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

  Widget _trendCard(GoldMasterAnalysis a) {
    final color = _biasColor(a.bias);
    final strength =
        a.clarity >= 50 ? 'Strong' : a.clarity >= 25 ? 'Moderate' : 'Weak';
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Trend Analysis'),
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
          const SectionLabel('Indicator Summary'),
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
          const SectionLabel('Momentum · H1'),
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
          const SectionLabel('Auto Fibonacci · H1'),
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
          const SectionLabel('Moving Averages · H1'),
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
          const SectionLabel('Candlestick Detection · H1'),
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
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(p.label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
