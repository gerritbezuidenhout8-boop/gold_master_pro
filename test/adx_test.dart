import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/adx.dart';
import 'package:gold_master_pro/models/candle.dart';

Candle _c(int i, double high, double low, double close) => Candle(
      time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
      open: close,
      high: high,
      low: low,
      close: close,
    );

List<Candle> _trend(int n, {required bool up}) => [
      for (var i = 0; i < n; i++)
        () {
          final c = up ? i.toDouble() : (n - i).toDouble();
          return _c(i, c + 0.5, c - 0.5, c);
        }()
    ];

void main() {
  group('Adx', () {
    test('a strong uptrend: high ADX, +DI dominant', () {
      final r = Adx.latest(_trend(80, up: true));
      expect(r, isNotNull);
      expect(r!.adx, greaterThan(25));
      expect(r.isTrending, isTrue);
      expect(r.plusDI, greaterThan(r.minusDI));
      expect(r.isBullish, isTrue);
    });

    test('a strong downtrend: high ADX, −DI dominant', () {
      final r = Adx.latest(_trend(80, up: false));
      expect(r, isNotNull);
      expect(r!.adx, greaterThan(25));
      expect(r.minusDI, greaterThan(r.plusDI));
      expect(r.isBullish, isFalse);
    });

    test('a choppy market is weakly directional (low ADX)', () {
      final candles = [
        for (var i = 0; i < 120; i++)
          () {
            final c = 100 + (i.isEven ? 1.0 : -1.0);
            return _c(i, c + 0.5, c - 0.5, c);
          }()
      ];
      final r = Adx.latest(candles);
      expect(r, isNotNull);
      expect(r!.adx, lessThan(25));
    });

    test('all ADX values stay within 0..100', () {
      for (final r in Adx.series(_trend(120, up: true))) {
        expect(r.adx, inInclusiveRange(0, 100));
        expect(r.plusDI, inInclusiveRange(0, 100));
        expect(r.minusDI, inInclusiveRange(0, 100));
      }
    });

    test('too little data returns null / empty', () {
      expect(Adx.latest([_c(0, 1, 0, 0.5), _c(1, 2, 1, 1.5)]), isNull);
      expect(Adx.series([_c(0, 1, 0, 0.5)]), isEmpty);
    });

    test('rejects non-positive period', () {
      expect(() => Adx.series(_trend(40, up: true), period: 0),
          throwsArgumentError);
    });
  });
}
