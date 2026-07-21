import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/fibonacci.dart';
import 'package:gold_master_pro/models/candle.dart';

Candle _c(int i, double high) => Candle(
      time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
      open: high - 1.5,
      high: high,
      low: high - 2,
      close: high - 0.5,
    );

void main() {
  test('up-leg: pivot high detected, absolute low as fallback anchor', () {
    // Rises 100→118, peaks at 120, falls back to 110 — no interior low
    // pivot exists, so the window minimum (first candle) anchors the low.
    final candles = [
      for (var i = 0; i <= 9; i++) _c(i, 100 + 2.0 * i),
      _c(10, 120),
      for (var i = 11; i <= 15; i++) _c(i, 120 - 2.0 * (i - 10)),
    ];
    final r = Fibonacci.auto(candles, pivotStrength: 3);
    expect(r.swingHigh, 120);
    expect(r.swingHighTime, DateTime.utc(2026, 1, 1, 10));
    expect(r.swingLow, 98); // low of the first candle
    expect(r.isUpLeg, isTrue);
    expect(r.levels[0.0], 120);
    expect(r.levels[1.0], 98);
    expect(r.levels[0.5], 109);
    expect(r.levels[0.618], closeTo(120 - 22 * 0.618, 1e-9));
  });

  test('down-leg: pivot low detected, ratios measured up from the low', () {
    final candles = [
      for (var i = 0; i <= 9; i++) _c(i, 130 - 2.0 * i),
      _c(10, 110),
      for (var i = 11; i <= 15; i++) _c(i, 110 + 2.0 * (i - 10)),
    ];
    final r = Fibonacci.auto(candles, pivotStrength: 3);
    expect(r.swingLow, 108); // low of the pivot candle at i=10
    expect(r.swingLowTime, DateTime.utc(2026, 1, 1, 10));
    expect(r.swingHigh, 130); // absolute high fallback (first candle)
    expect(r.isUpLeg, isFalse);
    expect(r.levels[0.0], 108);
    expect(r.levels[1.0], 130);
    expect(r.levels[0.5], 119);
  });

  test('lookback trims old candles out of the window', () {
    final candles = [
      _c(0, 500), // huge spike that must be ignored
      for (var i = 1; i <= 30; i++) _c(i, 100 + i.toDouble()),
    ];
    final r = Fibonacci.auto(candles, pivotStrength: 3, lookback: 20);
    expect(r.swingHigh, lessThan(200));
  });

  test('rejects an empty list', () {
    expect(() => Fibonacci.auto(const []), throwsArgumentError);
  });
}
