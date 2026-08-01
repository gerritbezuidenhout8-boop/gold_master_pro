import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/services/spot_gold_data.dart';

void main() {
  group('candlesFromYahooChart', () {
    test('parses timestamps and OHLCV, skipping null buckets', () {
      const body = '{"chart":{"result":[{"timestamp":[1784700000,1784703600,'
          '1784707200],"indicators":{"quote":[{"open":[4100.0,null,4110.0],'
          '"high":[4105.0,null,4118.5],"low":[4095.0,null,4108.0],'
          '"close":[4102.5,null,4115.0],"volume":[120,null,90]}]}}],'
          '"error":null}}';
      final candles = candlesFromYahooChart(body);
      expect(candles, hasLength(2)); // null bucket dropped
      expect(candles.first.time.isUtc, isTrue);
      expect(candles.first.time.millisecondsSinceEpoch, 1784700000 * 1000);
      expect(candles.first.open, 4100.0);
      expect(candles.last.close, 4115.0);
      expect(candles.last.high, 4118.5);
      expect(candles.last.volume, 90);
    });

    test('returns empty on error payloads', () {
      expect(
          candlesFromYahooChart(
              '{"chart":{"result":null,"error":{"code":"Not Found"}}}'),
          isEmpty);
      expect(candlesFromYahooChart('{}'), isEmpty);
    });
  });

  group('aggregateCandles', () {
    test('combines H1 candles into H4 buckets on UTC boundaries', () {
      final h1 = [
        for (var i = 0; i < 8; i++)
          Candle(
            time: DateTime.utc(2026, 7, 21, i),
            open: 100.0 + i,
            high: 110.0 + i,
            low: 90.0 + i,
            close: 105.0 + i,
            volume: 10,
          ),
      ];
      final h4 = aggregateCandles(h1, const Duration(hours: 4));
      expect(h4, hasLength(2));
      expect(h4.first.time, DateTime.utc(2026, 7, 21, 0));
      expect(h4.first.open, 100.0); // first H1 open
      expect(h4.first.close, 108.0); // last H1 close in bucket (i=3)
      expect(h4.first.high, 113.0); // max high (i=3)
      expect(h4.first.low, 90.0); // min low (i=0)
      expect(h4.first.volume, 40);
      expect(h4.last.time, DateTime.utc(2026, 7, 21, 4));
      expect(h4.last.close, 112.0);
    });

    test('handles partial buckets and empty input', () {
      expect(aggregateCandles(const [], const Duration(hours: 4)), isEmpty);
      final h1 = [
        Candle(
            time: DateTime.utc(2026, 7, 21, 5),
            open: 1,
            high: 2,
            low: 0.5,
            close: 1.5),
      ];
      final h4 = aggregateCandles(h1, const Duration(hours: 4));
      expect(h4, hasLength(1));
      expect(h4.first.time, DateTime.utc(2026, 7, 21, 4));
    });
  });

  group('anchorCandleToSpot', () {
    // The regression: candles came from one vendor and the ticker from
    // another, with a frozen offset between them, so the forming bar flipped
    // between two price levels and painted red candles on green moves.
    Candle proxyBar({required double open, required double close}) => Candle(
          time: DateTime.utc(2026, 7, 21, 9),
          open: open,
          high: (open > close ? open : close) + 2,
          low: (open < close ? open : close) - 2,
          close: close,
          volume: 7,
        );

    test('puts the close exactly on spot', () {
      final anchored =
          anchorCandleToSpot(proxyBar(open: 4100, close: 4104), 4285.5, 0);
      expect(anchored.close, closeTo(4285.5, 1e-9));
    });

    test('preserves the bar shape, so a green proxy move stays green', () {
      final raw = proxyBar(open: 4100, close: 4104); // up 4
      final anchored = anchorCandleToSpot(raw, 4285.5, 0);

      expect(anchored.close, greaterThan(anchored.open), reason: 'still green');
      expect(anchored.close - anchored.open, closeTo(4, 1e-9));
      expect(anchored.high - anchored.low, closeTo(raw.high - raw.low, 1e-9));
      expect(anchored.time, raw.time);
      expect(anchored.volume, raw.volume);
    });

    test('a falling proxy bar stays red after anchoring', () {
      final anchored =
          anchorCandleToSpot(proxyBar(open: 4104, close: 4100), 4285.5, 0);
      expect(anchored.close, lessThan(anchored.open));
      expect(anchored.close, closeTo(4285.5, 1e-9));
    });

    test('anchoring is idempotent — re-anchoring at the same spot is a no-op',
        () {
      final once =
          anchorCandleToSpot(proxyBar(open: 4100, close: 4104), 4285.5, 0);
      final twice = anchorCandleToSpot(once, 4285.5, 0);
      expect(twice.open, closeTo(once.open, 1e-9));
      expect(twice.close, closeTo(once.close, 1e-9));
    });

    test('falls back to the series offset before the first quote', () {
      final raw = proxyBar(open: 4100, close: 4104);
      final anchored = anchorCandleToSpot(raw, null, 180.0);
      expect(anchored.close, closeTo(4284.0, 1e-9));
      expect(anchored.open, closeTo(4280.0, 1e-9));
    });
  });

  group('quoteFromSwissquote', () {
    test('takes the mid of the first spread profile', () {
      const body = '[{"topo":{"platform":"X"},"spreadProfilePrices":'
          '[{"spreadProfile":"premium","bid":4113.946,"ask":4114.604}],'
          '"ts":1784703772687}]';
      final q = quoteFromSwissquote(body)!;
      expect(q.price, closeTo((4113.946 + 4114.604) / 2, 1e-9));
      expect(q.bid, 4113.946);
      expect(q.ask, 4114.604);
      expect(q.spread, closeTo(0.658, 1e-9));
      expect(q.time.millisecondsSinceEpoch, 1784703772687);
      expect(q.source, contains('Swissquote'));
    });

    test('returns null on malformed payloads', () {
      expect(quoteFromSwissquote('[]'), isNull);
      expect(quoteFromSwissquote('{}'), isNull);
      expect(quoteFromSwissquote('[{"spreadProfilePrices":[]}]'), isNull);
    });
  });
}
