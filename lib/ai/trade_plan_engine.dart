import '../indicators/atr.dart';
import '../indicators/key_levels.dart';
import '../models/candle.dart';
import '../models/journal_entry.dart' show TradeDirection;
import 'gold_master_engine.dart';

export '../models/journal_entry.dart' show TradeDirection, TradeDirectionLabel;

/// A concrete, deterministic trade plan derived from the Gold Master
/// Score. Analysis/education only — never an instruction to trade.
class TradePlan {
  const TradePlan({
    required this.direction,
    required this.score,
    required this.confidence,
    required this.entry,
    required this.entryLow,
    required this.entryHigh,
    required this.stop,
    required this.tp1,
    required this.tp2,
    required this.risk,
    required this.rr1,
    required this.rr2,
    required this.validUntil,
    required this.rationale,
  });

  final TradeDirection direction;
  final int score;
  final int confidence;
  final double entry;
  final double entryLow;
  final double entryHigh;
  final double stop;
  final double tp1;
  final double tp2;

  /// Absolute risk per unit (|entry − stop|).
  final double risk;
  final double rr1;
  final double rr2;
  final DateTime validUntil;
  final List<String> rationale;

  String get action => direction == TradeDirection.long ? 'BUY' : 'SELL';
}

/// Turns a high-conviction Gold Master Score into an entry / stop /
/// take-profit plan. Returns null unless the score clears the bullish or
/// bearish conviction threshold — no signal in the neutral middle.
class TradePlanEngine {
  TradePlanEngine._();

  static TradePlan? generate({
    required GoldMasterAnalysis analysis,
    required List<Candle> candles,
    required KeyLevelsResult levels,
    int bullishThreshold = 80,
    int bearishThreshold = 20,
    DateTime? now,
  }) {
    if (candles.isEmpty) return null;
    final long = analysis.score >= bullishThreshold;
    final short = analysis.score <= bearishThreshold;
    if (!long && !short) return null;

    final entry = candles.last.close;
    final atr = Atr.latest(candles) ?? entry * 0.0015;
    final n = candles.length;
    final window = candles.sublist(n > 20 ? n - 20 : 0);

    final nowUtc = (now ?? DateTime.now().toUtc()).toUtc();
    // Valid until the next UTC daily close (levels are daily-based).
    final validUntil = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day)
        .add(const Duration(days: 1));

    if (long) {
      final swingLow =
          window.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      var stop = swingLow - 0.2 * atr;
      final rawRisk = entry - stop;
      if (rawRisk < 0.8 * atr) {
        stop = entry - 0.8 * atr;
      } else if (rawRisk > 3 * atr) {
        stop = entry - 3 * atr;
      }
      final risk = entry - stop;
      final resistances = <double>[
        levels.dailyHigh,
        levels.weekHigh,
        levels.allTimeHigh,
        if (levels.prevDayHigh != null) levels.prevDayHigh!,
        if (levels.prevWeekHigh != null) levels.prevWeekHigh!,
      ]..sort();
      final above =
          resistances.where((r) => r > entry + 0.25 * risk).toList();
      final tp1 = above.isNotEmpty ? above[0] : entry + 1.5 * risk;
      final tp2 = above.length >= 2 ? above[1] : entry + 3 * risk;
      return TradePlan(
        direction: TradeDirection.long,
        score: analysis.score,
        confidence: analysis.confidence,
        entry: entry,
        entryLow: entry - 0.25 * atr,
        entryHigh: entry + 0.10 * atr,
        stop: stop,
        tp1: tp1,
        tp2: tp2,
        risk: risk,
        rr1: (tp1 - entry) / risk,
        rr2: (tp2 - entry) / risk,
        validUntil: validUntil,
        rationale: analysis.topReasons,
      );
    }

    // Short (mirror).
    final swingHigh =
        window.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    var stop = swingHigh + 0.2 * atr;
    final rawRisk = stop - entry;
    if (rawRisk < 0.8 * atr) {
      stop = entry + 0.8 * atr;
    } else if (rawRisk > 3 * atr) {
      stop = entry + 3 * atr;
    }
    final risk = stop - entry;
    final supports = <double>[
      levels.dailyLow,
      levels.weekLow,
      if (levels.prevDayLow != null) levels.prevDayLow!,
      if (levels.prevWeekLow != null) levels.prevWeekLow!,
    ]..sort((a, b) => b.compareTo(a)); // descending
    final below = supports.where((s) => s < entry - 0.25 * risk).toList();
    final tp1 = below.isNotEmpty ? below[0] : entry - 1.5 * risk;
    final tp2 = below.length >= 2 ? below[1] : entry - 3 * risk;
    return TradePlan(
      direction: TradeDirection.short,
      score: analysis.score,
      confidence: analysis.confidence,
      entry: entry,
      entryLow: entry - 0.10 * atr,
      entryHigh: entry + 0.25 * atr,
      stop: stop,
      tp1: tp1,
      tp2: tp2,
      risk: risk,
      rr1: (entry - tp1) / risk,
      rr2: (entry - tp2) / risk,
      validUntil: validUntil,
      rationale: analysis.topReasons,
    );
  }
}
