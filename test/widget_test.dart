import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_chart_plus/k_chart_plus.dart' show KChartWidget;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/main.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/services/alert_store.dart';
import 'package:gold_master_pro/services/market_data.dart';
import 'package:gold_master_pro/state/alerts_controller.dart';

class _FakeMarketData implements MarketData {
  @override
  Future<List<Candle>> fetchCandles(String timeframe) async => [
        for (var i = 0; i < 60; i++)
          Candle(
            time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
            open: 100.0 + i,
            high: 101.0 + i,
            low: 99.0 + i,
            close: 100.5 + i,
            volume: 1,
          ),
      ];

  @override
  Stream<Candle> candleStream(String timeframe) => const Stream.empty();

  @override
  Stream<SpotQuote> quoteStream() => const Stream.empty();

  @override
  Future<SpotQuote?> fetchXauSpot() async => null;
}

void main() {
  late MarketData realMarketData;
  late AlertsController realAlerts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    realMarketData = MarketData.instance;
    MarketData.instance = _FakeMarketData();
    // The app-level AlertWatcher loads alerts at launch; give it a fresh
    // controller over an empty store so tests don't share state.
    realAlerts = AlertsController.instance;
    AlertsController.instance = AlertsController(store: LocalAlertStore());
  });

  tearDown(() {
    MarketData.instance = realMarketData;
    AlertsController.instance = realAlerts;
  });

  testWidgets('boots to Home with six destinations', (tester) async {
    await tester.pumpWidget(const GmpApp());

    for (final label in [
      'Home',
      'Analysis',
      'Chart',
      'Markets',
      'Alerts',
      'Profile',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Gold Master Pro'), findsOneWidget);
    // Chart screen is offstage inside the IndexedStack until selected.
    expect(find.text('M15'), findsNothing);

    // Dispose the tree so subscriptions and timers shut down.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chart tab renders candles from the market-data facade',
      (tester) async {
    await tester.pumpWidget(const GmpApp());

    await tester.tap(find.text('Chart'));
    await tester.pump();
    await tester.pump();

    expect(find.text('M15'), findsOneWidget);
    expect(find.text('XAUUSD · H1'), findsOneWidget);
    expect(find.textContaining('PAXG'), findsOneWidget);
    expect(find.byType(KChartWidget), findsOneWidget);

    // Dispose the tree so subscriptions and timers shut down.
    await tester.pumpWidget(const SizedBox());
  });
}
