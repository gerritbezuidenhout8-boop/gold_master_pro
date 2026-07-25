import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trade_signal.dart';

/// Swappable signal persistence — local-first, like the journal and alerts.
/// Holds the running signal (if any) plus the closed history.
abstract class SignalStore {
  static SignalStore instance = LocalSignalStore();

  Future<List<TradeSignal>> load();
  Future<void> save(List<TradeSignal> signals);
}

class LocalSignalStore implements SignalStore {
  static const String _key = 'gmp-signals-v1';

  @override
  Future<List<TradeSignal>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list =
          (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      return [for (final m in list) TradeSignal.fromMap(m)];
    } on Exception {
      return []; // never let a bad record block the app
    }
  }

  @override
  Future<void> save(List<TradeSignal> signals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final s in signals) s.toMap()]));
  }
}
