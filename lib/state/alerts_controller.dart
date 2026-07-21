import 'package:flutter/foundation.dart';

import '../alerts/alert_engine.dart';
import '../models/alert_rule.dart';
import '../services/alert_store.dart';

/// App-wide alert state. A plain [ChangeNotifier] singleton — the first
/// genuinely cross-screen state (the app-level watcher feeds prices in;
/// the Alerts screen renders the list) — kept deliberately dependency-free
/// rather than pulling in a state-management package.
class AlertsController extends ChangeNotifier {
  AlertsController({AlertStore? store})
      : _store = store ?? AlertStore.instance;

  static AlertsController instance = AlertsController();

  final AlertStore _store;
  List<AlertRule> _rules = [];
  double? _lastPrice;
  bool _loaded = false;

  List<AlertRule> get rules => List.unmodifiable(_rules);
  double? get lastPrice => _lastPrice;
  bool get loaded => _loaded;

  Future<void> load() async {
    _rules = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() => _store.save(_rules);

  Future<void> upsert(AlertRule rule) async {
    final i = _rules.indexWhere((r) => r.id == rule.id);
    if (i >= 0) {
      _rules[i] = rule;
    } else {
      _rules.insert(0, rule);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _rules.removeWhere((r) => r.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final i = _rules.indexWhere((r) => r.id == id);
    if (i < 0) return;
    _rules[i] = _rules[i].copyWith(enabled: enabled);
    notifyListeners();
    await _persist();
  }

  Future<void> rearm(String id) async {
    final i = _rules.indexWhere((r) => r.id == id);
    if (i < 0) return;
    _rules[i] = _rules[i].copyWith(enabled: true, clearTriggered: true);
    notifyListeners();
    await _persist();
  }

  /// Feed the latest price; returns the rules that fired on this move so
  /// the caller can surface an in-app notification.
  List<AlertRule> onPrice(double price) {
    final prev = _lastPrice;
    _lastPrice = price;
    if (prev == null) return const [];

    final fired = <AlertRule>[];
    for (var i = 0; i < _rules.length; i++) {
      if (AlertEngine.fires(_rules[i], prev, price)) {
        _rules[i] = _rules[i].copyWith(triggeredAt: DateTime.now().toUtc());
        fired.add(_rules[i]);
      }
    }
    if (fired.isNotEmpty) {
      notifyListeners();
      _persist();
    }
    return fired;
  }
}
