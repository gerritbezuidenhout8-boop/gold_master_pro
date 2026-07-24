import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/indicators/atr.dart';
import 'package:gold_master_pro/models/candle.dart';

void main() {
  test('constant-range candles give an ATR equal to that range', () {
    // Each candle spans 2.0 and there are no gaps, so TR == 2 throughout.
    final candles = [
      for (var i = 0; i < 30; i++)
        Candle(
          time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          open: 100,
          high: 101,
          low: 99,
          close: 100,
        ),
    ];
    expect(Atr.latest(candles), closeTo(2.0, 1e-9));
  });

  test('null when there are fewer than period + 1 candles', () {
    final few = [
      for (var i = 0; i < 10; i++)
        Candle(
            time: DateTime.utc(2026).add(Duration(hours: i)),
            open: 1,
            high: 2,
            low: 0,
            close: 1),
    ];
    expect(Atr.latest(few), isNull);
  });

  test('gaps widen the true range', () {
    final candles = [
      for (var i = 0; i < 20; i++)
        Candle(
          time: DateTime.utc(2026).add(Duration(hours: i)),
          open: 100.0 + i * 5,
          high: 101.0 + i * 5,
          low: 99.0 + i * 5, // each candle gaps up 5 vs previous close
          close: 100.0 + i * 5,
        ),
    ];
    // True range includes the gap, so ATR exceeds the 2-point candle span.
    expect(Atr.latest(candles)!, greaterThan(2.0));
  });
}
