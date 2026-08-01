import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/services/market_data.dart';
import 'package:gold_master_pro/services/signal_store.dart';
import 'package:gold_master_pro/state/plan_scout.dart';
import 'package:gold_master_pro/state/signal_controller.dart';

import 'gold_master_engine_test.dart' show bullishH1, bullishD1;

class _Fake implements MarketData {
  _Fake(this.h1, this.d1);
  final List<Candle> h1;
  final List<Candle> d1;
  int h1Calls = 0;
  int d1Calls = 0;

  @override
  Future<List<Candle>> fetchCandles(String timeframe) async {
    if (timeframe == 'D1') {
      d1Calls++;
      return d1;
    }
    h1Calls++;
    return h1;
  }

  @override
  Stream<Candle> candleStream(String timeframe) => const Stream.empty();

  @override
  Stream<SpotQuote> quoteStream() => const Stream.empty();

  @override
  Future<SpotQuote?> fetchXauSpot() async => null;
}

class _Broken implements MarketData {
  @override
  Future<List<Candle>> fetchCandles(String timeframe) async =>
      throw Exception('offline');

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

final DateTime _t0 = DateTime.utc(2026, 6, 3, 12);

void main() {
  late SignalController signals;

  SignalController fresh() => SignalController(store: _MemStore());

  setUp(() => signals = fresh());

  test('issues a signal when the score clears the 80 gate', () async {
    final scout = PlanScout(
      data: _Fake(bullishH1(), bullishD1()),
      signals: signals,
    );

    final opened = await scout.scan(now: _t0);

    expect(opened, isNotNull);
    expect(opened!.plan.score, greaterThanOrEqualTo(80));
    expect(opened.isOpen, isTrue);
    expect(signals.active, isNotNull);
  });

  test('a flat market issues nothing', () async {
    final scout = PlanScout(
      data: _Fake(_flat(60), _flat(30, daily: true)),
      signals: signals,
    );

    expect(await scout.scan(now: _t0), isNull);
    expect(signals.active, isNull);
  });

  test('throttles a second scan inside minInterval', () async {
    final feed = _Fake(bullishH1(), bullishD1());
    final scout = PlanScout(
      data: feed,
      signals: signals,
      minInterval: const Duration(minutes: 1),
    );

    await scout.scan(now: _t0);
    expect(feed.h1Calls, 1);

    // 30s later: throttled, so the network is never touched.
    expect(await scout.scan(now: _t0.add(const Duration(seconds: 30))), isNull);
    expect(feed.h1Calls, 1);
    expect(scout.due(_t0.add(const Duration(seconds: 30))), isFalse);
    expect(scout.due(_t0.add(const Duration(minutes: 1))), isTrue);
  });

  test('will not open a second signal while one is running', () async {
    final feed = _Fake(bullishH1(), bullishD1());
    final scout = PlanScout(
      data: feed,
      signals: signals,
      minInterval: Duration.zero,
    );

    expect(await scout.scan(now: _t0), isNotNull);
    // The gate is the running trade, not the throttle.
    expect(await scout.scan(now: _t0.add(const Duration(hours: 1))), isNull);
    expect(signals.signals.where((s) => s.isOpen), hasLength(1));
  });

  test('reuses the daily fetch inside the cache window', () async {
    final feed = _Fake(_flat(60), _flat(30, daily: true));
    final scout = PlanScout(
      data: feed,
      signals: signals,
      minInterval: Duration.zero,
      dailyCacheTtl: const Duration(minutes: 15),
    );

    await scout.scan(now: _t0);
    await scout.scan(now: _t0.add(const Duration(minutes: 5)));
    expect(feed.h1Calls, 2, reason: 'hourly candles are always refetched');
    expect(feed.d1Calls, 1, reason: 'daily candles come from cache');

    await scout.scan(now: _t0.add(const Duration(minutes: 20)));
    expect(feed.d1Calls, 2, reason: 'cache expired');
  });

  test('a failing feed returns null instead of throwing', () async {
    final scout = PlanScout(data: _Broken(), signals: signals);

    expect(await scout.scan(now: _t0), isNull);
    expect(signals.active, isNull);
    // The failed attempt still counts, so a dead feed cannot spin the app.
    expect(scout.due(_t0), isFalse);
  });

  test('records when it last looked, even when nothing fired', () async {
    final scout = PlanScout(
      data: _Fake(_flat(60), _flat(30, daily: true)),
      signals: signals,
    );

    expect(scout.lastScan, isNull);
    expect(scout.due(_t0), isTrue);
    await scout.scan(now: _t0);
    expect(scout.lastScan, _t0);
  });
}
