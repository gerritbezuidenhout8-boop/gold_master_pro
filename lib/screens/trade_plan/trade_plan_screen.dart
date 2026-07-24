import 'package:flutter/material.dart';

import '../../ai/gold_master_engine.dart';
import '../../ai/trade_plan_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../indicators/key_levels.dart';
import '../../services/market_data.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/score_gauge.dart';

/// Trade Plan / Signal (spec: mockup screen 8). Uses the Gold Master
/// Score to produce a concrete entry / stop / take-profit plan only on
/// high conviction — a long setup at score ≥ [bullishThreshold], a short
/// at ≤ [bearishThreshold]; otherwise it reports "no signal". Analysis
/// and education only — not financial advice.
class TradePlanScreen extends StatefulWidget {
  const TradePlanScreen({
    super.key,
    this.bullishThreshold = 80,
    this.bearishThreshold = 20,
  });

  final int bullishThreshold;
  final int bearishThreshold;

  @override
  State<TradePlanScreen> createState() => _TradePlanScreenState();
}

class _TradePlanScreenState extends State<TradePlanScreen> {
  GoldMasterAnalysis? _analysis;
  TradePlan? _plan;
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
      final h1 = await MarketData.instance.fetchCandles('H1');
      final d1 = await MarketData.instance.fetchCandles('D1');
      if (!mounted) return;
      final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: h1,
        levels: KeyLevels.compute(d1),
        bullishThreshold: widget.bullishThreshold,
        bearishThreshold: widget.bearishThreshold,
      );
      setState(() {
        _analysis = analysis;
        _plan = plan;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not build a trade plan: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trade Plan'),
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
    final a = _analysis;
    if (a == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final plan = _plan;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (plan == null) _noSignalCard(a) else ..._planCards(plan),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Always manage your risk. Past performance is not indicative of '
            'future results. Educational analysis only — not financial advice.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _noSignalCard(GoldMasterAnalysis a) {
    return GmpCard(
      child: Column(
        children: [
          const SectionLabel('No High-Conviction Signal'),
          const SizedBox(height: 14),
          ScoreGauge(score: a.score),
          const SizedBox(height: 14),
          Text(
            'A trade plan appears only when the Gold Master Score reaches '
            '≥ ${widget.bullishThreshold} (bullish) or '
            '≤ ${widget.bearishThreshold} (bearish). '
            'Current bias is ${a.bias.label.toLowerCase()} — waiting for a '
            'stronger, higher-probability setup.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  List<Widget> _planCards(TradePlan plan) {
    final long = plan.direction == TradeDirection.long;
    final color = long ? AppTheme.bull : AppTheme.bear;
    return [
      GmpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(long ? Icons.north_east : Icons.south_east,
                    color: color, size: 26),
                const SizedBox(width: 8),
                Text('${plan.action} SETUP',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const Spacer(),
                GmpPill(text: 'Score ${plan.score}', color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text('High-conviction ${plan.direction.label} setup',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ),
      GmpCard(
        child: Column(
          children: [
            _planRow('Entry Zone',
                '${formatPrice(plan.entryLow)} – ${formatPrice(plan.entryHigh)}',
                valueColor: AppTheme.textPrimary),
            const Divider(height: 16, color: AppTheme.hairline),
            _planRow('Stop Loss', formatPrice(plan.stop),
                sub: 'Risk ${plan.risk.toStringAsFixed(2)}',
                valueColor: AppTheme.bear),
            const Divider(height: 16, color: AppTheme.hairline),
            _planRow('Take Profit 1', formatPrice(plan.tp1),
                sub: 'RR ${plan.rr1.toStringAsFixed(1)}',
                valueColor: AppTheme.bull),
            const Divider(height: 16, color: AppTheme.hairline),
            _planRow('Take Profit 2', formatPrice(plan.tp2),
                sub: 'RR ${plan.rr2.toStringAsFixed(1)}',
                valueColor: AppTheme.bull),
          ],
        ),
      ),
      GmpCard(
        child: Row(
          children: [
            _metric('Risk / Reward', '1 : ${plan.rr2.toStringAsFixed(1)}'),
            _metric('Confidence', '${plan.confidence}%'),
            _metric('Valid Until', '${formatUtcStamp(plan.validUntil)} UTC'),
          ],
        ),
      ),
      if (plan.rationale.isNotEmpty)
        GmpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Why This Setup'),
              const SizedBox(height: 10),
              for (final r in plan.rationale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5, right: 8),
                        child:
                            Icon(Icons.circle, size: 5, color: AppTheme.gold),
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
        ),
    ];
  }

  Widget _planRow(String label, String value,
      {String? sub, required Color valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: valueColor)),
            if (sub != null)
              Text(sub,
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.6,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gold)),
        ],
      ),
    );
  }
}
