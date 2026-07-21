import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/fibonacci.dart';
import 'package:gold_master_pro/indicators/smma.dart';

void main() {
  group('Smma.compute', () {
    test('warm-up entries are null and the seed is the SMA', () {
      final out = Smma.compute([1, 2, 3, 4, 5], 3);
      expect(out.sublist(0, 2), [null, null]);
      expect(out[2], closeTo(2.0, 1e-9));
    });

    test('recursive smoothing matches hand-computed values', () {
      final out = Smma.compute([1, 2, 3, 4, 5], 3);
      expect(out[3], closeTo(8 / 3, 1e-9)); // (2*2 + 4) / 3
      expect(out[4], closeTo((8 / 3 * 2 + 5) / 3, 1e-9));
    });

    test('series shorter than the period stays all-null', () {
      expect(Smma.compute([1, 2], 3), [null, null]);
    });

    test('rejects a non-positive period', () {
      expect(() => Smma.compute([1], 0), throwsArgumentError);
    });
  });

  group('Fibonacci.retracement', () {
    test('maps the standard ratios across the swing', () {
      final levels = Fibonacci.retracement(swingHigh: 2400, swingLow: 2300);
      expect(levels[0.0], 2400);
      expect(levels[1.0], 2300);
      expect(levels[0.5], 2350);
      expect(levels[0.618]!, closeTo(2338.2, 1e-9));
    });
  });
}
