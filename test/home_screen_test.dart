import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/screens/home/home_screen.dart';
import 'package:gold_master_pro/services/market_data.dart';

import 'gold_master_engine_test.dart' show bullishH1, bullishD1;

class _BullishFake implements MarketData {
  int fetches = 0;

  @override
  Future<List<Candle>> fetchCandles(String timeframe) async {
    fetches++;
    return timeframe == 'D1' ? bullishD1() : bullishH1();
  }

  @override
  Stream<Candle> candleStream(String timeframe) => const Stream.empty();

  @override
  Stream<SpotQuote> quoteStream() => const Stream.empty();

  @override
  Future<SpotQuote?> fetchXauSpot() async => null;
}

void main() {
  late MarketData real;
  late _BullishFake fake;

  setUp(() {
    real = MarketData.instance;
    fake = _BullishFake();
    MarketData.instance = fake;
  });

  tearDown(() {
    MarketData.instance = real;
  });

  testWidgets('renders score, bias chip, story and data health; '
      'Analyze recomputes', (tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const HomeScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('GOLD MASTER SCORE'), findsOneWidget);
    expect(find.text('BULLISH'), findsOneWidget);
    expect(find.text('/100'), findsOneWidget); // score gauge centre
    expect(fake.fetches, 2);

    await tester.scrollUntilVisible(
        find.textContaining('Gold trades at'), 300);
    expect(find.textContaining('Gold trades at'), findsOneWidget);

    await tester.scrollUntilVisible(find.textContaining('candles'), 300);
    // Synthetic fixtures are old, so the feed reads as delayed.
    expect(find.textContaining('delayed'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Analyze Gold'), 300);
    await tester.tap(find.text('Analyze Gold'));
    await tester.pump();
    await tester.pump();
    expect(fake.fetches, 4);

    // Dispose so the live-price card's timers shut down.
    await tester.pumpWidget(const SizedBox());
  });
}
