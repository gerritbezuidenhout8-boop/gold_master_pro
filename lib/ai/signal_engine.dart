import '../models/candle.dart';
import '../models/trade_signal.dart';

/// The close of one signal: which side was hit and at what price.
class SignalResolution {
  const SignalResolution({
    required this.outcome,
    required this.exitPrice,
    required this.at,
  });

  final SignalOutcome outcome;
  final double exitPrice;
  final DateTime at;
}

/// Decides when a running signal is finished — pure and deterministic, so
/// the same rule can be replayed over history or applied to a live tick.
///
/// A signal closes at the first level price reaches: the take-profit
/// ([TradePlan.tp1], the target the plan is judged on) or the stop. The exit
/// is booked *at the level*, modelling a resting limit/stop order rather
/// than guessing slippage.
class SignalEngine {
  SignalEngine._();

  /// Resolution for a live [price] tick, or null while the trade runs.
  static SignalResolution? resolve(
    TradeSignal signal,
    double price, {
    DateTime? now,
  }) {
    if (!signal.isOpen) return null;
    final at = (now ?? DateTime.now().toUtc()).toUtc();
    final plan = signal.plan;
    if (signal.isLong) {
      if (price <= plan.stop) {
        return SignalResolution(
            outcome: SignalOutcome.stopLoss, exitPrice: plan.stop, at: at);
      }
      if (price >= plan.tp1) {
        return SignalResolution(
            outcome: SignalOutcome.takeProfit, exitPrice: plan.tp1, at: at);
      }
      return null;
    }
    if (price >= plan.stop) {
      return SignalResolution(
          outcome: SignalOutcome.stopLoss, exitPrice: plan.stop, at: at);
    }
    if (price <= plan.tp1) {
      return SignalResolution(
          outcome: SignalOutcome.takeProfit, exitPrice: plan.tp1, at: at);
    }
    return null;
  }

  /// Replays [candles] recorded since the signal opened, so a trade that
  /// completed while the app was closed still resolves on the next launch.
  ///
  /// Only bars at/after [TradeSignal.openedAt] are considered. When a single
  /// bar touches both levels the order within it is unknowable, so it counts
  /// as the stop — the conservative reading, never flattering the result.
  static SignalResolution? resolveFromCandles(
    TradeSignal signal,
    List<Candle> candles,
  ) {
    if (!signal.isOpen) return null;
    final plan = signal.plan;
    for (final c in candles) {
      if (c.time.isBefore(signal.openedAt)) continue;
      final hitStop =
          signal.isLong ? c.low <= plan.stop : c.high >= plan.stop;
      final hitTarget =
          signal.isLong ? c.high >= plan.tp1 : c.low <= plan.tp1;
      if (hitStop) {
        return SignalResolution(
            outcome: SignalOutcome.stopLoss,
            exitPrice: plan.stop,
            at: c.time);
      }
      if (hitTarget) {
        return SignalResolution(
            outcome: SignalOutcome.takeProfit,
            exitPrice: plan.tp1,
            at: c.time);
      }
    }
    return null;
  }
}
