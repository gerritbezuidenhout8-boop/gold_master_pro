import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/gold_master_engine.dart';
import 'package:gold_master_pro/models/candle.dart';

List<Candle> bullishH1() {
  final candles = [
    for (var i = 0; i < 258; i++)
      Candle(
        time: DateTime.utc(2026, 7, 1).add(Duration(hours: i)),
        open: 100 + 0.5 * i - 0.3,
        high: 100 + 0.5 * i + 0.2,
        low: 100 + 0.5 * i - 0.5,
        close: 100 + 0.5 * i,
      ),
  ];
  // Finish with a bearish candle engulfed by a bullish one.
  return [
    ...candles,
    Candle(
      time: DateTime.utc(2026, 7, 1).add(const Duration(hours: 258)),
      open: 229,
      high: 229.1,
      low: 228.3,
      close: 228.4,
    ),
    Candle(
      time: DateTime.utc(2026, 7, 1).add(const Duration(hours: 259)),
      open: 228.3,
      high: 229.7,
      low: 228.2,
      close: 229.6,
    ),
  ];
}

List<Candle> bullishD1() => [
      for (var i = 0; i < 300; i++)
        Candle(
          time: DateTime.utc(2025, 9, 1).add(Duration(days: i)),
          open: 80 + 0.5 * i - 0.3,
          high: 80 + 0.5 * i + 0.2,
          low: 80 + 0.5 * i - 0.5,
          close: 80 + 0.5 * i,
        ),
    ];

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

void main() {
  test('strongly rising market scores bullish with aligned components', () {
    final a = GoldMasterEngine.analyze(h1: bullishH1(), d1: bullishD1());
    expect(a.score, greaterThan(60));
    expect(a.bias, MarketBias.bullish);
    expect(a.components, hasLength(5));
    expect(a.topReasons, hasLength(3));
    for (final c in a.components) {
      expect(c.signal, inInclusiveRange(-1, 1));
    }
    expect(a.strategyMatch, contains('of 5'));
    expect(a.story, contains('bullish'));
    expect(a.story, contains('229.60'));
    expect(a.confidence, greaterThan(60));
  });

  test('mirrored falling market scores bearish', () {
    final a = GoldMasterEngine.analyze(
      h1: _mirror(bullishH1(), 200),
      d1: _mirror(bullishD1(), 200),
    );
    expect(a.score, lessThan(40));
    expect(a.bias, MarketBias.bearish);
    expect(a.story, contains('bearish'));
  });

  test('flat market is neutral with zero clarity', () {
    final a = GoldMasterEngine.analyze(
      h1: _flat(60),
      d1: _flat(30, daily: true),
    );
    expect(a.score, 50);
    expect(a.bias, MarketBias.neutral);
    expect(a.clarity, 0);
  });

  test('is deterministic for identical input', () {
    final now = DateTime.utc(2026, 7, 21, 12);
    final a = GoldMasterEngine.analyze(
        h1: bullishH1(), d1: bullishD1(), now: now);
    final b = GoldMasterEngine.analyze(
        h1: bullishH1(), d1: bullishD1(), now: now);
    expect(a.score, b.score);
    expect(a.story, b.story);
    expect(a.topReasons, b.topReasons);
  });

  test('rejects empty inputs', () {
    expect(() => GoldMasterEngine.analyze(h1: const [], d1: _flat(10)),
        throwsArgumentError);
    expect(() => GoldMasterEngine.analyze(h1: _flat(10), d1: const []),
        throwsArgumentError);
  });
}
