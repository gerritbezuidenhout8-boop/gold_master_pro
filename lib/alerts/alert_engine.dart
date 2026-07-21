import '../models/alert_rule.dart';

/// Pure crossing detector — the heart of the alert system, deliberately
/// free of any UI, storage or network so it is fully unit-testable and
/// reused verbatim by the background Cloudflare Worker (docs/alerts_backend.md).
class AlertEngine {
  AlertEngine._();

  /// Whether [rule] fires on a price move from [prev] to [next].
  ///
  /// Fires only on a genuine crossing (not merely "already past"), so an
  /// alert created while the condition is already true waits for the next
  /// real cross. A disarmed rule never fires.
  static bool fires(AlertRule rule, double prev, double next) {
    if (!rule.isArmed) return false;
    return switch (rule.kind) {
      AlertKind.priceAbove => prev < rule.threshold && next >= rule.threshold,
      AlertKind.priceBelow => prev > rule.threshold && next <= rule.threshold,
    };
  }
}
