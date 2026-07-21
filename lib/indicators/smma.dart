import '../models/candle.dart';

/// Smoothed Moving Average (SMMA). GMP plots SMMA 21 / 50 / 200
/// (spec: Moving Averages).
///
/// Definition: the seed value at index `period - 1` is the simple average
/// of the first `period` values; afterwards
/// `smma[i] = (smma[i-1] * (period - 1) + value[i]) / period`.
class Smma {
  Smma._();

  /// Returns a list aligned with [values]; entries before the warm-up
  /// window (`period - 1`) are null. An SMMA 200 on D1 therefore needs
  /// 200+ candles of history backfill.
  static List<double?> compute(List<double> values, int period) {
    if (period <= 0) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    final out = List<double?>.filled(values.length, null);
    if (values.length < period) return out;

    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += values[i];
    }
    out[period - 1] = sum / period;
    for (var i = period; i < values.length; i++) {
      out[i] = (out[i - 1]! * (period - 1) + values[i]) / period;
    }
    return out;
  }

  static List<double?> fromCandles(List<Candle> candles, int period) =>
      compute([for (final c in candles) c.close], period);
}
