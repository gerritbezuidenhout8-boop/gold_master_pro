import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/key_levels.dart';
import 'package:gold_master_pro/models/candle.dart';

// July 2026: the 6th and 20th are Mondays; the 21st (a Tuesday) is "today".
Candle _d(int day, {double? high}) => Candle(
      time: DateTime.utc(2026, 7, day),
      open: 90.0 + day,
      high: high ?? 100.0 + day,
      low: 80.0 + day,
      close: 95.0 + day,
    );

List<Candle> _july() => [
      for (var d = 6; d <= 21; d++) _d(d, high: d == 10 ? 200 : null),
    ];

void main() {
  test('computes daily, weekly, previous and all-time levels (UTC)', () {
    final r = KeyLevels.compute(_july());
    expect(r.asOf, DateTime.utc(2026, 7, 21));
    expect(r.dailyOpen, 111);
    expect(r.dailyHigh, 121);
    expect(r.dailyLow, 101);
    expect(r.prevDayHigh, 120);
    expect(r.prevDayLow, 100);
    expect(r.weekHigh, 121); // Mon 20 + Tue 21
    expect(r.weekLow, 100);
    expect(r.prevWeekHigh, 119); // 13th–19th
    expect(r.prevWeekLow, 93);
    expect(r.allTimeHigh, 200); // spike on the 10th
  });

  test('Monday: current week holds a single day', () {
    final candles = _july().sublist(0, 15); // ends Mon 20th
    final r = KeyLevels.compute(candles);
    expect(r.weekHigh, 120);
    expect(r.weekLow, 100);
    expect(r.prevWeekHigh, 119);
    expect(r.prevWeekLow, 93);
    expect(r.prevDayHigh, 119); // Sun 19th
  });

  test('single candle: previous fields are null', () {
    final r = KeyLevels.compute([_d(21)]);
    expect(r.prevDayHigh, isNull);
    expect(r.prevWeekHigh, isNull);
    expect(r.weekHigh, 121);
    expect(r.allTimeHigh, 121);
  });

  test('weekStart maps any weekday to Monday 00:00 UTC', () {
    expect(KeyLevels.weekStart(DateTime.utc(2026, 7, 21, 13, 45)),
        DateTime.utc(2026, 7, 20));
    expect(KeyLevels.weekStart(DateTime.utc(2026, 7, 19)),
        DateTime.utc(2026, 7, 13)); // Sunday belongs to the week before
    expect(KeyLevels.weekStart(DateTime.utc(2026, 7, 20)),
        DateTime.utc(2026, 7, 20));
  });

  test('rejects an empty list', () {
    expect(() => KeyLevels.compute(const []), throwsArgumentError);
  });
}
