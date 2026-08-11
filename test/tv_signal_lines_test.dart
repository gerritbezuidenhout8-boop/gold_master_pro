import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/trade_plan_engine.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/widgets/tv_payload.dart';

TradePlan _plan() => TradePlan(
      direction: TradeDirection.long,
      score: 90,
      confidence: 70,
      entry: 4020,
      entryLow: 4018,
      entryHigh: 4022,
      stop: 4000,
      tp1: 4100,
      tp2: 4140,
      risk: 20,
      rr1: 4,
      rr2: 6,
      validUntil: DateTime.utc(2026, 7, 25),
      rationale: const ['test'],
    );

TradeSignal _signal() => TradeSignal(
      id: 's1',
      plan: _plan(),
      openedAt: DateTime.utc(2026, 7, 24, 12),
    );

Map<String, dynamic> _byTitle(List<Map<String, dynamic>> lines, String t) =>
    lines.firstWhere((l) => (l['title'] as String).startsWith(t));

void main() {
  test('a flat desk draws no lines', () {
    expect(signalPriceLines(null), isEmpty);
  });

  test('a closed signal draws no lines', () {
    final closed = _signal().close(
        outcome: SignalOutcome.takeProfit,
        exitPrice: 4100,
        at: DateTime.utc(2026, 7, 24, 14));
    expect(signalPriceLines(closed), isEmpty);
  });

  test('a running signal draws entry, stop and both targets', () {
    final lines = signalPriceLines(_signal());
    expect(lines, hasLength(4));
    expect(_byTitle(lines, 'BUY')['price'], 4020);
    expect(_byTitle(lines, 'SL')['price'], 4000);
    expect(_byTitle(lines, 'TP1')['price'], 4100);
    expect(_byTitle(lines, 'TP2')['price'], 4140);
  });

  test('the stop line follows the trail, not the original level', () {
    // risk 20, trail 1.5R = 30 behind the peak.
    final trailed = _signal().withPeak(4060);
    final sl = _byTitle(signalPriceLines(trailed), 'SL');
    expect(sl['price'], 4030);
    expect(sl['title'], 'SL (trailing)');
    expect(sl['style'], 0, reason: 'solid once actually trailing');
  });

  test('payload always carries priceLines so stale ones get cleared', () {
    final candles = [
      for (var i = 0; i < 30; i++)
        Candle(
          time: DateTime.utc(2026, 8, 11, 9).add(Duration(minutes: 15 * i)),
          open: 4020,
          high: 4025,
          low: 4015,
          close: 4020,
        ),
    ];

    final flat = tvChartPayload(candles);
    expect(flat['priceLines'], isEmpty);

    final running = tvChartPayload(candles, signal: _signal());
    expect(running['priceLines'], hasLength(4));
  });

  group('bar-close countdown', () {
    List<Candle> bars(String tf, DateTime lastOpen) => [
          Candle(
              time: lastOpen, open: 4020, high: 4025, low: 4015, close: 4020),
        ];

    test('barCloseAt is the end of the forming bar', () {
      final p = tvChartPayload(
        bars('M15', DateTime.utc(2026, 8, 11, 9, 15)),
        timeframe: 'M15',
      );
      expect(
        p['barCloseAt'],
        DateTime.utc(2026, 8, 11, 9, 30).millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('each timeframe closes its own bar', () {
      final open = DateTime.utc(2026, 8, 11, 8, 0);
      for (final entry in {
        'M5': DateTime.utc(2026, 8, 11, 8, 5),
        'M30': DateTime.utc(2026, 8, 11, 8, 30),
        'H1': DateTime.utc(2026, 8, 11, 9, 0),
        'H4': DateTime.utc(2026, 8, 11, 12, 0),
      }.entries) {
        final p = tvChartPayload(bars(entry.key, open), timeframe: entry.key);
        expect(p['barCloseAt'],
            entry.value.millisecondsSinceEpoch ~/ 1000,
            reason: entry.key);
      }
    });

    test('omitted without a timeframe, so the label stays hidden', () {
      final p = tvChartPayload(bars('M15', DateTime.utc(2026, 8, 11, 9, 15)));
      expect(p.containsKey('barCloseAt'), isFalse);
    });

    test('no candles means no countdown', () {
      final p = tvChartPayload(const [], timeframe: 'M15');
      expect(p.containsKey('barCloseAt'), isFalse);
    });
  });
}
