import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/macd.dart';

void main() {
  group('Macd.compute', () {
    test('warm-up: MACD null until the slow EMA is defined', () {
      final closes = [for (var i = 0; i < 60; i++) i.toDouble()];
      final r = Macd.compute(closes);
      // slow=26 → first MACD at index 25.
      expect(r.macd.sublist(0, 25).every((v) => v == null), isTrue);
      expect(r.macd[25], isNotNull);
    });

    test('signal lags the MACD line', () {
      final closes = [for (var i = 0; i < 80; i++) i.toDouble()];
      final r = Macd.compute(closes);
      final firstMacd = r.macd.indexWhere((v) => v != null);
      final firstSignal = r.signal.indexWhere((v) => v != null);
      expect(firstSignal, greaterThan(firstMacd));
    });

    test('an accelerating uptrend is bullish (MACD line above signal)', () {
      // Accelerating (not linear) rise keeps the MACD line above its
      // lagging signal; a steady ramp would let signal catch up to equal.
      final closes = [for (var i = 0; i < 80; i++) (i * i).toDouble()];
      final r = Macd.compute(closes);
      expect(r.latestMacd, greaterThan(0));
      expect(r.isBullish, isTrue);
    });

    test('a sustained downtrend is bearish', () {
      final closes = [for (var i = 80; i > 0; i--) i.toDouble()];
      final r = Macd.compute(closes);
      expect(r.latestMacd, lessThan(0));
      expect(r.isBullish, isFalse);
    });

    test('histogram equals MACD minus signal at each defined bar', () {
      final closes = [
        for (var i = 0; i < 90; i++) 100 + 5 * (i % 6) - 2 * (i % 4).toDouble()
      ];
      final r = Macd.compute(closes);
      for (var i = 0; i < closes.length; i++) {
        final h = r.histogram[i];
        if (h == null) continue;
        expect(h, closeTo(r.macd[i]! - r.signal[i]!, 1e-9));
      }
    });

    test('rejects bad periods', () {
      expect(() => Macd.compute([1, 2, 3], fast: 0), throwsArgumentError);
      expect(() => Macd.compute([1, 2, 3], fast: 26, slow: 12),
          throwsArgumentError);
    });
  });
}
