import 'package:flutter/material.dart';

import '../../ai/gold_master_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format.dart';
import '../../services/market_data.dart';
import '../../widgets/live_price_card.dart';
import '../../widgets/section_card.dart';

/// Home dashboard (spec: Home Screen) — live price plus the
/// deterministic Gold Master Score and its narrative.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoldMasterAnalysis? _analysis;
  String? _health;
  String? _error;
  bool _analyzing = true;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      final h1 = await MarketData.instance.fetchCandles('H1');
      final d1 = await MarketData.instance.fetchCandles('D1');
      if (!mounted) return;
      final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
      final age = DateTime.now().toUtc().difference(h1.last.time);
      final fresh = age <= const Duration(hours: 2);
      setState(() {
        _analysis = analysis;
        _health = '${h1.length} H1 + ${d1.length} D1 candles · '
            'last candle ${formatUtcStamp(h1.last.time)} UTC · '
            '${fresh ? 'fresh' : 'stale'}';
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Analysis failed: $e';
        _analyzing = false;
      });
    }
  }

  Color _biasColor(MarketBias b, ThemeData theme) => switch (b) {
        MarketBias.bullish => const Color(0xFF14AD8F),
        MarketBias.bearish => const Color(0xFFD5405D),
        MarketBias.neutral => theme.colorScheme.outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = _analysis;
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const LivePriceCard(),
          if (_error != null)
            SectionCard(title: 'Analysis', children: [
              Text(_error!, style: theme.textTheme.bodySmall),
              TextButton(onPressed: _analyze, child: const Text('Retry')),
            ])
          else if (a == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            _scoreCard(theme, a),
            SectionCard(title: 'Strategy Match & Market Clarity', children: [
              KvRow(label: 'Strategy match', value: a.strategyMatch),
              KvRow(label: 'Market clarity', value: '${a.clarity}%'),
              KvRow(label: 'Signal confidence', value: '${a.confidence}%'),
            ]),
            SectionCard(title: 'Market Story & Top Reasons', children: [
              Text(a.story, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final r in a.topReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('•  $r', style: theme.textTheme.bodySmall),
                ),
            ]),
            SectionCard(title: 'Data Health', children: [
              Text(_health ?? '', style: theme.textTheme.bodySmall),
              Text(
                'Source: Binance PAXG/USD public feed (tracks gold)',
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _analyzing ? null : _analyze,
              icon: const Icon(Icons.bolt),
              label: Text(_analyzing ? 'Analyzing…' : 'Analyze Gold'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Analysis is for education only and is not financial advice.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _scoreCard(ThemeData theme, GoldMasterAnalysis a) {
    final color = _biasColor(a.bias, theme);
    return SectionCard(
      title: 'Gold Master Score',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          a.bias.label.toUpperCase(),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${a.score}',
              style: theme.textTheme.displayMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            Text(' / 100', style: theme.textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: a.score / 100,
            minHeight: 6,
            color: color,
            backgroundColor:
                theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Market bias: ${a.bias.label} · '
          'computed ${formatUtcStamp(a.computedAt)} UTC',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
