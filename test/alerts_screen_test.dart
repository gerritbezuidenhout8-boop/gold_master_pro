import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/alert_rule.dart';
import 'package:gold_master_pro/screens/alerts/alerts_screen.dart';
import 'package:gold_master_pro/services/alert_store.dart';
import 'package:gold_master_pro/state/alerts_controller.dart';

class _MemStore implements AlertStore {
  List<AlertRule> data = [];

  @override
  Future<List<AlertRule>> load() async => List.of(data);

  @override
  Future<void> save(List<AlertRule> rules) async => data = List.of(rules);
}

void main() {
  late AlertsController real;
  late _MemStore store;

  setUp(() {
    real = AlertsController.instance;
    store = _MemStore();
    AlertsController.instance = AlertsController(store: store);
  });

  tearDown(() => AlertsController.instance = real);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const AlertsScreen()));
    await tester.pump();
  }

  testWidgets('empty state and live-watch card', (tester) async {
    await pump(tester);
    expect(find.text('Live watch'), findsOneWidget);
    expect(find.textContaining('No alerts yet'), findsOneWidget);
    expect(find.text('waiting for feed…'), findsOneWidget);
  });

  testWidgets('creates a price alert through the sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('add-alert')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('threshold-field')), '4100');
    await tester.tap(find.byKey(const ValueKey('save-alert-button')));
    await tester.pumpAndSettle();

    expect(find.text('Gold crosses above 4,100.00'), findsOneWidget);
    expect(find.text('ARMED'), findsOneWidget);
    expect(store.data.single.threshold, 4100);
  });

  testWidgets('a fired alert shows a Re-arm action that re-arms it',
      (tester) async {
    AlertsController.instance = AlertsController(store: store);
    await AlertsController.instance.upsert(AlertRule(
      id: 'a',
      kind: AlertKind.priceBelow,
      threshold: 4000,
    ));
    // Drive a crossing so the rule fires.
    AlertsController.instance.onPrice(4010);
    AlertsController.instance.onPrice(3990);

    await pump(tester);
    expect(find.textContaining('FIRED'), findsOneWidget);

    await tester.tap(find.text('Re-arm'));
    await tester.pump();
    expect(find.text('ARMED'), findsOneWidget);
    expect(AlertsController.instance.rules.single.isArmed, isTrue);
  });

  testWidgets('validation blocks a non-numeric level', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('add-alert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-alert-button')));
    await tester.pump();
    expect(find.text('Price must be a positive number'), findsOneWidget);
    expect(store.data, isEmpty);
  });
}
