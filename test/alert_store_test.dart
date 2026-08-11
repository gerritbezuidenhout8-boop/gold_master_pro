import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/models/alert_rule.dart';
import 'package:gold_master_pro/services/alert_store.dart';

/// Exercises the *real* store. The screen and controller tests all swap in an
/// in-memory fake, so `LocalAlertStore` was previously only ever loaded from
/// empty prefs — the parsing path had no coverage at all.
const String _key = 'gmp-alerts-v1';

void _seed(String raw) => SharedPreferences.setMockInitialValues({_key: raw});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty store loads an empty list', () async {
    expect(await LocalAlertStore().load(), isEmpty);
  });

  test('save/load round trip preserves both kinds and the armed state',
      () async {
    final store = LocalAlertStore();
    await store.save([
      AlertRule(
        id: 'a',
        kind: AlertKind.priceAbove,
        threshold: 4100,
        note: 'breakout',
        createdAt: DateTime.utc(2026, 7, 24, 9),
      ),
      AlertRule(
        id: 'b',
        kind: AlertKind.priceBelow,
        threshold: 3950,
        enabled: false,
        triggeredAt: DateTime.utc(2026, 7, 24, 11),
      ),
    ]);

    final back = await store.load();
    expect(back, hasLength(2));
    expect(back[0].kind, AlertKind.priceAbove);
    expect(back[0].threshold, 4100);
    expect(back[0].note, 'breakout');
    expect(back[0].isArmed, isTrue);
    expect(back[1].kind, AlertKind.priceBelow);
    expect(back[1].enabled, isFalse);
    expect(back[1].triggeredAt, DateTime.utc(2026, 7, 24, 11));
    expect(back[1].isArmed, isFalse); // disabled *and* already fired
  });

  group('a corrupt record never blocks the app', () {
    // `load` had no try/catch at all, so each of these crashed the launch.

    test('malformed JSON yields an empty list', () async {
      _seed('}{');
      expect(await LocalAlertStore().load(), isEmpty);
    });

    test('a stored object instead of a list yields an empty list', () async {
      _seed('{"id":"a"}');
      expect(await LocalAlertStore().load(), isEmpty);
    });

    test('an unknown alert kind yields an empty list', () async {
      // `AlertKind.values.byName` throws an ArgumentError — an Error, so the
      // catch has to be wider than `on Exception`.
      _seed(jsonEncode([
        {'id': 'a', 'kind': 'priceSideways', 'threshold': 4100}
      ]));
      expect(await LocalAlertStore().load(), isEmpty);
    });

    test('a missing threshold yields an empty list', () async {
      _seed(jsonEncode([
        {'id': 'a', 'kind': 'priceAbove'}
      ]));
      expect(await LocalAlertStore().load(), isEmpty);
    });
  });

  test('an unparseable timestamp degrades to null rather than throwing',
      () async {
    // `AlertRule._parse` uses tryParse, so a bad date leaves the rule armed
    // instead of losing it — worth pinning, it is the one lenient field.
    _seed(jsonEncode([
      {
        'id': 'a',
        'kind': 'priceAbove',
        'threshold': 4100,
        'triggeredAt': 'not a date',
      }
    ]));
    final rule = (await LocalAlertStore().load()).single;
    expect(rule.triggeredAt, isNull);
    expect(rule.isArmed, isTrue);
  });
}
