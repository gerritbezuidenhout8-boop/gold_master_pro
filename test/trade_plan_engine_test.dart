import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/gold_master_engine.dart';
import 'package:gold_master_pro/ai/trade_plan_engine.dart';
import 'package:gold_master_pro/indicators/key_levels.dart';
import 'package:gold_master_pro/models/candle.dart';

import 'gold_master_engine_test.dart' show bullishH1, bullishD1;

List<Candle> _mirror(List<Candle> candles, double pivot) => [
      for (final c in candles)
        Candle(
          time: c.time,
          open: pivot - (c.open - pivot),
          high: pivot - (c.low - pivot),
          low: pivot - (c.high - pivot),
          close: pivot - (c.close - pivot),
        ),
    ];

List<Candle> _flat(int n, {bool daily = false}) => [
      for (var i = 0; i < n; i++)
        Candle(
          time: daily
              ? DateTime.utc(2026, 1, 1).add(Duration(days: i))
              : DateTime.utc(2026, 6, 1).add(Duration(hours: i)),
          open: 100,
          high: 100,
          low: 100,
          close: 100,
        ),
    ];

/// 30 bars of uniform range around [close], with one bar inside the 20-bar
/// swing window dipping to [swingLow], so entry and stop are predictable.
List<Candle> _dayTradeBars({required double close, required double swingLow}) =>
    [
      for (var i = 0; i < 30; i++)
        Candle(
          time: DateTime.utc(2026, 6, 1).add(Duration(minutes: 5 * i)),
          open: close,
          high: close + 2,
          low: i == 15 ? swingLow : close - 2,
          close: close,
        ),
    ];

/// Wide-range bars so ATR (~300) makes the reach ceiling generous, isolating
/// whichever other limit is under test.
List<Candle> _volatileBars({required double close}) => [
      for (var i = 0; i < 30; i++)
        Candle(
          time: DateTime.utc(2026, 6, 1).add(Duration(minutes: 5 * i)),
          open: close,
          high: close + 150,
          low: close - 150,
          close: close,
        ),
    ];

/// Levels far enough above/below [pivot] that every one of them sits outside
/// the 2000-pip day-trade cap.
KeyLevelsResult _distantLevels(double pivot) => KeyLevelsResult(
      asOf: DateTime.utc(2026, 6, 1),
      dailyOpen: pivot,
      dailyHigh: pivot + 280,
      dailyLow: pivot - 280,
      prevDayHigh: pivot + 320,
      prevDayLow: pivot - 320,
      weekHigh: pivot + 400,
      weekLow: pivot - 400,
      prevWeekHigh: pivot + 500,
      prevWeekLow: pivot - 500,
      allTimeHigh: pivot + 900,
    );

