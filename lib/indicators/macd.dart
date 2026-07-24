/// Moving Average Convergence/Divergence (MACD) — pure and deterministic.
///
/// MACD line = EMA(fast) − EMA(slow) of close; signal = EMA(signalPeriod)
/// of the MACD line; histogram = MACD − signal. Entries before each stage's
/// warm-up window are null. EMAs seed from the SMA of their first `period`
/// values (the common convention).
class Macd {
  Macd._();

  static MacdResult compute(
    List<double> closes, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    if (fast <= 0 || slow <= 0 || signal <= 0) {
      throw ArgumentError('MACD periods must be positive');
    }
    if (fast >= slow) {
      throw ArgumentError('fast period must be smaller than slow');
    }
    final emaFast = _ema(closes, fast);
    final emaSlow = _ema(closes, slow);
    final n = closes.length;
    final macd = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final f = emaFast[i];
      final s = emaSlow[i];
      if (f != null && s != null) macd[i] = f - s;
    }
    final sig = _emaNullable(macd, signal);
    final hist = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final m = macd[i];
      final g = sig[i];
      if (m != null && g != null) hist[i] = m - g;
    }
    return MacdResult(macd: macd, signal: sig, histogram: hist);
  }

  /// EMA over [period]; seeds with the SMA of the first [period] values.
  static List<double?> _ema(List<double> src, int period) {
    final out = List<double?>.filled(src.length, null);
    if (src.length < period) return out;
    final k = 2 / (period + 1);
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += src[i];
    }
    var ema = sum / period;
    out[period - 1] = ema;
    for (var i = period; i < src.length; i++) {
      ema = (src[i] - ema) * k + ema;
      out[i] = ema;
    }
    return out;
  }

  /// EMA over a nullable series (the MACD line), which becomes non-null
  /// contiguously from one index on. Seeds from the SMA of the first
  /// [period] non-null values.
  static List<double?> _emaNullable(List<double?> src, int period) {
    final out = List<double?>.filled(src.length, null);
    final first = src.indexWhere((v) => v != null);
    if (first < 0 || first + period > src.length) return out;
    final k = 2 / (period + 1);
    var sum = 0.0;
    for (var i = first; i < first + period; i++) {
      sum += src[i]!;
    }
    var ema = sum / period;
    out[first + period - 1] = ema;
    for (var i = first + period; i < src.length; i++) {
      final v = src[i];
      if (v == null) continue;
      ema = (v - ema) * k + ema;
      out[i] = ema;
    }
    return out;
  }
}

/// MACD line, signal line and histogram, each aligned to the input closes.
class MacdResult {
  const MacdResult({
    required this.macd,
    required this.signal,
    required this.histogram,
  });

  final List<double?> macd;
  final List<double?> signal;
  final List<double?> histogram;

  double? get latestMacd => _last(macd);
  double? get latestSignal => _last(signal);
  double? get latestHistogram => _last(histogram);

  /// True when the MACD line is above its signal line (bullish momentum).
  bool? get isBullish {
    final m = latestMacd;
    final s = latestSignal;
    if (m == null || s == null) return null;
    return m > s;
  }

  static double? _last(List<double?> xs) {
    for (var i = xs.length - 1; i >= 0; i--) {
      if (xs[i] != null) return xs[i];
    }
    return null;
  }
}
