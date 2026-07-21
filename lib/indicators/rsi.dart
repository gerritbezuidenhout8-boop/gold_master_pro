import '../models/candle.dart';

/// Relative Strength Index (Wilder's smoothing) plus Stochastic RSI and
/// RSI-divergence detection — all pure and deterministic.
class Rsi {
  Rsi._();

  /// RSI over [period]; entries before the warm-up window are null.
  ///
  /// Seeds the first average as the simple mean of the first [period]
  /// changes (Wilder), then smooths recursively. RSI is 100 when there
  /// are no losses in the window, 0 when there are no gains.
  static List<double?> compute(List<double> closes, {int period = 14}) {
    if (period <= 0) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    final out = List<double?>.filled(closes.length, null);
    if (closes.length <= period) return out;

    var gain = 0.0, loss = 0.0;
    for (var i = 1; i <= period; i++) {
      final change = closes[i] - closes[i - 1];
      if (change >= 0) {
        gain += change;
      } else {
        loss -= change;
      }
    }
    var avgGain = gain / period;
    var avgLoss = loss / period;
    out[period] = _rsi(avgGain, avgLoss);

    for (var i = period + 1; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      final g = change > 0 ? change : 0.0;
      final l = change < 0 ? -change : 0.0;
      avgGain = (avgGain * (period - 1) + g) / period;
      avgLoss = (avgLoss * (period - 1) + l) / period;
      out[i] = _rsi(avgGain, avgLoss);
    }
    return out;
  }

  static double _rsi(double avgGain, double avgLoss) {
    if (avgLoss == 0) return avgGain == 0 ? 50 : 100;
    final rs = avgGain / avgLoss;
    return 100 - 100 / (1 + rs);
  }
}

/// Stochastic RSI %K and %D (both 0–100).
///
/// Applies the stochastic formula to the RSI series, then smooths: raw
/// StochRSI = (rsi - min)/(max - min) over [stochPeriod]; %K = SMA(raw,
/// [kSmooth]); %D = SMA(%K, [dSmooth]).
class StochRsi {
  StochRsi._();

  static ({List<double?> k, List<double?> d}) compute(
    List<double> closes, {
    int rsiPeriod = 14,
    int stochPeriod = 14,
    int kSmooth = 3,
    int dSmooth = 3,
  }) {
    final rsi = Rsi.compute(closes, period: rsiPeriod);
    final n = closes.length;
    final raw = List<double?>.filled(n, null);

    for (var i = 0; i < n; i++) {
      if (i < stochPeriod - 1) continue;
      double? lo, hi;
      var complete = true;
      for (var j = i - stochPeriod + 1; j <= i; j++) {
        final v = rsi[j];
        if (v == null) {
          complete = false;
          break;
        }
        lo = (lo == null || v < lo) ? v : lo;
        hi = (hi == null || v > hi) ? v : hi;
      }
      if (!complete || lo == null || hi == null) continue;
      raw[i] = (hi - lo).abs() < 1e-12 ? 0.0 : (rsi[i]! - lo) / (hi - lo) * 100;
    }

    final k = _sma(raw, kSmooth);
    final d = _sma(k, dSmooth);
    return (k: k, d: d);
  }

  static List<double?> _sma(List<double?> src, int window) {
    final out = List<double?>.filled(src.length, null);
    for (var i = 0; i < src.length; i++) {
      if (i < window - 1) continue;
      var sum = 0.0;
      var ok = true;
      for (var j = i - window + 1; j <= i; j++) {
        final v = src[j];
        if (v == null) {
          ok = false;
          break;
        }
        sum += v;
      }
      if (ok) out[i] = sum / window;
    }
    return out;
  }
}

enum DivergenceType { bullish, bearish }

extension DivergenceTypeLabel on DivergenceType {
  String get label =>
      this == DivergenceType.bullish ? 'Bullish divergence' : 'Bearish divergence';
}

/// A detected divergence anchored at the later of the two pivots.
class DivergenceEvent {
  const DivergenceEvent({required this.index, required this.type});

  final int index;
  final DivergenceType type;
}

/// Classic RSI divergence: price makes a lower low while RSI makes a
/// higher low (bullish), or price a higher high while RSI a lower high
/// (bearish). Compares consecutive confirmed pivots.
class RsiDivergence {
  RsiDivergence._();

  static List<DivergenceEvent> detect(
    List<Candle> candles, {
    int rsiPeriod = 14,
    int pivotStrength = 5,
  }) {
    if (candles.length < rsiPeriod + pivotStrength * 2 + 2) return const [];
    final rsi = Rsi.compute([for (final c in candles) c.close], period: rsiPeriod);

    final lows = <int>[]; // pivot-low indices
    final highs = <int>[]; // pivot-high indices
    for (var i = pivotStrength; i < candles.length - pivotStrength; i++) {
      if (rsi[i] == null) continue;
      if (_isPivot(candles, i, pivotStrength, low: true)) lows.add(i);
      if (_isPivot(candles, i, pivotStrength, low: false)) highs.add(i);
    }

    final events = <DivergenceEvent>[];
    for (var i = 1; i < lows.length; i++) {
      final a = lows[i - 1], b = lows[i];
      if (candles[b].low < candles[a].low && rsi[b]! > rsi[a]!) {
        events.add(DivergenceEvent(index: b, type: DivergenceType.bullish));
      }
    }
    for (var i = 1; i < highs.length; i++) {
      final a = highs[i - 1], b = highs[i];
      if (candles[b].high > candles[a].high && rsi[b]! < rsi[a]!) {
        events.add(DivergenceEvent(index: b, type: DivergenceType.bearish));
      }
    }
    events.sort((x, y) => x.index.compareTo(y.index));
    return events;
  }

  static bool _isPivot(List<Candle> c, int i, int s, {required bool low}) {
    for (var j = i - s; j <= i + s; j++) {
      if (j == i) continue;
      if (low ? c[j].low <= c[i].low : c[j].high >= c[i].high) return false;
    }
    return true;
  }
}
