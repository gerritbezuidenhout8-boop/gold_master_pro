import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/services/market_data.dart';

Candle _c(DateTime t, {double open = 100, double high = 101, double low = 99, double close = 100}) =>
    Candle(time: t, open: open, high: high, low: low, close: close);

void main() {
  group('floorToTimeframe', () {
    test('snaps minutes and hours to the bar boundary', () {
      final t = DateTime.utc(2026, 8, 11, 9, 23, 47);
      expect(floorToTimeframe(t, 'M5'), DateTime.utc(2026, 8, 11, 9, 20));
      expect(floorToTimeframe(t, 'M15'), DateTime.utc(2026, 8, 11, 9, 15));
      expect(floorToTimeframe(t, 'M30'), DateTime.utc(2026, 8, 11, 9, 0));
      expect(floorToTimeframe(t, 'H1'), DateTime.utc(2026, 8, 11, 9, 0));
      expect(floorToTimeframe(t, 'H4'), DateTime.utc(2026, 8, 11, 8, 0));
      expect(floorToTimeframe(t, 'D1'), DateTime.utc(2026, 8, 11));
    });

    test('weeks start Monday 00:00 UTC, matching KeyLevels', () {
      // 2026-08-11 is a Tuesday.
      expect(floorToTimeframe(DateTime.utc(2026, 8, 11, 9), 'W1'),
          DateTime.utc(2026, 8, 10));
      // A Monday is its own bar start.
      expect(floorToTimeframe(DateTime.utc(2026, 8, 10, 0), 'W1'),
          DateTime.utc(2026, 8, 10));
      // A Sunday belongs to the week that began the previous Monday.
      expect(floorToTimeframe(DateTime.utc(2026, 8, 16, 23), 'W1'),
          DateTime.utc(2026, 8, 10));
    });

    test('every timestamp inside one bar snaps to the same instant', () {
      final open = DateTime.utc(2026, 8, 11, 9, 15);
      for (final s in [0, 1, 59, 300, 600, 899]) {
        expect(floorToTimeframe(open.add(Duration(seconds: s)), 'M15'), open);
      }
      // The next second belongs to the next bar.
      expect(floorToTimeframe(open.add(const Duration(minutes: 15)), 'M15'),
          DateTime.utc(2026, 8, 11, 9, 30));
    });
  });

  group('normalizeCandles', () {
    test("folds a feed's trailing live point into the bar it belongs to", () {
      // Exactly the Yahoo shape: a proper 15m bar, then the live quote
      // stamped with the current second.
      final merged = normalizeCandles([
        _c(DateTime.utc(2026, 8, 11, 9, 15),
            open: 4370, high: 4374, low: 4369, close: 4372),
        _c(DateTime.utc(2026, 8, 11, 9, 23, 47),
            open: 4372, high: 4377, low: 4368, close: 4376),
      ], 'M15');

      expect(merged, hasLength(1), reason: 'one 15m bar, not two');
      final bar = merged.single;
      expect(bar.time, DateTime.utc(2026, 8, 11, 9, 15));
      expect(bar.open, 4370); // keeps the open it started with
      expect(bar.close, 4376); // and the most recent close
      expect(bar.high, 4377); // extremes span both points
      expect(bar.low, 4368);
    });

    test('keeps genuinely separate bars separate', () {
      final merged = normalizeCandles([
        _c(DateTime.utc(2026, 8, 11, 9, 0)),
        _c(DateTime.utc(2026, 8, 11, 9, 15)),
        _c(DateTime.utc(2026, 8, 11, 9, 30)),
      ], 'M15');
      expect(merged, hasLength(3));
    });
  });

  group('mergeCandle with bucketed times', () {
    test('repeated polls inside one bar update it instead of appending', () {
      final open = DateTime.utc(2026, 8, 11, 9, 15);
      var series = [
        _c(DateTime.utc(2026, 8, 11, 9, 0)),
        _c(open, close: 4370),
      ];

      // Five polls a few seconds apart, exactly the case in the bug report:
      // un-bucketed these appended a new sliver of a bar every time.
      for (var i = 1; i <= 5; i++) {
        final poll = _c(open.add(Duration(seconds: i * 10)), close: 4370.0 + i);
        series = mergeCandle(series, bucketCandle(poll, 'M15'));
      }

      expect(series, hasLength(2), reason: 'still one forming bar');
      expect(series.last.time, open);
      expect(series.last.close, 4375);
    });

    test('crossing the boundary does append a new bar', () {
      final open = DateTime.utc(2026, 8, 11, 9, 15);
      var series = [_c(open)];
      series = mergeCandle(
          series, bucketCandle(_c(open.add(const Duration(minutes: 15))), 'M15'));
      expect(series, hasLength(2));
      expect(series.last.time, DateTime.utc(2026, 8, 11, 9, 30));
    });
  });

  test('timeframeDuration covers every offered timeframe', () {
    expect(timeframeDuration('M5'), const Duration(minutes: 5));
    expect(timeframeDuration('M15'), const Duration(minutes: 15));
    expect(timeframeDuration('M30'), const Duration(minutes: 30));
    expect(timeframeDuration('H1'), const Duration(hours: 1));
    expect(timeframeDuration('H4'), const Duration(hours: 4));
    expect(timeframeDuration('D1'), const Duration(days: 1));
    expect(timeframeDuration('W1'), const Duration(days: 7));
    expect(() => timeframeDuration('nope'), throwsArgumentError);
  });
}
