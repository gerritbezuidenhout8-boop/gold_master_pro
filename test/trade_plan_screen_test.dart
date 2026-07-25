import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/screens/trade_plan/trade_plan_screen.dart';
import 'package:gold_master_pro/services/market_data.dart';
import 'package:gold_master_pro/services/signal_store.dart';
import 'package:gold_master_pro/state/signal_controller.dart';

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

class _MemStore implements SignalStore {
  List<TradeSignal> data = [];
  @override
  Future<List<TradeSignal>> load() async => List.of(data);
  @override
  Future<void> save(List<TradeSignal> s) async => data = List.of(s);
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
  late SignalController realSignals;

  setUp(() {
    real = MarketData.instance;
    realSignals = SignalController.instance;
    SignalController.instance = SignalController(store: _MemStore());
  });
  tearDown(() {
    MarketData.instance = real;
    SignalController.instance = realSignals;
  });

  testWidgets('issues one BUY signal with entry, TP and SL', (tester) async {
    MarketData.instance = _Fake(bullishH1(), bullishD1());
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const TradePlanScreen()));
    await tester.pumpAndSettle();

    expect(find.text('BUY SIGNAL'), findsOneWidget);
    // The plain-language instruction the plan is meant to give.
    expect(find.textContaining('Take buy trade at'), findsOneWidget);
    expect(find.textContaining('TP at'), findsOneWidget);
    expect(find.textContaining('SL at'), findsOneWidget);
    expect(find.text('Live Tracking'.toUpperCase()), findsOneWidget);

    final active = SignalController.instance.active!;
    expect(active.isLong, isTrue);
    expect(active.plan.tp1, greaterThan(active.plan.entry));
    expect(active.plan.stop, lessThan(active.plan.entry));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a neutral score stays flat and issues nothing', (tester) async {
    MarketData.instance = _Fake(_flat(60), _flat(30, daily: true));
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const TradePlanScreen()));
    await tester.pumpAndSettle();

    expect(find.text('NO HIGH-CONVICTION SIGNAL'), findsOneWidget);
    expect(find.text('BUY SIGNAL'), findsNothing);
    expect(find.textContaining('≥ 80'), findsOneWidget);
    // Flat is a real state: nothing was opened.
    expect(SignalController.instance.active, isNull);
    expect(SignalController.instance.signals, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('re-analysing does not replace the running signal',
      (tester) async {
    MarketData.instance = _Fake(bullishH1(), bullishD1());
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const TradePlanScreen()));
    await tester.pumpAndSettle();

    final first = SignalController.instance.active!;
    expect(SignalController.instance.signals, hasLength(1));

    await tester.tap(find.byTooltip('Re-analyse'));
    await tester.pumpAndSettle();

    // Still exactly one, and still the same trade.
    expect(SignalController.instance.signals, hasLength(1));
    expect(SignalController.instance.active!.id, first.id);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a closed signal frees the next one and shows in history',
      (tester) async {
    MarketData.instance = _Fake(bullishH1(), bullishD1());
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const TradePlanScreen()));
    await tester.pumpAndSettle();

    final signals = SignalController.instance;
    final first = signals.active!;
    // Drive price to the take-profit — the trade closes.
    signals.onPrice(first.plan.tp1 + 1);
    await tester.pumpAndSettle();
    expect(signals.active, isNull);
    expect(signals.history, hasLength(1));

    // Re-analysing now issues the next trade.
    await tester.tap(find.byTooltip('Re-analyse'));
    await tester.pumpAndSettle();
    expect(signals.active, isNotNull);
    expect(signals.active!.id, isNot(first.id));

    await tester.scrollUntilVisible(find.text('SIGNAL HISTORY'), 250);
    expect(find.text('SIGNAL HISTORY'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
