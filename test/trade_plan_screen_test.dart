import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/screens/trade_plan/trade_plan_screen.dart';
import 'package:gold_master_pro/services/market_data.dart';

import 'gold_master_engine_test.dart' show bullishH1, bullishD1;

class _Fake implements MarketData {
  _Fake(this.h1, this.d1);
  final List<Candle> h1;
  final List<Candle> d1;

  @override
  Future<List<Candle>> fetchCandles(String timeframe) async =>
      timeframe == 'D1' ? d1 : h1;

  @override
  Stream<Candle> candleStream(String timeframe) => const Stream.empty();

  @override
  Stream<SpotQuote> quoteStream() => const Stream.empty();

  @override
  Future<SpotQuote?> fetchXauSpot() async => null;
}

List<Candle> _flat(int n, {bool daily = false}) => [
      for (var i = 0; i < n; i++)
        Candle(
          time: daily
              ? DateTime.utc(2026, 1, 1).add(Duration(days: i))
              : DateTime.utc(2026, 6, 1).add(Duration(hours: i)),
          open: 100,
          high: 100,
          low: 100,
          close: 100,
        ),
    ];

void main() {
  late MarketData real;

  setUp(() => real = MarketData.instance);
  tearDown(() => MarketData.instance = real);

  testWidgets('strong bullish score shows a BUY trade plan', (tester) async {
    MarketData.instance = _Fake(bullishH1(), bullishD1());
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const TradePlanScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('BUY SETUP'), findsOneWidget);
    expect(find.text('Entry Zone'), findsOneWidget);
    expect(find.text('Stop Loss'), findsOneWidget);
    expect(find.text('Take Profit 1'), findsOneWidget);
    expect(find.text('Take Profit 2'), findsOneWidget);
    expect(find.text('RISK / REWARD'), findsOneWidget);

    // Disclaimer sits at the bottom of the list — scroll to confirm it.
    await tester.scrollUntilVisible(
        find.textContaining('not financial advice'), 250);
    expect(find.textContaining('not financial advice'), findsOneWidget);
  });

  testWidgets('neutral score shows the no-signal state', (tester) async {
    MarketData.instance = _Fake(_flat(60), _flat(30, daily: true));
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const TradePlanScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('NO HIGH-CONVICTION SIGNAL'), findsOneWidget);
    expect(find.text('BUY SETUP'), findsNothing);
    expect(find.textContaining('≥ 80'), findsOneWidget);
  });
}
