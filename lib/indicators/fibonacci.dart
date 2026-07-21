import '../models/candle.dart';

/// Fibonacci retracement (spec: Fibonacci).
class Fibonacci {
  Fibonacci._();

  /// Standard ratio set used by GMP.
  static const List<double> ratios = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1];

  /// Price level for each ratio, measured down from [swingHigh] toward
  /// [swingLow] (ratio 0 = the high, ratio 1 = the low).
  static Map<double, double> retracement({
    required double swingHigh,
    required double swingLow,
  }) {
    final range = swingHigh - swingLow;
    return {for (final r in ratios) r: swingHigh - range * r};
  }

  /// Automatic retracement from detected swing pivots.
  ///
  /// A pivot high is a candle whose high strictly exceeds the highs of
  /// [pivotStrength] candles on each side (mirror rule for pivot lows);
  /// the most recent pivot of each kind within the last [lookback]
  /// candles anchors the swing. When no pivot exists (monotonic data or
  /// plateaus), the window's absolute extreme is used instead. The leg
  /// direction follows whichever anchor is more recent: an up-leg
  /// measures ratio 0 at the high going down; a down-leg measures
  /// ratio 0 at the low going up.
  static AutoFibResult auto(
    List<Candle> candles, {
    int pivotStrength = 5,
    int lookback = 120,
  }) {
    if (candles.isEmpty) throw ArgumentError('candles must not be empty');
    final w = candles.length > lookback
        ? candles.sublist(candles.length - lookback)
        : candles;

    int? hi, lo;
    for (var i = w.length - 1 - pivotStrength; i >= pivotStrength; i--) {
      if (hi == null && _isPivot(w, i, pivotStrength, high: true)) hi = i;
      if (lo == null && _isPivot(w, i, pivotStrength, high: false)) lo = i;
      if (hi != null && lo != null) break;
    }
    hi ??= _extremeIndex(w, high: true);
    lo ??= _extremeIndex(w, high: false);

    final high = w[hi].high;
    final low = w[lo].low;
    final isUp = !w[hi].time.isBefore(w[lo].time);
    final range = high - low;
    return AutoFibResult(
      swingHigh: high,
      swingLow: low,
      swingHighTime: w[hi].time,
      swingLowTime: w[lo].time,
      isUpLeg: isUp,
      levels: {
        for (final r in ratios) r: isUp ? high - range * r : low + range * r,
      },
    );
  }

  static bool _isPivot(List<Candle> w, int i, int s, {required bool high}) {
    for (var j = i - s; j <= i + s; j++) {
      if (j == i) continue;
      if (high ? w[j].high >= w[i].high : w[j].low <= w[i].low) return false;
    }
    return true;
  }

  static int _extremeIndex(List<Candle> w, {required bool high}) {
    var best = 0;
    for (var i = 1; i < w.length; i++) {
      if (high ? w[i].high > w[best].high : w[i].low < w[best].low) best = i;
    }
    return best;
  }
}

class AutoFibResult {
  const AutoFibResult({
    required this.swingHigh,
    required this.swingLow,
    required this.swingHighTime,
    required this.swingLowTime,
    required this.isUpLeg,
    required this.levels,
  });

  final double swingHigh;
  final double swingLow;
  final DateTime swingHighTime;
  final DateTime swingLowTime;
  final bool isUpLeg;

  /// ratio → price, oriented per leg direction (see [Fibonacci.auto]).
  final Map<double, double> levels;
}
