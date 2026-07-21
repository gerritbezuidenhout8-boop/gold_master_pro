import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/alerts/alert_engine.dart';
import 'package:gold_master_pro/models/alert_rule.dart';

AlertRule _rule(AlertKind kind, double t,
        {bool enabled = true, DateTime? triggeredAt}) =>
    AlertRule(
        id: '1',
        kind: kind,
        threshold: t,
        enabled: enabled,
        triggeredAt: triggeredAt);

void main() {
  group('priceAbove', () {
    final r = _rule(AlertKind.priceAbove, 4000);
    test('fires only on an upward crossing', () {
      expect(AlertEngine.fires(r, 3990, 4010), isTrue);
      expect(AlertEngine.fires(r, 3990, 4000), isTrue); // touches exactly
    });
    test('does not fire without a crossing', () {
      expect(AlertEngine.fires(r, 4010, 4020), isFalse); // already above
      expect(AlertEngine.fires(r, 3990, 3995), isFalse); // still below
      expect(AlertEngine.fires(r, 4010, 3990), isFalse); // downward
    });
  });

  group('priceBelow', () {
    final r = _rule(AlertKind.priceBelow, 4000);
    test('fires only on a downward crossing', () {
      expect(AlertEngine.fires(r, 4010, 3990), isTrue);
      expect(AlertEngine.fires(r, 4010, 4000), isTrue);
    });
    test('does not fire without a crossing', () {
      expect(AlertEngine.fires(r, 3990, 3980), isFalse); // already below
      expect(AlertEngine.fires(r, 4010, 4005), isFalse); // still above
      expect(AlertEngine.fires(r, 3990, 4010), isFalse); // upward
    });
  });

  test('a disarmed rule never fires', () {
    expect(
        AlertEngine.fires(
            _rule(AlertKind.priceAbove, 4000, enabled: false), 3990, 4010),
        isFalse);
    expect(
        AlertEngine.fires(
            _rule(AlertKind.priceAbove, 4000,
                triggeredAt: DateTime.utc(2026)),
            3990,
            4010),
        isFalse);
  });
}