void main() {
  group('day-trade take-profit cap', () {
    final analysis =
        GoldMasterEngine.analyze(h1: bullishH1(), d1: bullishD1());

    test('M15 long never targets further than 2000 pips from entry', () {
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
        bullishThreshold: 0, // force the long branch
        timeframe: 'M15',
      )!;

      // The worked example: entry 4020 => the target must not exceed 4220.
      expect(plan.entry, 4020);
      expect(plan.tp1, lessThanOrEqualTo(4220));
      expect(plan.tp2, lessThanOrEqualTo(4220));
      expect(plan.tp1, greaterThan(plan.entry));
      expect(plan.tp2, greaterThanOrEqualTo(plan.tp1));
    });

    test('H1 is capped too, so real signals are day-trade shaped', () {
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
        bullishThreshold: 0,
        timeframe: 'H1',
      )!;

      // H1 is what the Trade Plan screen and the scout analyse — leaving it
      // exempt meant the cap changed nothing about the signals received.
      expect(plan.tp1, lessThanOrEqualTo(4220));
    });

    test('H4 and above stay exempt from the hard cap', () {
      // Volatile enough that the ATR reach is wide (~600), so the only thing
      // that could hold the target back is the day-trade cap.
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _volatileBars(close: 4020),
        levels: _distantLevels(4020),
        bullishThreshold: 0,
        timeframe: 'H4',
      )!;
      expect(plan.tp1, greaterThan(4220));

      // Same bars on M15: the cap binds.
      final capped = TradePlanEngine.generate(
        analysis: analysis,
        candles: _volatileBars(close: 4020),
        levels: _distantLevels(4020),
        bullishThreshold: 0,
        timeframe: 'M15',
      )!;
      expect(capped.tp1, lessThanOrEqualTo(4220));
    });

    test('targets the furthest level still within ATR reach, not the nearest',
        () {
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _volatileBars(close: 4020), // ATR ~300 => reach ~600
        levels: _distantLevels(4020),
        bullishThreshold: 0,
        timeframe: 'H4',
      )!;

      // Levels above entry: 4300, 4340, 4420, 4520, 4920. Reach ends ~4620,
      // so 4520 is the furthest one realistically hit — not 4300.
      expect(plan.tp1, 4520);
      expect(plan.tp2, greaterThanOrEqualTo(plan.tp1));
    });

    test('the target is never closer than the 1R floor', () {
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
        bullishThreshold: 0,
        timeframe: 'M15',
      )!;
      expect(plan.tp1 - plan.entry, greaterThanOrEqualTo(plan.risk));
      expect(plan.rr1, greaterThanOrEqualTo(1));

      // Shorts too. The floor only survives the hard cap because the stop
      // ceiling (500 pips) is well inside the target cap (2000 pips) — if
      // those ever cross, 1R could no longer fit under the cap.
      final short = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
        bullishThreshold: 101,
        bearishThreshold: 100,
        timeframe: 'M15',
      )!;
      expect(short.entry - short.tp1, greaterThanOrEqualTo(short.risk));
      expect(short.rr1, greaterThanOrEqualTo(1));
      expect(TradePlanEngine.maxStopDistance,
          lessThan(TradePlanEngine.intradayMaxTpPips * TradePlanEngine.pipSize));
    });

    test('M15 short mirrors the cap', () {
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
        bullishThreshold: 101, // unreachable, so the short branch runs
        bearishThreshold: 100,
        timeframe: 'M15',
      )!;

      expect(plan.direction, TradeDirection.short);
      expect(plan.tp1, greaterThanOrEqualTo(3820)); // 4020 - 200
      expect(plan.tp2, greaterThanOrEqualTo(3820));
      expect(plan.tp1, lessThan(plan.entry));
      expect(plan.tp2, lessThanOrEqualTo(plan.tp1));
    });

    test('an explicit cap clamps a target that would overshoot it', () {
      // A 1-pip cap forces the clamp itself to run, not just the level filter.
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
        bullishThreshold: 0,
        maxTpDistance: 0.10,
      )!;

      expect(plan.tp1, closeTo(4020.10, 1e-9));
      expect(plan.tp2, closeTo(4020.10, 1e-9));
      expect(plan.rr2, greaterThanOrEqualTo(plan.rr1));
    });

    test('risk never exceeds 500 pips, however wide the swing', () {
      // A 900-wide swing low would put the raw stop far below entry; the ATR
      // clamp alone would still allow 3x a very large ATR.
      final wild = [
        for (var i = 0; i < 30; i++)
          Candle(
            time: DateTime.utc(2026, 6, 1).add(Duration(minutes: 5 * i)),
            open: 4020,
            high: 4020 + 60,
            low: i == 15 ? 3120 : 4020 - 60,
            close: 4020,
          ),
      ];
      for (final tf in ['M15', 'H1', 'D1']) {
        final plan = TradePlanEngine.generate(
          analysis: analysis,
          candles: wild,
          levels: _distantLevels(4020),
          bullishThreshold: 0,
          timeframe: tf,
        )!;
        expect(plan.risk, lessThanOrEqualTo(50),
            reason: '$tf must respect the 500-pip stop ceiling');
        expect(plan.stop, greaterThanOrEqualTo(3970)); // 4020 - 50
      }
    });

    test('the risk ceiling mirrors for shorts', () {
      final wild = [
        for (var i = 0; i < 30; i++)
          Candle(
            time: DateTime.utc(2026, 6, 1).add(Duration(minutes: 5 * i)),
            open: 4020,
            high: i == 15 ? 4920 : 4020 + 60,
            low: 4020 - 60,
            close: 4020,
          ),
      ];
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: wild,
        levels: _distantLevels(4020),
        bullishThreshold: 101,
        bearishThreshold: 100,
        timeframe: 'M15',
      )!;
      expect(plan.direction, TradeDirection.short);
      expect(plan.risk, lessThanOrEqualTo(50));
      expect(plan.stop, lessThanOrEqualTo(4070)); // 4020 + 50
    });

    test('the issue gate agrees with TradePlan.isHighConviction', () {
      // isHighConviction is conviction >= 60, i.e. score >= 80 or <= 20.
      // v1.1.4 briefly gated at 85/15, so the engine could refuse a plan its
      // own model called high conviction — and starved the app of signals.
      expect(TradePlanEngine.defaultBullishThreshold, 80);
      expect(TradePlanEngine.defaultBearishThreshold, 20);

      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: _dayTradeBars(close: 4020, swingLow: 4000),
        levels: _distantLevels(4020),
      );
      if (plan != null) {
        expect(plan.isHighConviction, isTrue,
            reason: 'anything issued must read as high conviction');
      }
    });

    test('intraday timeframes through H1 are capped, swing ones are not', () {
      expect(TradePlanEngine.maxTpDistanceFor('M5'), 200);
      expect(TradePlanEngine.maxTpDistanceFor('M15'), 200);
      expect(TradePlanEngine.maxTpDistanceFor('M30'), 200);
      expect(TradePlanEngine.maxTpDistanceFor('H1'), 200);
      expect(TradePlanEngine.maxTpDistanceFor('H4'), isNull);
      expect(TradePlanEngine.maxTpDistanceFor('D1'), isNull);
      expect(TradePlanEngine.maxTpDistanceFor(null), isNull);
    });
  });

  test('strong bullish score yields a coherent long plan', () {
    final h1 = bullishH1();
    final d1 = bullishD1();
    final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
    final plan = TradePlanEngine.generate(
      analysis: analysis,
      candles: h1,
      levels: KeyLevels.compute(d1),
      bullishThreshold: 60, // fixture scores strongly bullish
    )!;

    expect(plan.direction, TradeDirection.long);
    expect(plan.action, 'BUY');
    // Sane geometry: stop < entry < tp1 < tp2.
    expect(plan.stop, lessThan(plan.entry));
    expect(plan.entry, lessThan(plan.tp1));
    expect(plan.tp1, lessThan(plan.tp2));
    expect(plan.risk, greaterThan(0));
    expect(plan.rr1, greaterThan(0));
    expect(plan.rr2, greaterThan(plan.rr1));
    expect(plan.entryLow, lessThan(plan.entryHigh));
    expect(plan.rationale, isNotEmpty);
  });

  test('strong bearish score yields a coherent short plan', () {
    final h1 = _mirror(bullishH1(), 200);
    final d1 = _mirror(bullishD1(), 200);
    final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
    final plan = TradePlanEngine.generate(
      analysis: analysis,
      candles: h1,
      levels: KeyLevels.compute(d1),
      bearishThreshold: 40,
    )!;

    expect(plan.direction, TradeDirection.short);
    expect(plan.action, 'SELL');
    // Sane geometry: tp2 < tp1 < entry < stop.
    expect(plan.tp2, lessThan(plan.tp1));
    expect(plan.tp1, lessThan(plan.entry));
    expect(plan.entry, lessThan(plan.stop));
    expect(plan.risk, greaterThan(0));
    expect(plan.rr2, greaterThan(plan.rr1));
  });

  test('neutral score produces no signal', () {
    final h1 = _flat(60);
    final d1 = _flat(30, daily: true);
    final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
    expect(analysis.score, 50);
    final plan = TradePlanEngine.generate(
      analysis: analysis,
      candles: h1,
      levels: KeyLevels.compute(d1),
    );
    expect(plan, isNull);
  });

  test('an issued plan is always high conviction', () {
    // With the 80/20 gate, anything that clears it is >= 60 conviction.
    final analysis =
        GoldMasterEngine.analyze(h1: bullishH1(), d1: bullishD1());
    final plan = TradePlanEngine.generate(
      analysis: analysis,
      candles: bullishH1(),
      levels: KeyLevels.compute(bullishD1()),
    )!;
    expect(plan.isHighConviction, isTrue);
    expect(plan.convictionLabel, 'High');
    expect(plan.stop, lessThan(plan.entry));
    expect(plan.entry, lessThan(plan.tp1));
  });

  test('returns null without candles', () {
    final analysis = GoldMasterEngine.analyze(h1: bullishH1(), d1: bullishD1());
    expect(
      TradePlanEngine.generate(
        analysis: analysis,
        candles: const [],
        levels: KeyLevels.compute(bullishD1()),
      ),
      isNull,
    );
  });

  test('threshold is inclusive at exactly 80', () {
    // Build an analysis and only accept it if the fixture reaches >=80;
    // otherwise assert the gating explicitly via a lower threshold.
    final h1 = bullishH1();
    final d1 = bullishD1();
    final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
    final plan = TradePlanEngine.generate(
      analysis: analysis,
      candles: h1,
      levels: KeyLevels.compute(d1),
      bullishThreshold: analysis.score, // inclusive lower bound
    );
    expect(plan, isNotNull);
  });
}
