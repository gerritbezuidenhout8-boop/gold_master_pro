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

/// The worked example: buy 4020, stop 4000 (1R = 20), target 4100.
TradePlan _trailPlan({bool long = true}) => TradePlan(
      direction: long ? TradeDirection.long : TradeDirection.short,
      score: long ? 85 : 15,
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

TradeSignal _trailSignal({bool long = true}) => TradeSignal(
      id: 't1',
      plan: _trailPlan(long: long),
      openedAt: DateTime.utc(2026, 7, 24, 12),
    );

void main() {
  group('trailing stop', () {
    test('trails 1.5R behind the high water mark', () {
      var s = _trailSignal(); // risk 20, so the trail sits 30 behind
      // At entry the plan's own stop is still in force.
      expect(s.trailingStop, 4000);
      expect(s.isTrailing, isFalse);

      s = s.withPeak(4040);
      expect(s.trailingStop, 4010);

      s = s.withPeak(4060);
      expect(s.trailingStop, 4030);
      expect(s.isTrailing, isTrue);
    });

    test('never retreats when price falls back', () {
      final s = _trailSignal().withPeak(4060).withPeak(4020);
      expect(s.peak, 4060);
      expect(s.trailingStop, 4030);
    });

    test('a pullback into the trail closes in profit', () {
      final s = _trailSignal().withPeak(4060); // stop ratcheted to 4030
      final r = SignalEngine.resolve(s, 4030)!;
      expect(r.outcome, SignalOutcome.trailingStop);
      expect(r.exitPrice, 4030);

      final closed = s.close(
          outcome: r.outcome, exitPrice: r.exitPrice, at: DateTime.utc(2026));
      expect(closed.realised, 10); // 4030 - 4020
      expect(closed.rMultiple, 0.5);
      expect(closed.isWin, isTrue);
    });

    test('before the trail engages it is still an ordinary stop loss', () {
      final s = _trailSignal().withPeak(4010);
      expect(s.trailingStop, 4000);
      final r = SignalEngine.resolve(s, 4000)!;
      expect(r.outcome, SignalOutcome.stopLoss);
      expect(r.exitPrice, 4000);
      expect(s.close(outcome: r.outcome, exitPrice: 4000, at: DateTime.utc(2026)).isWin,
          isFalse);
    });

    test('short mirrors the trail', () {
      var s = _trailSignal(long: false);
      expect(s.trailingStop, 4040);
      s = s.withPeak(4000);
      expect(s.trailingStop, 4030);
      s = s.withPeak(3980);
      expect(s.trailingStop, 4010);

      final r = SignalEngine.resolve(s, 4010)!;
      expect(r.outcome, SignalOutcome.trailingStop);
      expect(r.exitPrice, 4010);
    });

    test('replayed candles trail, then stop out in profit', () {
      final open = _trailSignal();
      final r = SignalEngine.resolveFromCandles(open, [
        // Runs up without touching the 4100 target: peak becomes 4060.
        _c(DateTime.utc(2026, 7, 24, 13), 4060, 4030),
        // Comes back into the ratcheted 4030 stop.
        _c(DateTime.utc(2026, 7, 24, 14), 4050, 4030),
      ])!;
      expect(r.outcome, SignalOutcome.trailingStop);
      expect(r.exitPrice, 4030);
      expect(r.at, DateTime.utc(2026, 7, 24, 14));
    });

    test('a bar making the high and returning books the pre-bar stop', () {
      // Intrabar order is unknowable, so the bar's own new high must not be
      // credited with lifting the stop before price came back to it.
      final r = SignalEngine.resolveFromCandles(_trailSignal(), [
        _c(DateTime.utc(2026, 7, 24, 13), 4090, 4000),
      ])!;
      expect(r.outcome, SignalOutcome.stopLoss);
      expect(r.exitPrice, 4000);
    });

    test('controller keeps the ratchet and counts a trailing exit as a win',
        () async {
      final store = _MemStore();
      final c = SignalController(store: store);
      await c.load();
      await c.issue(_trailPlan());

      expect(c.onPrice(4060), isNull); // ratchets, does not close
      expect(c.active!.peak, 4060);
      expect(c.active!.trailingStop, 4030);
      expect(store.data.single.peak, 4060, reason: 'the ratchet is persisted');

      final closed = c.onPrice(4030)!;
      expect(closed.outcome, SignalOutcome.trailingStop);
      expect(closed.exitPrice, 4030);
      expect(c.wins, 1);
      expect(c.losses, 0);
      expect(c.totalR, closeTo(0.5, 1e-9));
    });
  });

  group('the bar the trade opened inside still counts', () {
    // The reported trade: BUY 4391, stop 4359, target 4438. Gold ran to 4450
    // and the signal never closed.
    TradePlan reported() => TradePlan(
          direction: TradeDirection.long,
          score: 88,
          confidence: 70,
          entry: 4391,
          entryLow: 4389,
          entryHigh: 4393,
          stop: 4359,
          tp1: 4438,
          tp2: 4470,
          risk: 32,
          rr1: 1.47,
          rr2: 2.47,
          validUntil: DateTime.utc(2026, 8, 12),
          rationale: const ['test'],
        );

    // Issued at 10:20, i.e. twenty minutes into the 10:00 H1 bar.
    TradeSignal reportedSignal() => TradeSignal(
          id: 'r1',
          plan: reported(),
          openedAt: DateTime.utc(2026, 8, 11, 10, 20),
        );

    List<Candle> hourly() => [
          // Earlier bar, entirely before entry: must stay ignored.
          Candle(
              time: DateTime.utc(2026, 8, 11, 9),
              open: 4380,
              high: 4500, // even a huge high here must not settle the trade
              low: 4300,
              close: 4391),
          // The bar the trade opened inside — gold runs to 4450.
          Candle(
              time: DateTime.utc(2026, 8, 11, 10),
              open: 4391,
              high: 4450,
              low: 4385,
              close: 4442),
        ];

    test('closes at the target instead of running forever', () {
      final r = SignalEngine.resolveFromCandles(reportedSignal(), hourly())!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.exitPrice, 4438, reason: 'booked at the level, not 4450');
      expect(r.at, DateTime.utc(2026, 8, 11, 10));
    });

    test('a bar wholly before entry is still ignored', () {
      // Only the 09:00 bar, which ended before the trade opened.
      final r = SignalEngine.resolveFromCandles(reportedSignal(), [
        Candle(
            time: DateTime.utc(2026, 8, 11, 9),
            open: 4380,
            high: 4500,
            low: 4300,
            close: 4391),
        // A second bar establishes the 1h interval but does nothing itself.
        Candle(
            time: DateTime.utc(2026, 8, 11, 10),
            open: 4391,
            high: 4400,
            low: 4385,
            close: 4395),
      ]);
      expect(r, isNull);
    });

    test('a live tick through the target also closes at the level', () {
      // If the app is running, the quote path must catch it too: at 4450 the
      // 1.5R trail sits at 4402, so nothing stops it out first.
      final s = reportedSignal().withPeak(4450);
      expect(s.trailingStop, 4402);
      final r = SignalEngine.resolve(s, 4450)!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.exitPrice, 4438);
    });

    test('the interval is inferred from the series', () {
      expect(SignalEngine.inferBarInterval(hourly()), const Duration(hours: 1));
      expect(SignalEngine.inferBarInterval(const []), isNull);
    });
  });

  group('the target is taken on touch', () {
    test('a quote exactly at the target closes it', () {
      final s = _trailSignal(); // tp1 4100
      final r = SignalEngine.resolve(s, 4100)!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.exitPrice, 4100);
      // A hair below is still running.
      expect(SignalEngine.resolve(s, 4099.99), isNull);
    });

    test('a bar whose high exactly reaches the target closes it', () {
      final r = SignalEngine.resolveFromCandles(_trailSignal(), [
        _c(DateTime.utc(2026, 7, 24, 13), 4100, 4050),
      ])!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.exitPrice, 4100);
    });

    test('short: touching the target from above closes it', () {
      final s = _trailSignal(long: false); // tp1 3940
      expect(SignalEngine.resolve(s, 3940)!.outcome, SignalOutcome.takeProfit);
      expect(
          SignalEngine.resolveFromCandles(s, [
            _c(DateTime.utc(2026, 7, 24, 13), 4010, 3940),
          ])!.outcome,
          SignalOutcome.takeProfit);
    });

    test('where the candle closes is irrelevant — only the touch counts', () {
      // Wick straight through the target and close well back below it. The
      // target was reached, so the trade is taken there.
      final r = SignalEngine.resolveFromCandles(_trailSignal(), [
        Candle(
          time: DateTime.utc(2026, 7, 24, 13),
          open: 4025,
          high: 4140, // through tp1 4100
          low: 4020,
          close: 4030, // closes nowhere near it
        ),
      ])!;
      expect(r.outcome, SignalOutcome.takeProfit);
      expect(r.exitPrice, 4100);
    });

    test('a bar touching both levels still counts as the stop', () {
      // Deliberate and unchanged: intrabar order is unknowable, so the
      // conservative reading stands rather than flattering the record.
      final r = SignalEngine.resolveFromCandles(_trailSignal(), [
        _c(DateTime.utc(2026, 7, 24, 13), 4100, 4000),
      ])!;
      expect(r.outcome, SignalOutcome.stopLoss);
    });
  });

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
