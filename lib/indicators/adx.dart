import '../models/candle.dart';

/// One bar of directional-movement output.
class AdxResult {
  const AdxResult({
    required this.adx,
    required this.plusDI,
    required this.minusDI,
  });

  final double adx;
  final double plusDI;
  final double minusDI;

  /// ADX ≥ 25 is the common "trending" threshold; below ~20 is choppy.
  bool get isTrending => adx >= 25;

  /// Direction of the trend from the dominant DI line.
  bool get isBullish => plusDI >= minusDI;
}

/// Average Directional Index with +DI / −DI (Wilder) — pure and
/// deterministic. ADX measures trend strength (0–100), the DI lines its
/// direction. Uses Wilder's smoothed sums for the DI lines and Wilder
/// averaging for the ADX line.
class Adx {
  Adx._();

  /// Full ADX series from the first computable bar onward; empty when there
  /// isn't enough data (needs roughly 2×[period] bars to warm up).
  static List<AdxResult> series(List<Candle> candles, {int period = 14}) {
    if (period <= 0) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    final n = candles.length;
    final tr = <double>[];
    final plusDM = <double>[];
    final minusDM = <double>[];
    for (var i = 1; i < n; i++) {
      final up = candles[i].high - candles[i - 1].high;
      final down = candles[i - 1].low - candles[i].low;
      plusDM.add((up > down && up > 0) ? up : 0.0);
      minusDM.add((down > up && down > 0) ? down : 0.0);
      final h = candles[i].high;
      final l = candles[i].low;
      final pc = candles[i - 1].close;
      tr.add([h - l, (h - pc).abs(), (l - pc).abs()]
          .reduce((a, b) => a > b ? a : b));
    }
    if (tr.length < period) return const [];

    double di(double dm, double t) => t == 0 ? 0 : 100 * dm / t;

    // Wilder-smoothed sums seeded from the first `period` values.
    var trS = 0.0, pS = 0.0, mS = 0.0;
    for (var i = 0; i < period; i++) {
      trS += tr[i];
      pS += plusDM[i];
      mS += minusDM[i];
    }
    final dx = <double>[];
    final plusDIs = <double>[];
    final minusDIs = <double>[];
    var plusDI = di(pS, trS), minusDI = di(mS, trS);
    plusDIs.add(plusDI);
    minusDIs.add(minusDI);
    dx.add(_dx(plusDI, minusDI));
    for (var i = period; i < tr.length; i++) {
      trS = trS - trS / period + tr[i];
      pS = pS - pS / period + plusDM[i];
      mS = mS - mS / period + minusDM[i];
      plusDI = di(pS, trS);
      minusDI = di(mS, trS);
      plusDIs.add(plusDI);
      minusDIs.add(minusDI);
      dx.add(_dx(plusDI, minusDI));
    }

    if (dx.length < period) return const [];
    final out = <AdxResult>[];
    var adx = 0.0;
    for (var i = 0; i < period; i++) {
      adx += dx[i];
    }
    adx /= period;
    out.add(AdxResult(
        adx: adx, plusDI: plusDIs[period - 1], minusDI: minusDIs[period - 1]));
    for (var i = period; i < dx.length; i++) {
      adx = (adx * (period - 1) + dx[i]) / period;
      out.add(AdxResult(adx: adx, plusDI: plusDIs[i], minusDI: minusDIs[i]));
    }
    return out;
  }

  /// Latest ADX/+DI/−DI, or null when there isn't enough data.
  static AdxResult? latest(List<Candle> candles, {int period = 14}) {
    final s = series(candles, period: period);
    return s.isEmpty ? null : s.last;
  }

  static double _dx(double plusDI, double minusDI) {
    final sum = plusDI + minusDI;
    return sum == 0 ? 0 : 100 * (plusDI - minusDI).abs() / sum;
  }
}
