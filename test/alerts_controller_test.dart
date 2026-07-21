import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/alert_rule.dart';
import 'package:gold_master_pro/services/alert_store.dart';
import 'package:gold_master_pro/state/alerts_controller.dart';

class _MemStore implements AlertStore {
  List<AlertRule> data;
  int saves = 0;
  _MemStore([this.data = const []]);

  @override
  Future<List<AlertRule>> load() async => List.of(data);

  @override
  Future<void> save(List<AlertRule> rules) async {
    data = List.of(rules);
    saves++;
  }
}

AlertRule _rule(String id, AlertKind kind, double t) =>
    AlertRule(id: id, kind: kind, threshold: t);

void main() {
  test('first price only seeds; no crossing evaluated', () {
    final c = AlertsController(store: _MemStore());
    expect(c.onPrice(4000), isEmpty);
    expect(c.lastPrice, 4000);
  });

  test('fires a crossing rule, marks it triggered and persists', () async {
    final store = _MemStore();
    final c = AlertsController(store: store);
    await c.upsert(_rule('a', AlertKind.priceAbove, 4050));

    expect(c.onPrice(4040), isEmpty); // seed below
    final fired = c.onPrice(4060); // cross up
    expect(fired.map((r) => r.id), ['a']);
    expect(c.rules.single.triggeredAt, isNotNull);
    expect(c.rules.single.isArmed, isFalse);

    // Fired rules do not re-fire on further crossings.
    expect(c.onPrice(4040), isEmpty);
    expect(c.onPrice(4060), isEmpty);

    expect(store.data.single.triggeredAt, isNotNull); // persisted
  });

  test('re-arm clears the triggered state so it can fire again', () async {
    final c = AlertsController(store: _MemStore());
    await c.upsert(_rule('a', AlertKind.priceBelow, 4000));
    c.onPrice(4010);
    c.onPrice(3990); // fires
    expect(c.rules.single.isArmed, isFalse);

    await c.rearm('a');
    expect(c.rules.single.isArmed, isTrue);
    c.onPrice(4010);
    expect(c.onPrice(3990).map((r) => r.id), ['a']); // fires again
  });

  test('disabled rules are skipped', () async {
    final c = AlertsController(store: _MemStore());
    await c.upsert(_rule('a', AlertKind.priceAbove, 4050));
    await c.setEnabled('a', false);
    c.onPrice(4040);
    expect(c.onPrice(4060), isEmpty);
  });

  test('load pulls existing rules from the store', () async {
    final c = AlertsController(
        store: _MemStore([_rule('x', AlertKind.priceAbove, 4200)]));
    await c.load();
    expect(c.loaded, isTrue);
    expect(c.rules.single.id, 'x');
  });

  test('remove deletes a rule and persists', () async {
    final store = _MemStore();
    final c = AlertsController(store: store);
    await c.upsert(_rule('a', AlertKind.priceAbove, 4050));
    await c.remove('a');
    expect(c.rules, isEmpty);
    expect(store.data, isEmpty);
  });
}
