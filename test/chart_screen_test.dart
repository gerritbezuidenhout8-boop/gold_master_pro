import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_plus/k_chart_plus.dart' show KChartWidget;

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/screens/chart/chart_screen.dart';
import 'package:gold_master_pro/widgets/gmp_chart.dart';

List<Candle> _syntheticCandles(int n) => [
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

Stream<Candle> _noStream(String _) => const Stream.empty();

void main() {
  testWidgets(
      'renders the chart engine once candles load, reloads on '
      'timeframe change', (tester) async {
    final requested = <String>[];
    Future<List<Candle>> loader(String tf) {
      requested.add(tf);
      return Future.value(_syntheticCandles(60));
    }

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: ChartScreen(loadCandles: loader, streamCandles: _noStream),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(KChartWidget), findsOneWidget);
    expect(requested, ['H1']);

    await tester.tap(find.text('M5'));
    await tester.pump();
    await tester.pump();
    expect(requested, ['H1', 'M5']);
    expect(find.text('XAUUSD · M5'), findsOneWidget);
    expect(find.byType(KChartWidget), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose throttle timer
  });

  testWidgets('applies live candle updates to the chart', (tester) async {
    final updates = StreamController<Candle>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: ChartScreen(
        loadCandles: (_) => Future.value(_syntheticCandles(60)),
        streamCandles: (_) => updates.stream,
      ),
    ));
    await tester.pump();
    expect(tester.widget<GmpChart>(find.byType(GmpChart)).datas, hasLength(60));

    updates.add(Candle(
      time: DateTime.utc(2026, 1, 1).add(const Duration(hours: 60)),
      open: 200,
      high: 201,
      low: 199,
      close: 200.5,
      volume: 1,
    ));
    await tester.pump(); // deliver stream event (marks dirty)
    // Updates are throttled — advance past the 1s coalescing window.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.widget<GmpChart>(find.byType(GmpChart)).datas, hasLength(61));

    await updates.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the error state with a retry button when loading fails',
      (tester) async {
    var calls = 0;
    Future<List<Candle>> loader(String tf) {
      calls++;
      if (calls == 1) return Future.error(StateError('boom'));
      return Future.value(_syntheticCandles(30));
    }

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: ChartScreen(loadCandles: loader, streamCandles: _noStream),
    ));
    await tester.pump();
    expect(find.textContaining('Could not load candles'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(KChartWidget), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose throttle timer
  });
}
