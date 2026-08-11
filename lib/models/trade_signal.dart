import 'dart:math' as math;

import '../ai/trade_plan_engine.dart';

/// How a signal finished. [trailingStop] is a stop that had ratcheted above
/// (long) or below (short) its original level, so it can close in profit —
/// which is why wins are judged on money, not on which level was hit.
enum SignalOutcome { takeProfit, stopLoss, trailingStop }

extension SignalOutcomeLabel on SignalOutcome {
  String get label => switch (this) {
        SignalOutcome.takeProfit => 'Take profit',
        SignalOutcome.stopLoss => 'Stop loss',
        SignalOutcome.trailingStop => 'Trailing stop',
      };
}

/// One issued signal and its lifecycle: the plan snapshot taken when it was
/// opened, then — once price reaches the take-profit or the stop — the exit.
///
/// Only one signal is open at a time (see `SignalController`); the plan is
/// stored by value so a closed signal keeps the exact levels it was judged
/// on, even after the market moves.
class TradeSignal {
  const TradeSignal({
    required this.id,
    required this.plan,
    required this.openedAt,
    this.recordedPeak,
    this.outcome,
    this.exitPrice,
    this.closedAt,
  });

  final String id;
  final TradePlan plan;
  final DateTime openedAt;

  /// Raw water mark as stored: null before the first ratchet, and on signals
  /// persisted before trailing existed. Read [peak] instead.
  final double? recordedPeak;

  /// Best price reached in the trade's favour since it opened — the high
  /// water mark for a long, the low water mark for a short. Defaults to the
  /// entry, so a signal stored before trailing existed simply starts its
  /// trail from entry rather than breaking.
  double get peak => recordedPeak ?? plan.entry;

  /// How far the stop trails behind [peak], in price. See
  /// [TradePlanEngine.trailRiskMultiple] for why it is 1.5R and not 1R.
  double get trailDistance =>
      plan.risk * TradePlanEngine.trailRiskMultiple;

  /// The stop actually in force. It starts at the plan's stop and ratchets in
  /// the trade's favour as [peak] advances, never moving against the trade.
  ///
  /// Entry 4020 with a stop at 4000 is a 20 risk, so the trail sits 30 (1.5R)
  /// behind the best price: at 4060 the stop is 4030. Once price has advanced
  /// past 1.5R the stop is above entry and a pullback closes in profit.
  double get trailingStop => isLong
      ? math.max(plan.stop, peak - trailDistance)
      : math.min(plan.stop, peak + trailDistance);

  /// Whether the stop has ratcheted away from its original level.
  bool get isTrailing => trailingStop != plan.stop;

  /// This signal with [peak] advanced by [price], or itself when [price] is
  /// not a new extreme. The stop never retreats, so this only ever ratchets.
  TradeSignal withPeak(double price) {
    final next = isLong ? math.max(peak, price) : math.min(peak, price);
    if (next == peak) return this;
    return TradeSignal(
      id: id,
      plan: plan,
      openedAt: openedAt,
      recordedPeak: next,
      outcome: outcome,
      exitPrice: exitPrice,
      closedAt: closedAt,
    );
  }

  /// Null while the signal is still running.
  final SignalOutcome? outcome;
  final double? exitPrice;
  final DateTime? closedAt;

  bool get isOpen => outcome == null;
  bool get isLong => plan.direction == TradeDirection.long;

  /// Signed move in the trade's favour at [price] (negative = losing).
  double unrealised(double price) =>
      isLong ? price - plan.entry : plan.entry - price;

  /// Realised move once closed, else null.
  double? get realised =>
      exitPrice == null ? null : unrealised(exitPrice!);

  /// Judged on money, not on which level was hit: a trailing stop can close
  /// in profit, and that counts as a win.
  bool get isWin => (realised ?? 0) > 0;

  /// Result in R (risk multiples) once closed, else null.
  double? get rMultiple {
    final r = realised;
    if (r == null || plan.risk == 0) return null;
    return r / plan.risk;
  }

  /// Progress from entry toward the take-profit at [price], 0–1. Clamped, so
  /// a losing trade reads 0 (the stop side is shown separately).
  double progressToTarget(double price) {
    final span = (plan.tp1 - plan.entry).abs();
    if (span == 0) return 0;
    return (unrealised(price) / span).clamp(0.0, 1.0);
  }

  TradeSignal close({
    required SignalOutcome outcome,
    required double exitPrice,
    required DateTime at,
  }) =>
      TradeSignal(
        id: id,
        plan: plan,
        openedAt: openedAt,
        recordedPeak: recordedPeak,
        outcome: outcome,
        exitPrice: exitPrice,
        closedAt: at,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'plan': plan.toMap(),
        'openedAt': openedAt.toIso8601String(),
        'peak': peak,
        if (outcome != null) 'outcome': outcome!.name,
        if (exitPrice != null) 'exitPrice': exitPrice,
        if (closedAt != null) 'closedAt': closedAt!.toIso8601String(),
      };

  static TradeSignal fromMap(Map<String, dynamic> m) => TradeSignal(
        id: m['id'] as String,
        plan: TradePlan.fromMap((m['plan'] as Map).cast<String, dynamic>()),
        openedAt: DateTime.parse(m['openedAt'] as String).toUtc(),
        // Absent on signals stored before trailing existed — peak falls back
        // to the entry, which just restarts the trail.
        recordedPeak: (m['peak'] as num?)?.toDouble(),
        outcome: switch (m['outcome']) {
          'takeProfit' => SignalOutcome.takeProfit,
          'stopLoss' => SignalOutcome.stopLoss,
          'trailingStop' => SignalOutcome.trailingStop,
          _ => null,
        },
        exitPrice: (m['exitPrice'] as num?)?.toDouble(),
        closedAt: m['closedAt'] == null
            ? null
            : DateTime.parse(m['closedAt'] as String).toUtc(),
      );
}
