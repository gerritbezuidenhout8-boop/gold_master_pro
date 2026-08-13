import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/trade_plan_engine.dart';
import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/screens/signal_journal/signal_journal_screen.dart';
import 'package:gold_master_pro/services/signal_store.dart';
import 'package:gold_master_pro/state/signal_controller.dart';

class _MemStore implements SignalStore {
  List<TradeSignal> data = [];
  @override
  Future<List<TradeSignal>> load() async => List.of(data);
  @override
  Future<void> save(List<TradeSignal> s) async => data = List.of(s);
}

TradePlan _plan({bool long = true}) => TradePlan(
      direction: long ? TradeDirection.long : TradeDirection.short,
      score: long ? 90 : 10,
      confidence: 70,
      entry: 4020,
      entryLow: 4018,
      entryHigh: 4022,
      stop: long ? 4000 : 4040,
      tp1: long ? 4100 : 3940,
      tp2: long ? 4140 : 3900,
      risk: 20,
      rr1: 4,
      rr2: 6,
      validUntil: DateTime.utc(2026, 7, 25),
      rationale: const ['test'],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: const SignalJournalScreen(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late SignalController real;

  setUp(() {
    real = SignalController.instance;
    SignalController.instance = SignalController(store: _MemStore());
  });

  tearDown(() => SignalController.instance = real);

  testWidgets('empty state explains that flat is normal', (tester) async {
    await _pump(tester);
    expect(find.text('No signals yet'), findsOneWidget);
    expect(find.textContaining('Flat is a normal state'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('records a take-profit with its levels and R', (tester) async {
    final c = SignalController.instance;
    await c.load();
    await c.issue(_plan());
    c.onPrice(4100); // hits the target

    await _pump(tester);

    expect(find.text('BUY'), findsOneWidget);
    // GmpPill uppercases.
    expect(find.text('TAKE PROFIT'), findsOneWidget);
    // Twice: the summary total and the signal's own result, which agree
    // because there is exactly one signal.
    expect(find.text('+4.00R'), findsNWidgets(2));
    expect(find.text('Entry'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);
    expect(find.textContaining('1 closed'), findsOneWidget);
    // One trade, taken at its target: the record must read exactly 1 win and
    // no losses.
    expect(find.textContaining('1W · 0L'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a trailing exit reads as a win, not a stop loss',
      (tester) async {
    final c = SignalController.instance;
    await c.load();
    await c.issue(_plan());
    c.onPrice(4060); // ratchets the stop to 4030 (1.5R behind)
    final closed = c.onPrice(4030)!;
    expect(closed.outcome, SignalOutcome.trailingStop);

    await _pump(tester);

    expect(find.text('TRAILING STOP'), findsOneWidget);
    expect(find.text('+0.50R'), findsNWidgets(2)); // summary + the signal
    // The record counts money, not which level closed it.
    expect(find.textContaining('1W · 0L'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a running signal shows as open with no result yet',
      (tester) async {
    final c = SignalController.instance;
    await c.load();
    await c.issue(_plan());

    await _pump(tester);

    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('Exit'), findsNothing);
    expect(find.textContaining('no closed signals'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a target reached only in the bars still reads 1W · 0L',
      (tester) async {
    // The reported case end to end: no tick ever reported the touch, so the
    // trade is settled from the bar's high by PlanScout.settle -> reconcile.
    final c = SignalController.instance;
    await c.load();
    final plan = _plan();
    await c.issue(plan, now: DateTime.utc(2026, 7, 24, 12));

    final closed = c.reconcile([
      Candle(
        time: DateTime.utc(2026, 7, 24, 13),
        open: plan.entry,
        high: plan.tp1, // exact touch, nothing beyond
        low: plan.entry - 1,
        close: plan.entry,
      ),
    ]);
    expect(closed, isNotNull);
    expect(closed!.outcome, SignalOutcome.takeProfit);

    await _pump(tester);

    expect(find.text('TAKE PROFIT'), findsOneWidget);
    expect(find.textContaining('1W · 0L'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('RUNNING'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  test('history keeps enough signals to be a real record', () {
    expect(SignalController.historyLimit, greaterThanOrEqualTo(100));
  });
}
