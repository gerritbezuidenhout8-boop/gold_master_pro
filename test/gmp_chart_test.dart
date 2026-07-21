import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_plus/k_chart_plus.dart';

import 'package:gold_master_pro/indicators/smma.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/widgets/gmp_chart.dart';

void main() {
  test('SmmaIndicator fills maValueList with real SMMA values', () {
    final closes = [for (var i = 1; i <= 260; i++) i.toDouble()];
    final datas = [
      for (final c in closes)
        KLineEntity.fromCustom(
            time: 0, open: c, high: c, low: c, close: c, vol: 0),
    ];
    SmmaIndicator().calc(datas);

    expect(datas[10].maValueList![0], 0);
    expect(datas[20].maValueList![0], closeTo(Smma.compute(closes, 21)[20]!, 1e-9));
    expect(datas[100].maValueList![1],
        closeTo(Smma.compute(closes, 50)[100]!, 1e-9));
    expect(datas[259].maValueList![2],
        closeTo(Smma.compute(closes, 200)[259]!, 1e-9));
  });

  test('prepare converts candles and computes the three overlays', () {
    final candles = [
      for (var i = 1; i <= 30; i++)
        Candle(
          time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          open: i.toDouble(),
          high: i + 1.0,
          low: i - 1.0,
          close: i + 0.5,
          volume: 10,
        ),
    ];
    final datas = GmpChart.prepare(candles);
    expect(datas.length, 30);
    expect(datas.first.open, 1.0);
    expect(datas[25].maValueList, hasLength(3));
    expect(datas[25].maValueList![0], isNot(0));
    expect(datas[25].maValueList![2], 0);
  });
}
