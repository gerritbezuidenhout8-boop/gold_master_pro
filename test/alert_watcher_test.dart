import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/alert_rule.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/services/alert_store.dart';
import 'package:gold_master_pro/services/app_settings.dart';
import 'package:gold_master_pro/state/alerts_controller.dart';
import 'package:gold_master_pro/widgets/alert_watcher.dart';

class _MemStore implements AlertStore {
  List<AlertRule> data;
  _MemStore([this.data = const []]);
  @override
  Future<List<AlertRule>> load() async => List.of(data);
  @override
  Future<void> save(List<AlertRule> rules) async => data = List.of(rules);
}

SpotQuote _q(double p) =>
    SpotQuote(price: p, time: DateTime.utc(2026), source: 'test');

void main() {
  late AlertsController real;

  setUp(() {
    real = AlertsController.instance;
    AppSettings.instance.priceAlerts.value = true; // order-independent
  });
  tearDown(() {
    AlertsController.instance = real;
    AppSettings.instance.priceAlerts.value = true;
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
    // The rule is never consumed, so it still fires once re-enabled.
    expect(AlertsController.instance.rules.single.isArmed, isTrue);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });
}
