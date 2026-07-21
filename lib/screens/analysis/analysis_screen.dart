import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../indicators/candlestick_ai.dart';
import '../../indicators/fibonacci.dart';
import '../../indicators/key_levels.dart';
import '../../indicators/smma.dart';
import '../../services/market_data.dart';
import '../../widgets/section_card.dart';
import '../../widgets/section_placeholder.dart';

/// Deep-dive analysis view (spec: Analysis Screen): real key levels,
/// auto-Fibonacci, SMMA read-out and candlestick detections computed
/// from live candles (D1 for levels, H1 for everything else).
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  KeyLevelsResult? _levels;
  AutoFibResult? _fib;
  List<(DateTime, CandlePattern)> _patterns = const [];
  double? _lastClose;
  double? _smma21, _smma50, _smma200;
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
        _levels = KeyLevels.compute(daily);
        _fib = h1.isEmpty ? null : Fibonacci.auto(h1);
        _patterns = found.reversed.take(6).toList();
        _lastClose = closes.isEmpty ? null : closes.last;
        _smma21 = closes.length >= 21 ? Smma.compute(closes, 21).last : null;
        _smma50 = closes.length >= 50 ? Smma.compute(closes, 50).last : null;
        _smma200 =
            closes.length >= 200 ? Smma.compute(closes, 200).last : null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recompute',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, style: theme.textTheme.bodySmall),
            TextButton(onPressed: _refresh, child: const Text('Retry')),
          ],
        ),
      );
    }
    final levels = _levels;
    if (levels == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final fib = _fib;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_computedAt != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Computed ${formatUtcStamp(_computedAt!)} UTC · D1 + H1 · PAXG data',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        SectionCard(
          title: 'Key Levels (UTC days)',
          children: [
            KvRow(label: 'Daily Open', value: formatPrice(levels.dailyOpen)),
            KvRow(label: 'Daily High', value: formatPrice(levels.dailyHigh)),
            KvRow(label: 'Daily Low', value: formatPrice(levels.dailyLow)),
            KvRow(label: 'Prev Day High', value: _fmtOpt(levels.prevDayHigh)),
            KvRow(label: 'Prev Day Low', value: _fmtOpt(levels.prevDayLow)),
            KvRow(label: 'Week High', value: formatPrice(levels.weekHigh)),
            KvRow(label: 'Week Low', value: formatPrice(levels.weekLow)),
            KvRow(
                label: 'Prev Week High',
                value: _fmtOpt(levels.prevWeekHigh)),
            KvRow(label: 'Prev Week Low', value: _fmtOpt(levels.prevWeekLow)),
            KvRow(
                label: 'All-Time High*',
                value: formatPrice(levels.allTimeHigh)),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '*highest within the loaded 500-day history',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (fib != null)
          SectionCard(
            title: 'Auto Fibonacci · H1',
            children: [
              Text(
                '${fib.isUpLeg ? 'Up' : 'Down'} leg · '
                '${formatPrice(fib.swingLow)} → ${formatPrice(fib.swingHigh)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              for (final r in Fibonacci.ratios)
                KvRow(
                  label: _ratioLabel(r),
                  value: formatPrice(fib.levels[r]!),
                  highlight: r == _nearestRatio(fib),
                ),
              if (_nearestRatio(fib) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Price is nearest the ${_ratioLabel(_nearestRatio(fib)!)} level',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        SectionCard(
          title: 'Moving Averages · H1',
          children: [
            KvRow(label: 'SMMA 21', value: _smmaText(_smma21)),
            KvRow(label: 'SMMA 50', value: _smmaText(_smma50)),
            KvRow(label: 'SMMA 200', value: _smmaText(_smma200)),
          ],
        ),
        SectionCard(
          title: 'Candlestick Detection · H1 · last 20 candles',
          children: [
            if (_patterns.isEmpty)
              Text('No patterns detected', style: theme.textTheme.bodySmall)
            else
              for (final (t, p) in _patterns) _patternRow(theme, t, p),
          ],
        ),
        const SectionPlaceholder(
          title: 'Indicator summary & risk analysis',
          subtitle: 'Gold Master Score rubric — see Home',
          icon: Icons.summarize,
        ),
        const SectionPlaceholder(
          title: 'Best / worst scenario',
          subtitle: 'Narrative engine — Phase 4+',
          icon: Icons.alt_route,
        ),
      ],
    );
  }

  String _fmtOpt(double? v) => v == null ? '—' : formatPrice(v);

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

  Widget _patternRow(ThemeData theme, DateTime t, CandlePattern p) {
    final color = p.isBullishSignal
        ? const Color(0xFF14AD8F)
        : p.isBearishSignal
            ? const Color(0xFFD5405D)
            : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${formatUtcStamp(t)} UTC', style: theme.textTheme.bodySmall),
          Text(p.label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}
