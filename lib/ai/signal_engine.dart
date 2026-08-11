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
    // Ratchet before testing: a tick that sets a new extreme moves the stop
    // up behind it, and can never be the tick that hits it.
    final advanced = signal.withPeak(price);
    final stop = advanced.trailingStop;
    final stopOutcome = advanced.isTrailing
        ? SignalOutcome.trailingStop
        : SignalOutcome.stopLoss;
    if (signal.isLong) {
      if (price <= stop) {
        return SignalResolution(
            outcome: stopOutcome, exitPrice: stop, at: at);
      }
      if (price >= plan.tp1) {
        return SignalResolution(
            outcome: SignalOutcome.takeProfit, exitPrice: plan.tp1, at: at);
      }
      return null;
    }
    if (price >= stop) {
      return SignalResolution(outcome: stopOutcome, exitPrice: stop, at: at);
    }
    if (price <= plan.tp1) {
      return SignalResolution(
          outcome: SignalOutcome.takeProfit, exitPrice: plan.tp1, at: at);
    }
    return null;
  }

  /// [signal] with its peak advanced over [candles] — so on launch the trail
  /// resumes where the market left it instead of resetting to entry.
  static TradeSignal advanceOverCandles(
    TradeSignal signal,
    List<Candle> candles,
  ) {
    var running = signal;
    for (final c in candles) {
      if (c.time.isBefore(signal.openedAt)) continue;
      running = running.withPeak(signal.isLong ? c.high : c.low);
    }
    return running;
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
    var running = signal;
    for (final c in candles) {
      if (c.time.isBefore(signal.openedAt)) continue;
      // Test against the trail as it stood *entering* this bar. Intrabar
      // order is unknowable, so the bar's own new high never gets credited
      // with having lifted the stop before price came back to hit it.
      final stop = running.trailingStop;
      final stopOutcome = running.isTrailing
          ? SignalOutcome.trailingStop
          : SignalOutcome.stopLoss;
      final hitStop = signal.isLong ? c.low <= stop : c.high >= stop;
      final hitTarget =
          signal.isLong ? c.high >= plan.tp1 : c.low <= plan.tp1;
      if (hitStop) {
        return SignalResolution(
            outcome: stopOutcome, exitPrice: stop, at: c.time);
      }
      if (hitTarget) {
        return SignalResolution(
            outcome: SignalOutcome.takeProfit,
            exitPrice: plan.tp1,
            at: c.time);
      }
      running = running.withPeak(signal.isLong ? c.high : c.low);
    }
    return null;
  }
}
