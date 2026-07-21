import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/rsi.dart';
import 'package:gold_master_pro/models/candle.dart';

Candle _c(int i, double high, double low, double close) => Candle(
      time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
      open: close,
      high: high,
      low: low,
      close: close,
    );

void main() {
  group('Rsi.compute', () {
    test('warm-up entries are null; first value at index period', () {
      final r = Rsi.compute([for (var i = 0; i < 20; i++) i.toDouble()]);
      expect(r.sublist(0, 14).every((v) => v == null), isTrue);
      expect(r[14], isNotNull);
    });

    test('a pure uptrend is RSI 100, pure downtrend is 0', () {
      final up = Rsi.compute([for (var i = 0; i < 20; i++) i.toDouble()]);
      expect(up[19], closeTo(100, 1e-9));
      final down = Rsi.compute([for (var i = 20; i > 0; i--) i.toDouble()]);
      expect(down[19], closeTo(0, 1e-9));
    });

    test('stays within 0..100 on mixed data', () {
      final closes = [
        for (var i = 0; i < 80; i++)
          100 + 10 * (i % 7) - 5 * (i % 3).toDouble()
      ];
      for (final v in Rsi.compute(closes)) {
        if (v != null) expect(v, inInclusiveRange(0, 100));
      }
    });

    test('rejects non-positive period', () {
      expect(() => Rsi.compute([1, 2, 3], period: 0), throwsArgumentError);
    });
  });

  group('StochRsi.compute', () {
    test('%K and %D stay within 0..100', () {
      final closes = [
        for (var i = 0; i < 120; i++)
          100 + 8 * (i % 5) - 3 * (i % 4).toDouble()
      ];
      final s = StochRsi.compute(closes);
      for (final v in [...s.k, ...s.d]) {
        if (v != null) expect(v, inInclusiveRange(0, 100));
      }
    });

    test('flat RSI (pure trend) yields a defined, bounded StochRSI', () {
      final closes = [for (var i = 0; i < 60; i++) i.toDouble()];
      final s = StochRsi.compute(closes);
      final lastK = s.k.lastWhere((v) => v != null, orElse: () => null);
      expect(lastK, isNotNull);
      expect(lastK!, inInclusiveRange(0, 100));
    });

    test('%D lags %K (needs more warm-up)', () {
      final closes = [
        for (var i = 0; i < 60; i++) 100 + (i % 9).toDouble()
      ];
      final s = StochRsi.compute(closes);
      final firstK = s.k.indexWhere((v) => v != null);
      final firstD = s.d.indexWhere((v) => v != null);
      expect(firstD, greaterThan(firstK));
    });
  });

  group('RsiDivergence.detect', () {
    test('flags a bullish divergence: lower price low, higher RSI low', () {
      // Long steep drop into trough 1 (RSI ~10), a rally, then a shorter
      // decline to a marginally lower low with RSI ~27 — bullish divergence.
      final closes = <double>[];
      for (var i = 0; i < 16; i++) {
        closes.add(100 + (i.isEven ? 1.0 : -1.0)); // seed
      }
      for (var i = 0; i < 14; i++) {
        closes.add(closes.last - 4); // steep decline -> trough 1
      }
      for (var i = 0; i < 10; i++) {
        closes.add(closes.last + 3); // rally
      }
      for (var i = 0; i < 8; i++) {
        closes.add(closes.last - 4); // shorter decline -> lower low, higher RSI
      }
      for (var i = 0; i < 8; i++) {
        closes.add(closes.last + 3); // recover
      }
      final candles = [
        for (var i = 0; i < closes.length; i++)
          _c(i, closes[i] + 0.5, closes[i] - 0.5, closes[i]),
      ];
      final events = RsiDivergence.detect(candles, pivotStrength: 3);
      expect(events.any((e) => e.type == DivergenceType.bullish), isTrue);
      expect(events.every((e) => e.index > 14), isTrue);
    });

    test('a clean uptrend produces no divergence', () {
      final candles = [
        for (var i = 0; i < 60; i++)
          _c(i, i + 1.0, i - 1.0, i.toDouble()),
      ];
      expect(RsiDivergence.detect(candles), isEmpty);
    });

    test('too little data returns empty', () {
      expect(RsiDivergence.detect([_c(0, 1, 0, 0.5)]), isEmpty);
    });
  });
}
