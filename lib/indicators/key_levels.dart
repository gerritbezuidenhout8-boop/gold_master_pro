import '../models/candle.dart';

/// Session key levels (spec: Key Levels) computed from DAILY candles.
///
/// Day-boundary convention (decided in step 3): **UTC midnight**, because
/// the Binance feed's D1 candles open at 00:00 UTC and PAXG trades 24/7.
/// A week starts Monday 00:00 UTC. Apply this convention everywhere; do
/// not mix it with broker-style New York 5 pm rollover.
class KeyLevels {
  KeyLevels._();

  /// [dailyCandles] must be ascending, UTC-midnight-opened daily candles;
  /// the last candle is treated as "today".
  static KeyLevelsResult compute(List<Candle> dailyCandles) {
    if (dailyCandles.isEmpty) {
      throw ArgumentError('dailyCandles must not be empty');
    }
    final today = dailyCandles.last;
    final prevDay = dailyCandles.length > 1
        ? dailyCandles[dailyCandles.length - 2]
        : null;

    final ws = weekStart(today.time);
    final prevWs = ws.subtract(const Duration(days: 7));

    double? weekHigh, weekLow, prevWeekHigh, prevWeekLow;
    var allTimeHigh = today.high;
    for (final c in dailyCandles) {
      if (c.high > allTimeHigh) allTimeHigh = c.high;
      if (!c.time.isBefore(ws)) {
        weekHigh = weekHigh == null || c.high > weekHigh ? c.high : weekHigh;
        weekLow = weekLow == null || c.low < weekLow ? c.low : weekLow;
      } else if (!c.time.isBefore(prevWs)) {
        prevWeekHigh =
            prevWeekHigh == null || c.high > prevWeekHigh ? c.high : prevWeekHigh;
        prevWeekLow =
            prevWeekLow == null || c.low < prevWeekLow ? c.low : prevWeekLow;
      }
    }

    return KeyLevelsResult(
      asOf: today.time,
      dailyOpen: today.open,
      dailyHigh: today.high,
      dailyLow: today.low,
      prevDayHigh: prevDay?.high,
      prevDayLow: prevDay?.low,
      weekHigh: weekHigh ?? today.high,
      weekLow: weekLow ?? today.low,
      prevWeekHigh: prevWeekHigh,
      prevWeekLow: prevWeekLow,
      allTimeHigh: allTimeHigh,
    );
  }

  /// Monday 00:00 UTC of the week containing [t].
  static DateTime weekStart(DateTime t) {
    final day = DateTime.utc(t.year, t.month, t.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}

class KeyLevelsResult {
  const KeyLevelsResult({
    required this.asOf,
    required this.dailyOpen,
    required this.dailyHigh,
    required this.dailyLow,
    required this.prevDayHigh,
    required this.prevDayLow,
    required this.weekHigh,
    required this.weekLow,
    required this.prevWeekHigh,
    required this.prevWeekLow,
    required this.allTimeHigh,
  });

  final DateTime asOf;
  final double dailyOpen;
  final double dailyHigh;
  final double dailyLow;
  final double? prevDayHigh;
  final double? prevDayLow;
  final double weekHigh;
  final double weekLow;
  final double? prevWeekHigh;
  final double? prevWeekLow;

  /// Highest high within the LOADED history (500 daily candles from the
  /// feed) — a true all-time high needs deeper data.
  final double allTimeHigh;
}
