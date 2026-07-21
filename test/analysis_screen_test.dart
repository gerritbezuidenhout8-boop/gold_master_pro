import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/screens/analysis/analysis_screen.dart';
import 'package:gold_master_pro/services/market_data.dart';

class _FakeMarketData implements MarketData {
  @override
  Future<List<Candle>> fetchCandles(String timeframe) async {
    if (timeframe == 'D1') {
      return [
        for (var d = 6; d <= 21; d++)
          Candle(
            time: DateTime.utc(2026, 7, d),
            open: 90.0 + d,
            high: d == 10 ? 200 : 100.0 + d,
            low: 80.0 + d,
            close: 95.0 + d,
          ),
      ];
    }
    // H1: quiet drift, then a bearish candle engulfed by a bullish one.
    final base = [
      for (var i = 0; i < 58; i++)
        Candle(
          time: DateTime.utc(2026, 7, 20).add(Duration(hours: i)),
          open: 100 + 0.1 * i,
          high: 100 + 0.1 * i + 0.15,
          low: 100 + 0.1 * i - 0.1,
          close: 100 + 0.1 * i + 0.05,
        ),
    ];
    return [
      ...base,
      Candle(
        time: DateTime.utc(2026, 7, 22, 10),
        open: 105,
        high: 105.2,
        low: 103.9,
        close: 104,
      ),
      Candle(
        time: DateTime.utc(2026, 7, 22, 11),
        open: 103.9,
        high: 105.6,
        low: 103.8,
        close: 105.5,
      ),
    ];
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

  setUp(() {
    real = MarketData.instance;
    MarketData.instance = _FakeMarketData();
  });

  tearDown(() {
    MarketData.instance = real;
  });

  testWidgets('shows key levels, fibonacci, SMMA and detected patterns',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalysisScreen()));
    await tester.pump();
    await tester.pump();

    // Section labels are uppercased; cards are virtualized so scroll to each.
    expect(find.text('TREND ANALYSIS'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.text('KEY LEVELS (UTC DAYS)'), 250);
    expect(find.text('Prev Week High'), findsOneWidget);
    expect(find.text('119.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('200.00'), 250); // ATH spike

    await tester.scrollUntilVisible(find.text('INDICATOR SUMMARY'), 250);
    expect(find.text('AUTO FIBONACCI · H1'), findsNothing); // not yet reached

    await tester.scrollUntilVisible(find.text('AUTO FIBONACCI · H1'), 250);
    expect(find.text('61.8%'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('MOVING AVERAGES · H1'), 250);
    expect(find.textContaining('price'), findsWidgets); // above/below note

    await tester.scrollUntilVisible(find.text('Bullish Engulfing').first, 250);
    expect(find.text('Bullish Engulfing'), findsWidgets);
  });

  testWidgets('theme variant renders without errors', (tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const AnalysisScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
