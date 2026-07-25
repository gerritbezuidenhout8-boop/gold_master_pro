import 'dart:async';

import 'package:flutter/material.dart';

import '../../ai/gold_master_engine.dart';
import '../../ai/trade_plan_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../indicators/key_levels.dart';
import '../../models/spot_quote.dart';
import '../../models/trade_signal.dart';
import '../../services/market_data.dart';
import '../../state/signal_controller.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/score_gauge.dart';

/// Trade Plan / Signal (spec: mockup screen 8).
///
/// Runs **one signal at a time**, and only on high conviction: a long at
/// score ≥ [bullishThreshold], a short at ≤ [bearishThreshold], nothing in
/// between — flat is a valid state. Once issued, the trade is tracked
/// against live price until it reaches its take-profit or its stop; only
/// after it closes does the score analyse the market for the next one.
/// Analysis and education only — not financial advice.
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
  double? _price;
  String? _error;
  bool _loading = true;
  StreamSubscription<SpotQuote>? _quoteSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _quoteSub = MarketData.instance.quoteStream().listen((q) {
      if (mounted) setState(() => _price = q.price);
    });
  }

  @override
  void dispose() {
    _quoteSub?.cancel();
    super.dispose();
  }

  /// Re-analyses the market, settles a trade that finished while the app was
  /// away, and issues the next signal only when nothing is running.
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
      final levels = KeyLevels.compute(d1);

      final signals = SignalController.instance;
      if (!signals.loaded) await signals.load();
      // Settle first: a trade may have hit its level while the app was shut.
      signals.reconcile(h1);
      if (signals.canIssue) {
        // Only a high-conviction read opens a trade; otherwise stay flat.
        final plan = TradePlanEngine.generate(
          analysis: analysis,
          candles: h1,
          levels: levels,
          bullishThreshold: widget.bullishThreshold,
          bearishThreshold: widget.bearishThreshold,
        );
        if (plan != null) await signals.issue(plan);
      }
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _price ??= h1.isEmpty ? null : h1.last.close;
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
            tooltip: 'Re-analyse',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: SignalController.instance,
        builder: (context, _) => _buildBody(),
      ),
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
    if (_loading && _analysis == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final signals = SignalController.instance;
    final active = signals.active;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (active != null)
          ..._activeCards(active)
        else
          _flatCard(_analysis),
        if (signals.history.isNotEmpty) _historyCard(signals),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'One signal runs at a time and closes only at its take-profit or '
            'stop. Always manage your risk. Past performance is not '
            'indicative of future results. Educational analysis only — not '
            'financial advice.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  /// Flat: no trade running, and the score isn't decisive enough to open
  /// one. A deliberate state, not an error — waiting beats a weak trade.
  Widget _flatCard(GoldMasterAnalysis? a) {
    return GmpCard(
      child: Column(
        children: [
          const SectionLabel('No High-Conviction Signal'),
          const SizedBox(height: 14),
          if (a != null) ...[
            ScoreGauge(score: a.score),
            const SizedBox(height: 14),
            Text(
              'A trade opens only when the Gold Master Score reaches '
              '≥ ${widget.bullishThreshold} (long) or '
              '≤ ${widget.bearishThreshold} (short). Current bias is '
              '${a.bias.label.toLowerCase()} at ${a.score} — flat, waiting '
              'for a higher-probability setup.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
          ] else
            Text(
              _loading ? 'Analysing the market…' : 'Waiting for market data.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
        ],
      ),
    );
  }

  List<Widget> _activeCards(TradeSignal signal) {
    final plan = signal.plan;
    final long = signal.isLong;
    final color = long ? AppTheme.bull : AppTheme.bear;
    final price = _price;
    final open = price == null ? null : signal.unrealised(price);
    final openR =
        (open == null || plan.risk == 0) ? null : open / plan.risk;

    return [
      // Headline instruction, in the plain form the user asked for.
      GmpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(long ? Icons.north_east : Icons.south_east,
                    color: color, size: 26),
                const SizedBox(width: 8),
                Text('${plan.action} SIGNAL',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const Spacer(),
                GmpPill(text: 'Score ${plan.score}', color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Take ${plan.action.toLowerCase()} trade at '
              '${formatPrice(plan.entry)} · TP at ${formatPrice(plan.tp1)} · '
              'SL at ${formatPrice(plan.stop)}',
              style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              '${plan.convictionLabel} conviction · opened '
              '${formatUtcStamp(signal.openedAt)} UTC',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),

      // Live tracking toward the two levels that can close it.
      GmpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Live Tracking'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Current price',
                    style: TextStyle(color: AppTheme.textSecondary)),
                Text(price == null ? '—' : formatPrice(price),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Open result',
                    style: TextStyle(color: AppTheme.textSecondary)),
                Text(
                  open == null
                      ? '—'
                      : '${open >= 0 ? '+' : ''}${open.toStringAsFixed(2)}'
                          '${openR == null ? '' : '  (${openR >= 0 ? '+' : ''}'
                              '${openR.toStringAsFixed(2)}R)'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: open == null
                        ? AppTheme.textSecondary
                        : open >= 0
                            ? AppTheme.bull
                            : AppTheme.bear,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (price != null) _progressBar(signal, price),
            const SizedBox(height: 10),
            const Text(
              'This trade stays open until price reaches the take-profit or '
              'the stop. The next signal is issued only after it closes.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),

      GmpCard(
        child: Column(
          children: [
            _planRow('Entry', formatPrice(plan.entry),
                sub:
                    'zone ${formatPrice(plan.entryLow)} – ${formatPrice(plan.entryHigh)}',
                valueColor: AppTheme.textPrimary),
            const Divider(height: 16, color: AppTheme.hairline),
            _planRow('Stop Loss', formatPrice(plan.stop),
                sub: 'risk ${plan.risk.toStringAsFixed(2)}',
                valueColor: AppTheme.bear),
            const Divider(height: 16, color: AppTheme.hairline),
            _planRow('Take Profit', formatPrice(plan.tp1),
                sub: 'RR ${plan.rr1.toStringAsFixed(1)} · closes the signal',
                valueColor: AppTheme.bull),
            const Divider(height: 16, color: AppTheme.hairline),
            _planRow('Extended Target', formatPrice(plan.tp2),
                sub: 'RR ${plan.rr2.toStringAsFixed(1)} · runner, not tracked',
                valueColor: AppTheme.textSecondary),
          ],
        ),
      ),

      GmpCard(
        child: Row(
          children: [
            _metric('Risk / Reward', '1 : ${plan.rr1.toStringAsFixed(1)}'),
            _metric('Confidence', '${plan.confidence}%'),
            _metric('Conviction', '${plan.conviction}%'),
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

  /// Stop ── current ── target, as a single bar.
  Widget _progressBar(TradeSignal signal, double price) {
    final plan = signal.plan;
    final lo = signal.isLong ? plan.stop : plan.tp1;
    final hi = signal.isLong ? plan.tp1 : plan.stop;
    final span = hi - lo;
    final t = span == 0 ? 0.5 : ((price - lo) / span).clamp(0.0, 1.0);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: 22,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: signal.isLong
                          ? [AppTheme.bear, AppTheme.bull]
                          : [AppTheme.bull, AppTheme.bear]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: (c.maxWidth - 3) * t,
                  child: Container(
                    width: 3,
                    height: 22,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(signal.isLong ? 'SL ${formatPrice(plan.stop)}' : 'TP ${formatPrice(plan.tp1)}',
                style: TextStyle(
                    fontSize: 10,
                    color: signal.isLong ? AppTheme.bear : AppTheme.bull)),
            Text(signal.isLong ? 'TP ${formatPrice(plan.tp1)}' : 'SL ${formatPrice(plan.stop)}',
                style: TextStyle(
                    fontSize: 10,
                    color: signal.isLong ? AppTheme.bull : AppTheme.bear)),
          ],
        ),
      ],
    );
  }

  Widget _historyCard(SignalController signals) {
    final closed = signals.history;
    final total = signals.totalR;
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Signal History'),
          const SizedBox(height: 8),
          Text(
            '${signals.wins}W · ${signals.losses}L · '
            '${total >= 0 ? '+' : ''}${total.toStringAsFixed(2)}R total',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          for (final s in closed.take(8)) _historyRow(s),
        ],
      ),
    );
  }

  Widget _historyRow(TradeSignal s) {
    final win = s.outcome?.isWin ?? false;
    final color = win ? AppTheme.bull : AppTheme.bear;
    final r = s.rMultiple;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(s.plan.action,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
          Expanded(
            child: Text(
              '${formatPrice(s.plan.entry)} → '
              '${formatPrice(s.exitPrice ?? 0)}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          GmpPill(text: s.outcome?.label ?? '', color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              r == null ? '—' : '${r >= 0 ? '+' : ''}${r.toStringAsFixed(1)}R',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planRow(String label, String value,
      {String? sub, required Color valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: valueColor)),
              if (sub != null)
                Text(sub,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
            ],
          ),
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
