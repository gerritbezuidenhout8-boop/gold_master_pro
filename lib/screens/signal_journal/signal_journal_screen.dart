import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/trade_signal.dart';
import '../../state/signal_controller.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/stat_tile.dart';

/// The full record of every signal the app has issued, and how each one
/// finished.
///
/// The Trade Plan screen shows only the last handful inline; this is the
/// complete list, kept deliberately plain so the record is easy to audit.
/// Nothing here is editable — a signal's levels are frozen when it opens
/// (the plan is stored by value), so what you read is what it was judged on.
class SignalJournalScreen extends StatelessWidget {
  const SignalJournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signal Journal')),
      body: AnimatedBuilder(
        animation: SignalController.instance,
        builder: (context, _) {
          final signals = SignalController.instance;
          final all = signals.signals; // newest first, open one included
          if (all.isEmpty) return const _EmptyJournal();
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              _summary(signals),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: SectionLabel('Every signal'),
              ),
              for (final s in all) _SignalTile(signal: s),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(SignalController signals) {
    final closed = signals.history;
    final total = signals.totalR;
    final rate = closed.isEmpty
        ? null
        : (signals.wins / closed.length * 100).round();
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Record'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Win rate',
                  value: rate == null ? '—' : '$rate%',
                  note: closed.isEmpty
                      ? 'no closed signals'
                      : 'of ${closed.length} closed',
                  noteColor:
                      (rate ?? 0) >= 50 ? AppTheme.bull : AppTheme.gold,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Won / lost',
                  value: '${signals.wins}W · ${signals.losses}L',
                  note: 'counted on result',
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Total',
                  value: '${total >= 0 ? '+' : ''}'
                      '${total.toStringAsFixed(2)}R',
                  note: 'risk multiples',
                  noteColor: total >= 0 ? AppTheme.bull : AppTheme.bear,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fact_check_outlined,
                color: AppTheme.gold, size: 40),
            const SizedBox(height: 14),
            const Text(
              'No signals yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'A signal is only opened on a high-conviction read, and never '
              'while a trade is already running. Flat is a normal state — '
              'every signal that does open will be recorded here with how it '
              'finished.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One signal: direction, the levels it was judged on, and its outcome.
class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});

  final TradeSignal signal;

  @override
  Widget build(BuildContext context) {
    final plan = signal.plan;
    final open = signal.isOpen;
    final win = signal.isWin;
    // An open trade has no result yet, so it reads gold rather than
    // green/red — nothing has been decided.
    final color =
        open ? AppTheme.gold : (win ? AppTheme.bull : AppTheme.bear);
    final r = signal.rMultiple;

    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  signal.isLong
                      ? Icons.north_east
                      : Icons.south_east,
                  color: signal.isLong ? AppTheme.bull : AppTheme.bear,
                  size: 18),
              const SizedBox(width: 6),
              Text(plan.action,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: signal.isLong ? AppTheme.bull : AppTheme.bear)),
              const SizedBox(width: 8),
              GmpPill(
                text: open ? 'Running' : (signal.outcome?.label ?? ''),
                color: color,
              ),
              const Spacer(),
              if (r != null)
                Text(
                  '${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}R',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _row('Entry', formatPrice(plan.entry)),
          // The stop as it stood at the end: a trailed stop is the level that
          // actually mattered, not the one the plan opened with.
          _row(
            signal.isTrailing ? 'Stop (trailed)' : 'Stop',
            signal.isTrailing
                ? '${formatPrice(plan.stop)} → ${formatPrice(signal.trailingStop)}'
                : formatPrice(plan.stop),
          ),
          _row('Target', formatPrice(plan.tp1)),
          if (!open) _row('Exit', formatPrice(signal.exitPrice ?? 0)),
          const SizedBox(height: 8),
          Text(
            open
                ? 'Opened ${formatUtcStamp(signal.openedAt)} UTC · score '
                    '${plan.score}'
                : 'Opened ${formatUtcStamp(signal.openedAt)} · closed '
                    '${formatUtcStamp(signal.closedAt ?? signal.openedAt)} '
                    'UTC · score ${plan.score}',
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
            Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ],
        ),
      );
}
