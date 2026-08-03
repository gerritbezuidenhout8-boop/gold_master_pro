import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/alert_rule.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/services/alert_store.dart';
import 'package:gold_master_pro/services/app_settings.dart';
import 'package:gold_master_pro/services/market_data.dart';
import 'package:gold_master_pro/services/notifications.dart';
import 'package:gold_master_pro/services/signal_store.dart';
import 'package:gold_master_pro/state/alerts_controller.dart';
import 'package:gold_master_pro/state/plan_scout.dart';
import 'package:gold_master_pro/state/signal_controller.dart';
import 'package:gold_master_pro/widgets/alert_watcher.dart';

import 'gold_master_engine_test.dart' show bullishH1, bullishD1;

class _MemStore implements AlertStore {
  List<AlertRule> data;
  _MemStore([this.data = const []]);
  @override
  Future<List<AlertRule>> load() async => List.of(data);
  @override
  Future<void> save(List<AlertRule> rules) async => data = List.of(rules);
}

class _MemSignals implements SignalStore {
  List<TradeSignal> data = [];
  @override
  Future<List<TradeSignal>> load() async => List.of(data);
  @override
  Future<void> save(List<TradeSignal> s) async => data = List.of(s);
}

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

SpotQuote _q(double p) =>
    SpotQuote(price: p, time: DateTime.utc(2026), source: 'test');

/// Flushes the async hops inside a scout scan (two fetches, a store load and
/// a store save) plus the frame that renders the resulting SnackBar.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

void main() {
  late AlertsController realAlerts;
  late SignalController realSignals;
  late Notifications realNotifications;
  late RecordingNotifications notifications;

  setUp(() {
    realAlerts = AlertsController.instance;
    realSignals = SignalController.instance;
    realNotifications = Notifications.instance;
    notifications = RecordingNotifications();
    Notifications.instance = notifications;
    AppSettings.instance.priceAlerts.value = true; // order-independent
    // Off unless a test opts in, so no test reaches the live feed.
    AppSettings.instance.scoreAlerts.value = false;
  });

  tearDown(() {
    AlertsController.instance = realAlerts;
    SignalController.instance = realSignals;
    Notifications.instance = realNotifications;
    AppSettings.instance.priceAlerts.value = true;
    AppSettings.instance.scoreAlerts.value = true;
  });

  testWidgets('asks for notification permission on mount when alerts are on',
      (tester) async {
    AlertsController.instance = AlertsController(store: _MemStore());
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    // Android 13+ drops every notification until POST_NOTIFICATIONS is granted
    // at runtime. The Settings toggles only prompt on an off→on transition,
    // and both alert switches default to on — so a fresh install never flipped
    // one, never asked, and alerts silently went nowhere.
    expect(notifications.permissionRequests, 1);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not ask for permission when every alert is off',
      (tester) async {
    AppSettings.instance.priceAlerts.value = false;
    AppSettings.instance.scoreAlerts.value = false;
    AlertsController.instance = AlertsController(store: _MemStore());
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(notifications.permissionRequests, 0);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows an in-app SnackBar when a watched level is crossed',
      (tester) async {
    final store = _MemStore(
        [AlertRule(id: 'a', kind: AlertKind.priceAbove, threshold: 4050)]);
    AlertsController.instance = AlertsController(store: store);
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle(); // let load() populate the rule
    expect(AlertsController.instance.rules, hasLength(1));

    quotes.add(_q(4040)); // seed below
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    quotes.add(_q(4060)); // cross up → fires
    await tester.pump(); // deliver the stream event
    await tester.pump(); // build the SnackBar frame
    expect(AlertsController.instance.rules.single.isArmed, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('crosses above'), findsOneWidget);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a crossed level also posts an OS notification', (tester) async {
    final store = _MemStore(
        [AlertRule(id: 'a', kind: AlertKind.priceAbove, threshold: 4050)]);
    AlertsController.instance = AlertsController(store: store);
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    quotes.add(_q(4040));
    await tester.pump();
    expect(notifications.shown, isEmpty);

    quotes.add(_q(4060));
    await tester.pump();
    await tester.pump();

    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single.id, GmpNotificationIds.priceAlert);
    expect(notifications.shown.single.body, contains('crosses above'));

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not fire when Price Alerts are turned off',
      (tester) async {
    final store = _MemStore(
        [AlertRule(id: 'a', kind: AlertKind.priceAbove, threshold: 4050)]);
    AlertsController.instance = AlertsController(store: store);
    AppSettings.instance.priceAlerts.value = false;
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    quotes.add(_q(4040)); // seed below
    await tester.pump();
    quotes.add(_q(4060)); // would cross up, but alerts are off
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(notifications.shown, isEmpty);
    // The rule is never consumed, so it still fires once re-enabled.
    expect(AlertsController.instance.rules.single.isArmed, isTrue);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notifies when the score opens a trade plan', (tester) async {
    AlertsController.instance = AlertsController(store: _MemStore());
    final signals = SignalController(store: _MemSignals());
    SignalController.instance = signals;
    AppSettings.instance.scoreAlerts.value = true;
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        scout: PlanScout(
          data: _Fake(bullishH1(), bullishD1()),
          signals: signals,
          minInterval: Duration.zero,
        ),
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    quotes.add(_q(4000));
    await _flush(tester);

    expect(signals.active, isNotNull,
        reason: 'the scout should have opened a plan');
    expect(notifications.shown, hasLength(1));
    final posted = notifications.shown.single;
    expect(posted.id, GmpNotificationIds.signal);
    expect(posted.title, contains('setup detected'));
    expect(posted.body, contains('Score'));
    expect(posted.body, contains('entry'));
    // Education/analysis framing, never an instruction to trade.
    expect(posted.body, contains('analysis only'));
    expect(find.byType(SnackBar), findsOneWidget);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not hunt when Signal Alerts are turned off',
      (tester) async {
    AlertsController.instance = AlertsController(store: _MemStore());
    final signals = SignalController(store: _MemSignals());
    SignalController.instance = signals;
    AppSettings.instance.scoreAlerts.value = false;
    final quotes = StreamController<SpotQuote>();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AlertWatcher(
        quotes: quotes.stream,
        scout: PlanScout(
          data: _Fake(bullishH1(), bullishD1()),
          signals: signals,
          minInterval: Duration.zero,
        ),
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    quotes.add(_q(4000));
    await _flush(tester);

    expect(signals.active, isNull);
    expect(notifications.shown, isEmpty);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });
}
