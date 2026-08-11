import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/ai/trade_plan_engine.dart';
import 'package:gold_master_pro/models/trade_signal.dart';
import 'package:gold_master_pro/services/signal_store.dart';

/// Exercises the *real* store. Every other test in the suite substitutes an
/// in-memory fake, so without this file `LocalSignalStore` — the thing that
/// actually holds the running trade across restarts — is never run.
const String _key = 'gmp-signals-v1';

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
      rationale: const ['test'],
    );

TradeSignal _signal({bool long = true}) => TradeSignal(
      id: 's1',
      plan: _plan(long: long),
      openedAt: DateTime.utc(2026, 7, 24, 12),
    );

/// Seeds the prefs blob directly, standing in for whatever a previous
/// version — or a half-finished write — left on disk.
void _seed(String raw) => SharedPreferences.setMockInitialValues({_key: raw});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty store loads an empty list', () async {
    expect(await LocalSignalStore().load(), isEmpty);
  });

  test('save/load round trip keeps the running signal and its plan', () async {
    final store = LocalSignalStore();
    await store.save([_signal().withPeak(4060)]);

    final back = await store.load();
    expect(back, hasLength(1));
    final s = back.single;
    expect(s.id, 's1');
    expect(s.isOpen, isTrue);
    expect(s.peak, 4060);
    // The plan is stored by value, so a reloaded signal keeps the exact
    // levels it was judged on.
    expect(s.plan.entry, 4020);
    expect(s.plan.stop, 4000);
    expect(s.plan.tp1, 4100);
    expect(s.plan.direction, TradeDirection.long);
  });

  test('a closed signal round trips its outcome and exit', () async {
    final store = LocalSignalStore();
    await store.save([
      _signal().withPeak(4060).close(
            outcome: SignalOutcome.trailingStop,
            exitPrice: 4030,
            at: DateTime.utc(2026, 7, 24, 15),
          ),
    ]);

    final s = (await store.load()).single;
    expect(s.isOpen, isFalse);
    expect(s.outcome, SignalOutcome.trailingStop);
    expect(s.exitPrice, 4030);
    expect(s.closedAt, DateTime.utc(2026, 7, 24, 15));
    expect(s.isWin, isTrue); // closed above entry, so it is money won
  });

  group('a corrupt record never blocks the app', () {
    // The two type-error cases below used to escape the old `on Exception`
    // catch and crash every launch, with no in-app way to clear the blob.
    // The FormatException cases were already handled — they are here so the
    // whole corruption surface is pinned, not just the half that broke.

    test('malformed JSON yields an empty list', () async {
      _seed('not json at all');
      expect(await LocalSignalStore().load(), isEmpty);
    });

    test('a stored object instead of a list yields an empty list', () async {
      // `jsonDecode(raw) as List` throws a TypeError here, not an Exception.
      _seed('{"id":"s1"}');
      expect(await LocalSignalStore().load(), isEmpty);
    });

    test('a record with a wrong-typed field yields an empty list', () async {
      _seed(jsonEncode([
        {..._signal().toMap(), 'id': 42} // id must be a String
      ]));
      expect(await LocalSignalStore().load(), isEmpty);
    });

    test('a record missing its plan yields an empty list', () async {
      final m = _signal().toMap()..remove('plan');
      _seed(jsonEncode([m]));
      expect(await LocalSignalStore().load(), isEmpty);
    });

    test('an unparseable timestamp yields an empty list', () async {
      _seed(jsonEncode([
        {..._signal().toMap(), 'openedAt': 'the day before yesterday'}
      ]));
      expect(await LocalSignalStore().load(), isEmpty);
    });
  });

  test('an unknown outcome name loads as a running signal', () async {
    // Forward compatibility: a future build adding a fourth outcome must not
    // brick this one. `fromMap` maps anything unrecognised to null, which
    // reads as still-running rather than throwing.
    _seed(jsonEncode([
      {..._signal().toMap(), 'outcome': 'someFutureOutcome'}
    ]));
    final s = (await LocalSignalStore().load()).single;
    expect(s.isOpen, isTrue);
  });
}
