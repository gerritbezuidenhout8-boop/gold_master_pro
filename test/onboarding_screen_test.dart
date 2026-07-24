import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/screens/onboarding/onboarding_screen.dart';
import 'package:gold_master_pro/services/alert_store.dart';
import 'package:gold_master_pro/services/app_settings.dart';
import 'package:gold_master_pro/services/market_data.dart';
import 'package:gold_master_pro/services/watchlist.dart';
import 'package:gold_master_pro/state/alerts_controller.dart';

class _FakeMarketData implements MarketData {
  @override
  Future<List<Candle>> fetchCandles(String timeframe) async => const [];
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
  late WatchlistFetcher realWatchlist;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    realMarketData = MarketData.instance;
    MarketData.instance = _FakeMarketData();
    realAlerts = AlertsController.instance;
    AlertsController.instance = AlertsController(store: LocalAlertStore());
    realWatchlist = Watchlist.fetch;
    Watchlist.fetch = () async => const [];
    AppSettings.instance.onboardingComplete.value = false;
  });

  tearDown(() {
    MarketData.instance = realMarketData;
    AlertsController.instance = realAlerts;
    Watchlist.fetch = realWatchlist;
    AppSettings.instance.onboardingComplete.value = false;
  });

  testWidgets('advances through slides and Get Started enters the shell',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const OnboardingScreen(),
    ));

    // First slide, with the not-financial-advice disclaimer.
    expect(find.text('The Gold Master Score'), findsOneWidget);
    expect(find.textContaining('not'), findsWidgets);
    expect(find.text('Next'), findsOneWidget);

    // Walk to the last slide.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Alerts & journal'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Finish → flag persists and the shell replaces onboarding.
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.onboardingComplete.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('gmp-onboarding-complete'), isTrue);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget); // shell nav

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Skip completes onboarding immediately', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const OnboardingScreen(),
    ));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.onboardingComplete.value, isTrue);
    expect(find.text('Home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
