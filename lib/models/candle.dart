/// A single OHLC candle at a given timeframe.
class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  /// Candle open time (UTC). The session day-boundary convention (NY 5 pm
  /// vs UTC midnight) is decided once in Phase 3 — see plan review.
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  bool get isBullish => close >= open;
  double get range => high - low;
  double get body => (close - open).abs();
}
