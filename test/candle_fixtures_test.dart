import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/services/candle_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses Binance kline rows', () {
    const sample =
        '[[1700000000000,"2000.5","2010.0","1995.0","2005.25","12.5",1700003599999,"0",10,"0","0","0"]]';
    final candles = candlesFromBinanceKlines(sample);
    expect(candles, hasLength(1));
    final c = candles.single;
    expect(c.time.isUtc, isTrue);
    expect(c.time.millisecondsSinceEpoch, 1700000000000);
    expect(c.open, 2000.5);
    expect(c.high, 2010.0);
    expect(c.low, 1995.0);
    expect(c.close, 2005.25);
    expect(c.volume, 12.5);
  });

  test('bundled H1 fixture loads, is non-empty and chronological', () async {
    final candles = await CandleFixtures.load('H1');
    expect(candles.length, greaterThan(400));
    for (var i = 1; i < candles.length; i++) {
      expect(candles[i].time.isAfter(candles[i - 1].time), isTrue);
    }
  });

  test('unknown timeframe throws', () {
    expect(CandleFixtures.load('X'), throwsArgumentError);
  });
}
