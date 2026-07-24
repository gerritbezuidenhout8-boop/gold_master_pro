import '../models/candle.dart';

/// Average True Range (Wilder) — volatility used to size stops/targets.
class Atr {
  Atr._();

  /// Latest ATR over [period]; null when there isn't enough data.
  static double? latest(List<Candle> candles, {int period = 14}) {
    if (candles.length < period + 1) return null;
    final tr = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final h = candles[i].high;
      final l = candles[i].low;
      final pc = candles[i - 1].close;
      final t = [h - l, (h - pc).abs(), (l - pc).abs()]
          .reduce((a, b) => a > b ? a : b);
      tr.add(t);
    }
    if (tr.length < period) return null;
    var atr = 0.0;
    for (var i = 0; i < period; i++) {
      atr += tr[i];
    }
    atr /= period;
    for (var i = period; i < tr.length; i++) {
      atr = (atr * (period - 1) + tr[i]) / period;
    }
    return atr;
  }
}
