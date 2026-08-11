import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/trade_plan_engine.dart';
import 'package:gold_master_pro/models/trade_signal.dart';

/// The serialization contract for the type that persists money-relevant
/// state. `JournalEntry` had a round-trip test; `TradeSignal` — which carries
/// the running trade, its ratcheted peak and a plan snapshot by value — did
/// not, despite being the one that has to survive an app restart mid-trade.
TradePlan _plan({bool long = true}) => TradePlan(
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
      rationale: const ['trend up', 'above PDH'],
    );

TradeSignal _signal({bool long = true}) => TradeSignal(
      id: 's1',
      plan: _plan(long: long),
      openedAt: DateTime.utc(2026, 7, 24, 12),
    );

TradeSignal _roundTrip(TradeSignal s) => TradeSignal.fromMap(s.toMap());

void main() {
  group('round trip', () {
    test('a running signal survives with its plan intact', () {
      final back = _roundTrip(_signal());

      expect(back.id, 's1');
      expect(back.openedAt, DateTime.utc(2026, 7, 24, 12));
      expect(back.isOpen, isTrue);
      expect(back.outcome, isNull);
      expect(back.exitPrice, isNull);
      expect(back.closedAt, isNull);

      // The plan is stored by value — every level it was judged on.
      expect(back.plan.direction, TradeDirection.long);
      expect(back.plan.score, 85);
      expect(back.plan.confidence, 70);
      expect(back.plan.entry, 4020);
      expect(back.plan.entryLow, 4018);
      expect(back.plan.entryHigh, 4022);
      expect(back.plan.stop, 4000);
      expect(back.plan.tp1, 4100);
      expect(back.plan.tp2, 4140);
      expect(back.plan.risk, 20);
      expect(back.plan.rr1, 4);
      expect(back.plan.rr2, 6);
      expect(back.plan.validUntil, DateTime.utc(2026, 7, 25));
      expect(back.plan.rationale, ['trend up', 'above PDH']);
    });

    test('a short signal keeps its direction', () {
      final back = _roundTrip(_signal(long: false));
      expect(back.plan.direction, TradeDirection.short);
      expect(back.isLong, isFalse);
      expect(back.plan.stop, 4040);
    });

    test('the ratcheted peak survives, so the trail resumes where it was', () {
      // The field is written as 'peak' and read back as `recordedPeak`; a
      // rename on either side would silently reset every restored trail.
      final back = _roundTrip(_signal().withPeak(4075));
      expect(back.peak, 4075);
      expect(back.trailingStop, 4075 - 20 * TradePlanEngine.trailRiskMultiple);
      expect(back.isTrailing, isTrue);
    });

    test('each outcome name maps back to itself', () {
      for (final outcome in SignalOutcome.values) {
        final closed = _signal().close(
          outcome: outcome,
          exitPrice: 4030,
          at: DateTime.utc(2026, 7, 24, 15),
        );
        final back = _roundTrip(closed);
        expect(back.outcome, outcome, reason: 'outcome ${outcome.name}');
        expect(back.exitPrice, 4030);
        expect(back.closedAt, DateTime.utc(2026, 7, 24, 15));
        expect(back.isOpen, isFalse);
      }
    });

    test('a closed signal keeps the result it was scored on', () {
      final closed = _signal().withPeak(4060).close(
            outcome: SignalOutcome.trailingStop,
            exitPrice: 4030,
            at: DateTime.utc(2026, 7, 24, 15),
          );
      final back = _roundTrip(closed);
      expect(back.realised, 10);
      expect(back.rMultiple, closeTo(0.5, 1e-9));
      // Judged on money, not on which level was hit: a trailing stop that
      // closed above entry is a win.
      expect(back.isWin, isTrue);
    });

    test('timestamps come back in UTC', () {
      final back = _roundTrip(_signal());
      expect(back.openedAt.isUtc, isTrue);
    });
  });

  group('signals stored before trailing existed (pre-v1.1.4)', () {
    // Compatibility path called out in the model: a stored record with no
    // 'peak' key must load and simply restart its trail from entry.
    Map<String, dynamic> legacy() => _signal().toMap()..remove('peak');

    test('a missing peak falls back to entry rather than throwing', () {
      final back = TradeSignal.fromMap(legacy());
      expect(back.recordedPeak, isNull);
      expect(back.peak, back.plan.entry);
    });

    test('the stop starts at the plan stop, not somewhere below it', () {
      final back = TradeSignal.fromMap(legacy());
      expect(back.trailingStop, back.plan.stop);
      expect(back.isTrailing, isFalse);
    });

    test('it ratchets normally from there', () {
      final back = TradeSignal.fromMap(legacy()).withPeak(4070);
      expect(back.peak, 4070);
      expect(back.trailingStop, greaterThan(back.plan.stop));
    });
  });

  test('toMap always writes a peak, so a re-read never has a null one', () {
    // `toMap` serializes the `peak` getter, which defaults to entry. A signal
    // that never ratcheted therefore comes back with recordedPeak == entry
    // rather than null. Behaviourally identical — pinned so the asymmetry
    // between the written and read field stays deliberate.
    final fresh = _signal();
    expect(fresh.recordedPeak, isNull);
    expect(fresh.toMap()['peak'], fresh.plan.entry);

    final back = _roundTrip(fresh);
    expect(back.recordedPeak, fresh.plan.entry);
    expect(back.peak, fresh.peak);
    expect(back.trailingStop, fresh.trailingStop);
  });
}
