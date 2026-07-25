import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/signal_engine.dart';
import 'package:gold_master_pro/ai/trade_plan_engine.dart';
import 'package:gold_master_pro/models/candle.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/services/signal_store.dart';
import 'package:gold_master_pro/state/signal_controller.dart';

TradePlan _plan({required bool long}) => TradePlan(
      direction: long ? TradeDirection.long : TradeDirection.short,
      score: long ? 85 : 15,
      confidence: 70,
      entry: 4000,
      entryLow: 3998,
      entryHigh: 4002,
      stop: long ? 3980 : 4020,
      tp1: long ? 4040 : 3960,
      tp2: long ? 4060 : 3940,
      risk: 20,
      rr1: 2,
      rr2: 3,
      validUntil: DateTime.utc(2026, 7, 25),
      rationale: const ['test'],
    );

TradeSignal _signal({required bool long, DateTime? openedAt}) => TradeSignal(
      id: 's1',
      plan: _plan(long: long),
      openedAt: openedAt ?? DateTime.utc(2026, 7, 24, 12),
    );

Candle _c(DateTime t, double high, double low) =>
    Candle(time: t, open: 4000, high: high, low: low, close: 4000);

class _MemStore implements SignalStore {
  List<TradeSignal> data = [];
  @override
  Future<List<TradeSignal>> load() async => List.of(data);
  @override
  Future<void> save(List<TradeSignal> s) async => data = List.of(s);
}

void main() {
  group('SignalEngine.resolve (live tick)', () {
    test('long: closes at take-profit, at the level', () {
      final r = SignalEngine.resolve(_signal(long: true), 4041)!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.exitPrice, 4040); // booked at the level, not the overshoot
    });

    test('long: closes at the stop', () {
      final r = SignalEngine.resolve(_signal(long: true), 3975)!;
      expect(r.outcome, SignalOutcome.stopLoss);
      expect(r.exitPrice, 3980);
    });

    test('short: mirrors both sides', () {
      expect(SignalEngine.resolve(_signal(long: false), 3959)!.outcome,
          SignalOutcome.takeProfit);
      expect(SignalEngine.resolve(_signal(long: false), 4025)!.outcome,
          SignalOutcome.stopLoss);
    });

    test('stays open between the levels', () {
      expect(SignalEngine.resolve(_signal(long: true), 4010), isNull);
      expect(SignalEngine.resolve(_signal(long: false), 3990), isNull);
    });

    test('an already-closed signal never resolves again', () {
      final closed = _signal(long: true).close(
        outcome: SignalOutcome.takeProfit,
        exitPrice: 4040,
        at: DateTime.utc(2026, 7, 24, 13),
      );
      expect(SignalEngine.resolve(closed, 3900), isNull);
    });
  });

  group('SignalEngine.resolveFromCandles (backfill)', () {
    test('settles a trade that completed while the app was closed', () {
      final s = _signal(long: true);
      final candles = [
        _c(DateTime.utc(2026, 7, 24, 13), 4010, 3995),
        _c(DateTime.utc(2026, 7, 24, 14), 4045, 4005), // target touched
      ];
      final r = SignalEngine.resolveFromCandles(s, candles)!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.at, DateTime.utc(2026, 7, 24, 14));
    });

    test('ignores bars from before the signal opened', () {
      final s = _signal(long: true);
      final stale = [_c(DateTime.utc(2026, 7, 24, 9), 4090, 3900)];
      expect(SignalEngine.resolveFromCandles(s, stale), isNull);
    });

    test('a bar touching both levels counts as the stop', () {
      final s = _signal(long: true);
      final both = [_c(DateTime.utc(2026, 7, 24, 13), 4050, 3970)];
      expect(SignalEngine.resolveFromCandles(s, both)!.outcome,
          SignalOutcome.stopLoss);
    });
  });

  group('SignalController — one at a time', () {
    late SignalController c;
    late _MemStore store;

    setUp(() {
      store = _MemStore();
      c = SignalController(store: store);
    });

    test('issues a signal, then refuses a second while it runs', () async {
      expect(c.canIssue, isTrue);
      final first = await c.issue(_plan(long: true));
      expect(first, isNotNull);
      expect(c.active, isNotNull);
      expect(c.canIssue, isFalse);

      final second = await c.issue(_plan(long: false));
      expect(second, isNull); // the gate
      expect(c.signals, hasLength(1));
      expect(c.active!.plan.direction, TradeDirection.long);
    });

    test('price movement closes it and unlocks the next signal', () async {
      await c.issue(_plan(long: true));
      expect(c.onPrice(4010), isNull); // still running
      final closed = c.onPrice(4041);
      expect(closed, isNotNull);
      expect(closed!.outcome, SignalOutcome.takeProfit);
      expect(c.active, isNull);
      expect(c.canIssue, isTrue);
      expect(c.history, hasLength(1));
      expect(closed.rMultiple, closeTo(2.0, 1e-9)); // +2R

      final next = await c.issue(_plan(long: false));
      expect(next, isNotNull);
      expect(c.signals, hasLength(2));
    });

    test('reconcile settles from candles on launch', () async {
      await c.issue(_plan(long: true), now: DateTime.utc(2026, 7, 24, 12));
      final closed = c.reconcile([
        _c(DateTime.utc(2026, 7, 24, 13), 4005, 3975), // stop touched
      ]);
      expect(closed!.outcome, SignalOutcome.stopLoss);
      expect(closed.rMultiple, closeTo(-1.0, 1e-9));
      expect(c.canIssue, isTrue);
    });

    test('tracks the running result and persists across a reload', () async {
      await c.issue(_plan(long: true));
      expect(c.active!.unrealised(4015), 15);
      expect(c.active!.unrealised(3990), -10);

      final reloaded = SignalController(store: store);
      await reloaded.load();
      expect(reloaded.active, isNotNull);
      expect(reloaded.active!.plan.entry, 4000);
      expect(reloaded.active!.plan.tp1, 4040);
      expect(reloaded.canIssue, isFalse);
    });

    test('win/loss stats aggregate closed signals', () async {
      await c.issue(_plan(long: true));
      c.onPrice(4041); // +2R win
      await c.issue(_plan(long: true));
      c.onPrice(3975); // -1R loss
      expect(c.wins, 1);
      expect(c.losses, 1);
      expect(c.totalR, closeTo(1.0, 1e-9));
    });
  });
}
