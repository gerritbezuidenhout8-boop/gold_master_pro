import 'package:flutter/material.dart';

import '../../ai/gold_master_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../services/market_data.dart';
import '../../widgets/brand.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/gold_button.dart';
import '../../widgets/live_price_card.dart';
import '../../widgets/score_gauge.dart';
import '../../widgets/stat_tile.dart';
import '../settings/settings_screen.dart';
import '../trade_plan/trade_plan_screen.dart';

/// Home dashboard (spec: Home Screen) — live price header, the Gold
/// Master Score gauge, evidence stat tiles, an AI recommendation and the
/// narrative, all driven by the deterministic engine.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoldMasterAnalysis? _analysis;
  List<double> _spark = const [];
  double? _dayOpen;
  int _candleCount = 0;
  bool _fresh = false;
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
      setState(() {
        _analysis = analysis;
        _spark = [
          for (final c in h1.sublist(h1.length > 30 ? h1.length - 30 : 0))
            c.close
        ];
        _dayOpen = d1.last.open;
        _candleCount = h1.length + d1.length;
        _fresh = age <= const Duration(hours: 2);
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

  Color _biasColor(MarketBias b) => switch (b) {
        MarketBias.bullish => AppTheme.bull,
        MarketBias.bearish => AppTheme.bear,
        MarketBias.neutral => AppTheme.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    return Scaffold(
      drawer: const _HomeDrawer(),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            GmpEmblem(size: 30),
            SizedBox(width: 8),
            Text(
              'GOLD MASTER PRO',
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppTheme.gold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            color: AppTheme.gold,
            tooltip: 'Notifications',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No new notifications')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          LivePriceCard(referenceOpen: _dayOpen, spark: _spark),
          if (_error != null)
            GmpCard(child: Column(children: [
              Text(_error!,
                  style: const TextStyle(color: AppTheme.textSecondary)),
              TextButton(onPressed: _analyze, child: const Text('Retry')),
            ]))
          else if (a == null)
            const GmpCard(
              child: SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            _scoreCard(a),
            _statTiles(a),
            _recommendationCard(a),
            _storyCard(a),
            _dataHealthCard(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: GoldButton(
              label: _analyzing ? 'Analyzing…' : 'Analyze Gold',
              icon: Icons.bolt,
              onPressed: _analyzing ? null : _analyze,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Analysis is for education only and is not financial advice.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard(GoldMasterAnalysis a) {
    final color = _biasColor(a.bias);
    final blurb = switch (a.bias) {
      MarketBias.bullish => 'Evidence supports a bullish setup',
      MarketBias.bearish => 'Evidence points to downside risk',
      MarketBias.neutral => 'Signals are mixed — no clear edge',
    };
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Gold Master Score'),
          const SizedBox(height: 12),
          Row(
            children: [
              ScoreGauge(score: a.score),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.bias.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(blurb,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    Text('Computed ${formatUtcStamp(a.computedAt)} UTC',
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTiles(GoldMasterAnalysis a) {
    ({String note, Color color}) band(int v) => v >= 70
        ? (note: 'Strong', color: AppTheme.bull)
        : v >= 45
            ? (note: 'Moderate', color: AppTheme.gold)
            : (note: 'Weak', color: AppTheme.bear);
    final match = band(a.confidence);
    final clarity = a.clarity >= 60
        ? (note: 'Clear', color: AppTheme.bull)
        : a.clarity >= 30
            ? (note: 'Mixed', color: AppTheme.gold)
            : (note: 'Choppy', color: AppTheme.bear);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              label: 'Strategy Match',
              value: '${a.confidence}%',
              note: '${match.note} Match',
              noteColor: match.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              label: 'Market Clarity',
              value: '${a.clarity}%',
              note: clarity.note,
              noteColor: clarity.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              label: 'Data Confidence',
              value: _fresh ? 'High' : 'Fair',
              note: _fresh ? 'Live feed' : 'Delayed',
              noteColor: _fresh ? AppTheme.bull : AppTheme.gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationCard(GoldMasterAnalysis a) {
    final (action, icon, color, text) = switch (a.bias) {
      MarketBias.bullish => (
          'BUY',
          Icons.north_east,
          AppTheme.bull,
          'Evidence supports potential upside based on current market conditions.'
        ),
      MarketBias.bearish => (
          'SELL',
          Icons.south_east,
          AppTheme.bear,
          'Evidence points to downside risk based on current market conditions.'
        ),
      MarketBias.neutral => (
          'HOLD',
          Icons.swap_horiz,
          AppTheme.textSecondary,
          'Signals are mixed — there is no clear directional edge right now.'
        ),
    };
    return GmpCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TradePlanScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('AI Recommendation'),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 8),
              Text(action,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: const [
              Text('View trade plan',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.gold)),
              Icon(Icons.chevron_right, size: 18, color: AppTheme.gold),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storyCard(GoldMasterAnalysis a) {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Market Story & Top Reasons'),
          const SizedBox(height: 12),
          Text(a.story,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary, height: 1.45)),
          const SizedBox(height: 10),
          for (final r in a.topReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5, right: 8),
                    child: Icon(Icons.circle, size: 5, color: AppTheme.gold),
                  ),
                  Expanded(
                    child: Text(r,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataHealthCard() {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Data Health'),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.circle,
                  size: 8, color: _fresh ? AppTheme.bull : AppTheme.gold),
              const SizedBox(width: 8),
              Text('$_candleCount candles · ${_fresh ? 'fresh' : 'delayed'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Source: Binance PAXG/USD public feed (tracks gold)',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  GmpEmblem(size: 44),
                  SizedBox(width: 12),
                  GmpWordmark(),
                ],
              ),
            ),
            const Divider(color: AppTheme.hairline),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: AppTheme.gold),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen()));
              },
            ),
            const ListTile(
              leading: Icon(Icons.info_outline, color: AppTheme.gold),
              title: Text('About Gold Master Pro'),
              subtitle: Text('Evidence-based gold analysis',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Educational analysis only — not financial advice.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
