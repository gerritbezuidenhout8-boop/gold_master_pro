import 'dart:math' as math;

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

  /// How strongly the score favours the direction (0–100): the distance of
  /// the score from the neutral 50, doubled.
  int get conviction => ((score - 50).abs() * 2).clamp(0, 100);

  String get convictionLabel => conviction >= 60
      ? 'High'
      : conviction >= 30
          ? 'Moderate'
          : 'Low';

  /// A high-conviction setup (score ≥ 80 or ≤ 20) — what [generate] gates on.
  bool get isHighConviction => conviction >= 60;

  Map<String, dynamic> toMap() => {
        'direction': direction.name,
        'score': score,
        'confidence': confidence,
        'entry': entry,
        'entryLow': entryLow,
        'entryHigh': entryHigh,
        'stop': stop,
        'tp1': tp1,
        'tp2': tp2,
        'risk': risk,
        'rr1': rr1,
        'rr2': rr2,
        'validUntil': validUntil.toIso8601String(),
        'rationale': rationale,
      };

  static TradePlan fromMap(Map<String, dynamic> m) => TradePlan(
        direction: m['direction'] == 'short'
            ? TradeDirection.short
            : TradeDirection.long,
        score: (m['score'] as num).toInt(),
        confidence: (m['confidence'] as num).toInt(),
        entry: (m['entry'] as num).toDouble(),
        entryLow: (m['entryLow'] as num).toDouble(),
        entryHigh: (m['entryHigh'] as num).toDouble(),
        stop: (m['stop'] as num).toDouble(),
        tp1: (m['tp1'] as num).toDouble(),
        tp2: (m['tp2'] as num).toDouble(),
        risk: (m['risk'] as num).toDouble(),
        rr1: (m['rr1'] as num).toDouble(),
        rr2: (m['rr2'] as num).toDouble(),
        validUntil:
            DateTime.tryParse(m['validUntil'] as String? ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
        rationale: [for (final r in (m['rationale'] as List? ?? [])) '$r'],
      );
}

/// Turns a high-conviction Gold Master Score into an entry / stop /
/// take-profit plan. Returns null unless the score clears the bullish or
/// bearish conviction threshold — no signal in the neutral middle.
class TradePlanEngine {
  TradePlanEngine._();

  /// XAUUSD is quoted to $0.01 but conventionally moves in $0.10 "pips", so
  /// 2000 pips = $200 of price.
  static const double pipSize = 0.10;

  /// Day-trading reach limit, in pips. A target further than this from entry
  /// will not realistically be hit inside a session, so a sub-hour setup that
  /// needs one is not a day trade — the plan is held to a closer target
  /// instead. Example: entry 4020 with a stop at 4000 targets at most 4220.
  static const double intradayMaxTpPips = 2000;

  /// Hard ceiling on risk, in pips: the plan never stakes more than 500 pips
  /// ($50) between entry and stop, on any timeframe. Applied *after* the ATR
  /// clamps so it always wins — a volatile session cannot widen the stop
  /// beyond what the account is willing to lose.
  static const double maxStopPips = 500;

  /// [maxStopPips] in price.
  static const double maxStopDistance = maxStopPips * pipSize;

  /// Conviction gate: long above 80, short below 20.
  ///
  /// Briefly 85/15 in v1.1.4, which starved the app of signals for no real
  /// gain in quality — and disagreed with [TradePlan.isHighConviction], which
  /// has always defined high conviction as 80/20. Safety comes from the risk
  /// controls (stop ceiling, ATR reach, news blackout, trailing stop), not
  /// from refusing to look at the market.
  static const int defaultBullishThreshold = 80;
  static const int defaultBearishThreshold = 20;

  /// TP1 must sit at least this many risk multiples beyond entry, so a plan
  /// never risks more than it aims to make, and the target is never so close
  /// that it is not worth taking.
  static const double minRewardRisk = 1.0;

  /// How far price can plausibly travel in the trade's favour before the plan
  /// goes stale, in ATR multiples. TP1 is the **furthest** key level inside
  /// this reach: nearer targets leave money on the table, further ones are
  /// not realistically hit. ATR is used rather than a fixed distance because
  /// what counts as reachable depends entirely on how much gold is moving.
  static const double reachAtrMultiple = 2.0;

  /// How far the stop trails behind the best price, in risk multiples
  /// ([TradeSignal.trailDistance]). 1.5R rather than 1R: the trail is a
  /// safety net, not the intended exit, and a 1R trail closes trades that
  /// would otherwise have reached target.
  static const double trailRiskMultiple = 1.5;

  /// Timeframes treated as day trades and held to [intradayMaxTpPips].
  /// H1 is included as of v1.1.4 — it is the timeframe the Trade Plan screen
  /// and the notification scout actually analyse, so leaving it out meant the
  /// cap changed nothing about the signals you receive. H4/D1/W1 stay exempt.
  static const Set<String> intradayTimeframes = {
    'M1',
    'M5',
    'M15',
    'M30',
    'H1',
  };

