import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight app-wide preferences. Currently holds the live auto-refresh
/// interval used by data screens (the Markets watchlist). Persisted so the
/// choice survives restarts.
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  /// Options offered in the picker.
  static const List<int> autoRefreshOptions = [5, 10, 15, 30, 60];

  /// Seconds between automatic refreshes (default 5).
  final ValueNotifier<int> autoRefreshSeconds = ValueNotifier(5);

  static const String _key = 'gmp-auto-refresh-seconds';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null && v > 0) autoRefreshSeconds.value = v;
  }

  Future<void> setAutoRefresh(int seconds) async {
    if (seconds <= 0) return;
    autoRefreshSeconds.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, seconds);
  }
}
