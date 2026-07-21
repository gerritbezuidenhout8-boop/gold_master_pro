import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_rule.dart';

/// Swappable alert persistence — local-first like the journal. When the
/// background alert path is set up (docs/alerts_backend.md), the same
/// rules are also mirrored to a server store the Worker can read.
abstract class AlertStore {
  static AlertStore instance = LocalAlertStore();

  Future<List<AlertRule>> load();
  Future<void> save(List<AlertRule> rules);
}

class LocalAlertStore implements AlertStore {
  static const String _key = 'gmp-alerts-v1';

  @override
  Future<List<AlertRule>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    return [for (final m in list) AlertRule.fromMap(m)];
  }

  @override
  Future<void> save(List<AlertRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final r in rules) r.toMap()]));
  }
}
