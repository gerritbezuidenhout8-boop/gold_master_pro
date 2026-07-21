import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/services/market_data.dart';

Candle _c(int hour, {double close = 100}) => Candle(
      time: DateTime.utc(2026, 1, 1, hour),
      open: close,
      high: close + 1,
      low: close - 1,
      close: close,
      volume: 1,
    );

void main() {
  test('candleFromKlineEvent parses a kline push', () {
    final msg = {
      'e': 'kline',
      'E': 1784617200123,
      's': 'PAXGUSDT',
      'k': {
        't': 1784617200000,
        'T': 1784620799999,
        'i': '1h',
        'o': '4072.97',
        'c': '4064.74',
        'h': '4073.59',
        'l': '4061.88',
        'v': '154.03',
        'x': false,
      },
    };
    final c = candleFromKlineEvent(msg)!;
    expect(c.time.millisecondsSinceEpoch, 1784617200000);
    expect(c.time.isUtc, isTrue);
    expect(c.open, 4072.97);
    expect(c.close, 4064.74);
    expect(c.high, 4073.59);
    expect(c.low, 4061.88);
    expect(c.volume, 154.03);
    expect(candleFromKlineEvent({'e': 'other'}), isNull);
  });

  test('quoteFromMiniTicker parses last price and event time', () {
    final q = quoteFromMiniTicker(
        {'e': '24hrMiniTicker', 'E': 1784628000000, 'c': '4057.86'})!;
    expect(q.price, 4057.86);
    expect(q.time.millisecondsSinceEpoch, 1784628000000);
    expect(quoteFromMiniTicker({'e': 'x'}), isNull);
  });

  test('quoteFromGoldApi parses the spot response', () {
    final q = quoteFromGoldApi({
      'name': 'Gold',
      'price': 4063.899902,
      'symbol': 'XAU',
      'updatedAt': '2026-07-21T10:10:03Z',
    })!;
    expect(q.price, closeTo(4063.899902, 1e-9));
    expect(q.time, DateTime.utc(2026, 7, 21, 10, 10, 3));
    expect(quoteFromGoldApi({'symbol': 'XAU'}), isNull);
  });

  group('mergeCandle', () {
    test('replaces the forming candle on the same open time', () {
      final merged = mergeCandle([_c(0), _c(1)], _c(1, close: 111));
      expect(merged, hasLength(2));
      expect(merged.last.close, 111);
      expect(merged.first.close, 100);
    });

    test('appends a newer candle and caps the length', () {
      final merged = mergeCandle(
          [for (var h = 0; h < 5; h++) _c(h)], _c(5),
          maxLength: 5);
      expect(merged, hasLength(5));
      expect(merged.first.time, DateTime.utc(2026, 1, 1, 1));
      expect(merged.last.time, DateTime.utc(2026, 1, 1, 5));
    });

    test('ignores stale updates', () {
      final list = [_c(0), _c(1)];
      expect(mergeCandle(list, _c(0, close: 50)), same(list));
    });

    test('starts from an empty list', () {
      expect(mergeCandle(const [], _c(0)), hasLength(1));
    });
  });

  test('unknown timeframes are rejected before any network use', () {
    final live = BinanceMarketData();
    expect(live.fetchCandles('X'), throwsArgumentError);
    expect(() => live.candleStream('X'), throwsArgumentError);
  });
}