  /// Maximum take-profit distance in price for [timeframe], or null when the
  /// timeframe is uncapped.
  static double? maxTpDistanceFor(String? timeframe) =>
      timeframe != null && intradayTimeframes.contains(timeframe)
          ? intradayMaxTpPips * pipSize
          : null;

  static TradePlan? generate({
    required GoldMasterAnalysis analysis,
    required List<Candle> candles,
    required KeyLevelsResult levels,
    int bullishThreshold = defaultBullishThreshold,
    int bearishThreshold = defaultBearishThreshold,
    DateTime? now,

    /// Timeframe the plan is for. Sub-hour timeframes cap the take-profit at
    /// [intradayMaxTpPips]; H1+ (and null) do not.
    String? timeframe,

    /// Explicit cap in price, overriding [timeframe]. Mainly for tests.
    double? maxTpDistance,
  }) {
    if (candles.isEmpty) return null;
    final long = analysis.score >= bullishThreshold;
    final short = analysis.score <= bearishThreshold;
    if (!long && !short) return null;
    return _build(
        analysis: analysis,
        candles: candles,
        levels: levels,
        long: long,
        now: now,
        maxTpDistance: maxTpDistance ?? maxTpDistanceFor(timeframe));
  }

  static TradePlan _build({
    required GoldMasterAnalysis analysis,
    required List<Candle> candles,
    required KeyLevelsResult levels,
    required bool long,
    DateTime? now,
    double? maxTpDistance,
  }) {
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
      // Absolute risk ceiling, last so it beats the ATR clamps above.
      if (entry - stop > maxStopDistance) stop = entry - maxStopDistance;
      final risk = entry - stop;
      final resistances = <double>[
        levels.dailyHigh,
        levels.weekHigh,
        levels.allTimeHigh,
        if (levels.prevDayHigh != null) levels.prevDayHigh!,
        if (levels.prevWeekHigh != null) levels.prevWeekHigh!,
      ]..sort();
      // Two different ceilings. The hard cap is the day-trade reach limit;
      // the ATR reach is how far price can plausibly travel before the plan
      // goes stale. The target is the furthest level inside *both*.
      final capCeiling =
          maxTpDistance == null ? double.infinity : entry + maxTpDistance;
      final tpCeiling =
          math.min(capCeiling, entry + reachAtrMultiple * atr);
      final floorPrice = entry + minRewardRisk * risk;

      final inReach = resistances
          .where((r) => r >= floorPrice && r <= tpCeiling)
          .toList();
      // `.last` — the furthest reachable level, not the nearest. A nearer
      // target leaves money on the table; a further one is not realistically
      // hit. With no level in reach, aim at the edge of the reach itself,
      // never closer than the 1R floor.
      var tp1 = inReach.isNotEmpty
          ? inReach.last
          : math.max(floorPrice, tpCeiling);
      tp1 = math.min(tp1, capCeiling);

      // TP2 is an untracked runner: the next level beyond the target, still
      // inside the hard cap.
      final beyond =
          resistances.where((r) => r > tp1 && r <= capCeiling).toList();
      var tp2 = beyond.isNotEmpty
          ? beyond.first
          : math.min(capCeiling, tp1 + risk);
      if (tp2 < tp1) tp2 = tp1;
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
    // Mirror of the long risk ceiling.
    if (stop - entry > maxStopDistance) stop = entry + maxStopDistance;
    final risk = stop - entry;
    final supports = <double>[
      levels.dailyLow,
      levels.weekLow,
      if (levels.prevDayLow != null) levels.prevDayLow!,
      if (levels.prevWeekLow != null) levels.prevWeekLow!,
    ]..sort((a, b) => b.compareTo(a)); // descending
    // Mirror of the long logic.
    final capFloor =
        maxTpDistance == null ? double.negativeInfinity : entry - maxTpDistance;
    final tpFloor = math.max(capFloor, entry - reachAtrMultiple * atr);
    final ceilingPrice = entry - minRewardRisk * risk;

    // `supports` is sorted descending, so `.last` is again the furthest.
    final inReach = supports
        .where((s) => s <= ceilingPrice && s >= tpFloor)
        .toList();
    var tp1 = inReach.isNotEmpty
        ? inReach.last
        : math.min(ceilingPrice, tpFloor);
    tp1 = math.max(tp1, capFloor);

    final beyond =
        supports.where((s) => s < tp1 && s >= capFloor).toList();
    var tp2 = beyond.isNotEmpty
        ? beyond.first
        : math.max(capFloor, tp1 - risk);
    if (tp2 > tp1) tp2 = tp1;
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
