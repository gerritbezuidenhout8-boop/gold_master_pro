import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/widgets/tv_chart.dart';

List<Candle> _trend(int n) => [
      for (var i = 0; i < n; i++)
        Candle(
          time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          open: 100.0 + i,
          high: 101.0 + i,
          low: 99.0 + i,
          close: 100.5 + i,
          volume: 5,
        ),
    ];

void main() {
  test('serializes candles and volume with epoch-second times', () {
    final candles = _trend(30);
    final p = tvChartPayload(candles, stochRsi: false, divergence: false);
    final cs = p['candles'] as List;
    expect(cs, hasLength(30));
    expect((cs.first as Map)['time'],
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000);
    expect((cs.first as Map)['open'], 100.0);
    final vols = p['volume'] as List;
    expect((vols.first as Map)['color'], contains('37,198,133')); // up candle
    expect(p.containsKey('stochK'), isFalse);
    expect(p.containsKey('markers'), isFalse);
  });

  test('SMMA series skip the warm-up window', () {
    final p = tvChartPayload(_trend(60), stochRsi: false, divergence: false);
    final smma = p['smma'] as List;
    expect(smma, hasLength(3));
    expect(smma[0] as List, hasLength(60 - 20)); // SMMA 21
    expect(smma[1] as List, hasLength(60 - 49)); // SMMA 50
    expect(smma[2] as List, isEmpty); // SMMA 200 needs 200 candles
  });

  test('stoch series appear when enabled and data suffices', () {
    final p = tvChartPayload(_trend(120));
    expect((p['stochK'] as List), isNotEmpty);
    expect((p['stochD'] as List), isNotEmpty);
    final k = (p['stochK'] as List).first as Map;
    expect(k['value'], inInclusiveRange(0, 100));
  });

  test('divergence markers map to arrows at the pivot time', () {
    // The known bullish-divergence construction from rsi_test.
    final closes = <double>[];
    for (var i = 0; i < 16; i++) {
      closes.add(100 + (i.isEven ? 1.0 : -1.0));
    }
    for (var i = 0; i < 14; i++) {
      closes.add(closes.last - 4);
    }
    for (var i = 0; i < 10; i++) {
      closes.add(closes.last + 3);
    }
    for (var i = 0; i < 8; i++) {
      closes.add(closes.last - 4);
    }
    for (var i = 0; i < 8; i++) {
      closes.add(closes.last + 3);
    }
    final candles = [
      for (var i = 0; i < closes.length; i++)
        Candle(
          time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          open: closes[i],
          high: closes[i] + 0.5,
          low: closes[i] - 0.5,
          close: closes[i],
        ),
    ];
    final p = tvChartPayload(candles, stochRsi: false);
    final markers = p['markers'] as List;
    expect(markers, isNotEmpty);
    final bull = markers.cast<Map>().firstWhere(
        (m) => m['position'] == 'belowBar',
        orElse: () => throw StateError('no bullish marker'));
    expect(bull['shape'], 'arrowUp');
    expect(bull['text'], 'Bull div');
  });
}
