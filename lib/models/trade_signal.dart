import '../ai/trade_plan_engine.dart';

/// How a signal finished.
enum SignalOutcome { takeProfit, stopLoss }

extension SignalOutcomeLabel on SignalOutcome {
  String get label =>
      this == SignalOutcome.takeProfit ? 'Take profit' : 'Stop loss';
  bool get isWin => this == SignalOutcome.takeProfit;
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
    this.outcome,
    this.exitPrice,
    this.closedAt,
  });

  final String id;
  final TradePlan plan;
  final DateTime openedAt;

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
        outcome: outcome,
        exitPrice: exitPrice,
        closedAt: at,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'plan': plan.toMap(),
        'openedAt': openedAt.toIso8601String(),
        if (outcome != null) 'outcome': outcome!.name,
        if (exitPrice != null) 'exitPrice': exitPrice,
        if (closedAt != null) 'closedAt': closedAt!.toIso8601String(),
      };

  static TradeSignal fromMap(Map<String, dynamic> m) => TradeSignal(
        id: m['id'] as String,
        plan: TradePlan.fromMap((m['plan'] as Map).cast<String, dynamic>()),
        openedAt: DateTime.parse(m['openedAt'] as String).toUtc(),
        outcome: switch (m['outcome']) {
          'takeProfit' => SignalOutcome.takeProfit,
          'stopLoss' => SignalOutcome.stopLoss,
          _ => null,
        },
        exitPrice: (m['exitPrice'] as num?)?.toDouble(),
        closedAt: m['closedAt'] == null
            ? null
            : DateTime.parse(m['closedAt'] as String).toUtc(),
      );
}
