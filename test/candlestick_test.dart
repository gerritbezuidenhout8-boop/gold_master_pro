import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/candlestick_ai.dart';
import 'package:gold_master_pro/models/candle.dart';

int _i = 0;
Candle _c(double o, double h, double l, double c) => Candle(
      time: DateTime.utc(2026, 1, 1).add(Duration(hours: _i++)),
      open: o,
      high: h,
      low: l,
      close: c,
    );

void main() {
  List<CandlePattern> detect(List<Candle> candles) =>
      CandlestickDetector.detect(candles);

  test('doji: tiny body, and it is not also a hammer', () {
    final out = detect([_c(100, 105, 95, 100.5)]);
    expect(out, contains(CandlePattern.doji));
    expect(out, isNot(contains(CandlePattern.hammer)));
  });

  test('marubozu: body dominates the range', () {
    expect(detect([_c(100, 110.2, 99.9, 110)]),
        contains(CandlePattern.marubozu));
  });

  test('hammer: long lower wick, tiny upper wick', () {
    final out = detect([_c(103.5, 105.5, 95, 105.5)]);
    expect(out, contains(CandlePattern.hammer));
    expect(out, isNot(contains(CandlePattern.shootingStar)));
  });

  test('shooting star: long upper wick, tiny lower wick', () {
    expect(detect([_c(96.5, 105, 94.4, 94.5)]),
        contains(CandlePattern.shootingStar));
  });

  test('bullish engulfing', () {
    expect(
        detect([_c(105, 105.5, 99.5, 100), _c(99.5, 106.5, 99, 106)]),
        contains(CandlePattern.bullishEngulfing));
  });

  test('bearish engulfing', () {
    expect(
        detect([_c(100, 105.5, 99.5, 105), _c(105.5, 106, 99, 99.5)]),
        contains(CandlePattern.bearishEngulfing));
  });

  test('engulfing requires the larger body', () {
    final out =
        detect([_c(105, 105.5, 99.5, 100), _c(101, 104.6, 100.5, 104.5)]);
    expect(out, isNot(contains(CandlePattern.bullishEngulfing)));
    expect(out, contains(CandlePattern.insideBar));
  });

  test('morning star', () {
    expect(
        detect([
          _c(110, 110.5, 99.5, 100),
          _c(99, 100, 98.5, 99.8),
          _c(100, 106.5, 99.5, 106),
        ]),
        contains(CandlePattern.morningStar));
  });

  test('evening star', () {
    expect(
        detect([
          _c(100, 110.5, 99.5, 110),
          _c(111, 111.5, 110.2, 110.5),
          _c(110, 110.5, 103, 104),
        ]),
        contains(CandlePattern.eveningStar));
  });

  test('tweezer top', () {
    expect(
        detect([_c(100, 105, 99.5, 104), _c(103.8, 105.2, 100.9, 101)]),
        contains(CandlePattern.tweezerTop));
  });

  test('tweezer bottom', () {
    expect(
        detect([_c(104, 104.5, 95, 100), _c(100.2, 103, 95.1, 102.5)]),
        contains(CandlePattern.tweezerBottom));
  });

  test('three white soldiers', () {
    expect(
        detect([
          _c(100, 104.5, 99.8, 104),
          _c(101, 106.4, 100.8, 106),
          _c(103, 109.3, 102.8, 109),
        ]),
        contains(CandlePattern.threeWhiteSoldiers));
  });

  test('three black crows', () {
    expect(
        detect([
          _c(109, 109.3, 104.5, 105),
          _c(108, 108.2, 102.6, 103),
          _c(106, 106.2, 99.8, 100),
        ]),
        contains(CandlePattern.threeBlackCrows));
  });

  test('inside and outside bars', () {
    expect(detect([_c(100, 110, 100, 108), _c(104, 107, 103, 105)]),
        contains(CandlePattern.insideBar));
    expect(detect([_c(104, 107, 103, 105), _c(103, 108, 102, 107)]),
        contains(CandlePattern.outsideBar));
  });

  test('a plain trending candle matches nothing', () {
    expect(detect([_c(100, 106, 99.5, 105)]), isEmpty);
    expect(detect(const []), isEmpty);
  });

  test('signal direction classification', () {
    expect(CandlePattern.bullishEngulfing.isBullishSignal, isTrue);
    expect(CandlePattern.threeBlackCrows.isBearishSignal, isTrue);
    expect(CandlePattern.doji.isBullishSignal, isFalse);
    expect(CandlePattern.doji.isBearishSignal, isFalse);
    expect(CandlePattern.hammer.label, 'Hammer');
  });
}
