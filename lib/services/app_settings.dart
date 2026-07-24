import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight app-wide preferences: the live auto-refresh interval used by
/// data screens (the Markets watchlist) and the notification toggles. All
/// persisted so choices survive restarts.
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  /// Options offered in the picker.
  static const List<int> autoRefreshOptions = [5, 10, 15, 30, 60];

  /// Seconds between automatic refreshes (default 5).
  final ValueNotifier<int> autoRefreshSeconds = ValueNotifier(5);

  /// Master switch for in-app price-alert notifications (default on). The
  /// [AlertWatcher] consults this before firing a SnackBar.
  final ValueNotifier<bool> priceAlerts = ValueNotifier(true);

  /// Forward-looking toggles: persisted, but their delivery needs the
  /// (deferred) cloud backend — see docs/alerts_backend.md.
  final ValueNotifier<bool> scoreAlerts = ValueNotifier(false);
  final ValueNotifier<bool> newsAlerts = ValueNotifier(false);
  final ValueNotifier<bool> pushNotifications = ValueNotifier(false);

  /// Whether the one-time onboarding intro has been completed.
  final ValueNotifier<bool> onboardingComplete = ValueNotifier(false);

  static const String _key = 'gmp-auto-refresh-seconds';
  static const String _priceKey = 'gmp-price-alerts';
  static const String _scoreKey = 'gmp-score-alerts';
  static const String _newsKey = 'gmp-news-alerts';
  static const String _pushKey = 'gmp-push-notifications';
  static const String _onboardKey = 'gmp-onboarding-complete';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null && v > 0) autoRefreshSeconds.value = v;
    priceAlerts.value = prefs.getBool(_priceKey) ?? true;
    scoreAlerts.value = prefs.getBool(_scoreKey) ?? false;
    newsAlerts.value = prefs.getBool(_newsKey) ?? false;
    pushNotifications.value = prefs.getBool(_pushKey) ?? false;
    onboardingComplete.value = prefs.getBool(_onboardKey) ?? false;
  }

  Future<void> setAutoRefresh(int seconds) async {
    if (seconds <= 0) return;
    autoRefreshSeconds.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, seconds);
  }

  Future<void> setPriceAlerts(bool v) => _setBool(priceAlerts, _priceKey, v);
  Future<void> setScoreAlerts(bool v) => _setBool(scoreAlerts, _scoreKey, v);
  Future<void> setNewsAlerts(bool v) => _setBool(newsAlerts, _newsKey, v);
  Future<void> setPushNotifications(bool v) =>
      _setBool(pushNotifications, _pushKey, v);
  Future<void> setOnboardingComplete(bool v) =>
      _setBool(onboardingComplete, _onboardKey, v);

  Future<void> _setBool(ValueNotifier<bool> n, String key, bool v) async {
    n.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }
}
