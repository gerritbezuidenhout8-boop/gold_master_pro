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
    List<Candle> candles, {
    Duration? barInterval,
  }) {
    final interval = barInterval ?? inferBarInterval(candles);
    var running = signal;
    for (final c in candles) {
      if (!_counts(c, signal.openedAt, interval)) continue;
      running = running.withPeak(signal.isLong ? c.high : c.low);
    }
    return running;
  }

  /// Whether [c] covers any time after [openedAt].
  ///
  /// A candle's `time` is its *open*, so a bar counts when its **end** falls
  /// after the trade opened — that is what keeps the bar the trade started
  /// inside. With no interval to work from (a single bar), fall back to the
  /// bar's open time rather than guessing a length.
  static bool _counts(Candle c, DateTime openedAt, Duration? interval) =>
      interval == null
          ? !c.time.isBefore(openedAt)
          : c.time.add(interval).isAfter(openedAt);

  /// Bar length inferred from [candles] — the smallest positive gap between
  /// consecutive opens, so weekend and session gaps do not inflate it.
  /// Null when there is nothing to infer from.
  static Duration? inferBarInterval(List<Candle> candles) {
    Duration? smallest;
    for (var i = 1; i < candles.length; i++) {
      final gap = candles[i].time.difference(candles[i - 1].time);
      if (gap <= Duration.zero) continue;
      if (smallest == null || gap < smallest) smallest = gap;
    }
    return smallest;
  }

  /// Replays [candles] recorded since the signal opened, so a trade that
  /// completed while the app was closed still resolves on the next launch.
  ///
  /// A bar counts once **any part of it falls after** [TradeSignal.openedAt],
  /// which includes the bar the trade opened inside. Comparing the bar's
  /// *open* time instead — a candle's `time` is when it opened, not when it
  /// closed — threw away everything from entry to the end of that bar. On H1
  /// that is up to a full hour, easily the hour in which the target was
  /// reached, and the trade would then sit open forever if price came back.
  ///
  /// The cost is that the containing bar's extreme may have happened just
  /// before entry. That is the lesser evil: ignoring an hour of genuine
  /// post-entry action is far worse, and the both-levels rule below still
  /// refuses to flatter the outcome.
  ///
  /// When a single bar touches both levels the order within it is unknowable,
  /// so it counts as the stop — the conservative reading.
  static SignalResolution? resolveFromCandles(
    TradeSignal signal,
    List<Candle> candles, {
    Duration? barInterval,
  }) {
    if (!signal.isOpen) return null;
    final plan = signal.plan;
    final interval = barInterval ?? inferBarInterval(candles);
    var running = signal;
    for (final c in candles) {
      if (!_counts(c, signal.openedAt, interval)) continue;
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
