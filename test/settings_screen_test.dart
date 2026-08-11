import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/screens/settings/settings_screen.dart';
import 'package:gold_master_pro/services/app_settings.dart';
import 'package:gold_master_pro/services/notifications.dart';

/// The Settings toggles are the only place a user can turn alerts back *on*,
/// and on Android 13+ a toggle that flips without asking for
/// POST_NOTIFICATIONS leaves alerts silently going nowhere while the in-app
/// SnackBar still appears — the v1.1.3 regression. `_grant` is the guard:
/// prompt on off→on, never on on→off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Notifications realNotifications;
  late RecordingNotifications notes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    realNotifications = Notifications.instance;
    notes = RecordingNotifications();
    Notifications.instance = notes;
  });

  tearDown(() async {
    Notifications.instance = realNotifications;
    // AppSettings is a true singleton (no injectable seam), so restore the
    // shipped defaults rather than leaking state into the next test.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  /// The list scrolls, so bring the row into view before tapping it.
  Future<void> toggle(WidgetTester tester, String label) async {
    final row = find.widgetWithText(SwitchListTile, label);
    await tester.scrollUntilVisible(row, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('renders the four notification toggles', (tester) async {
    await pump(tester);
    for (final label in [
      'Price Alerts',
      'Signal Alerts',
      'News Alerts',
      'Push Notifications',
    ]) {
      expect(find.widgetWithText(SwitchListTile, label), findsOneWidget);
    }
  });

  group('Price Alerts', () {
    testWidgets('turning it on asks the OS for permission and persists',
        (tester) async {
      await AppSettings.instance.setPriceAlerts(false);
      await pump(tester);

      await toggle(tester, 'Price Alerts');

      expect(notes.permissionRequests, 1);
      expect(AppSettings.instance.priceAlerts.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('gmp-price-alerts'), isTrue);
    });

    testWidgets('turning it off never prompts', (tester) async {
      await AppSettings.instance.setPriceAlerts(true);
      await pump(tester);

      await toggle(tester, 'Price Alerts');

      expect(notes.permissionRequests, 0);
      expect(AppSettings.instance.priceAlerts.value, isFalse);
    });

    testWidgets('the setting still flips when permission is declined',
        (tester) async {
      // A declined prompt must not strand the switch: the preference is the
      // user's intent, and AlertWatcher re-asks on the next launch.
      notes.granted = false;
      await AppSettings.instance.setPriceAlerts(false);
      await pump(tester);

      await toggle(tester, 'Price Alerts');

      expect(notes.permissionRequests, 1);
      expect(AppSettings.instance.priceAlerts.value, isTrue);
    });
  });

  group('Signal Alerts', () {
    testWidgets('turning it on asks the OS for permission and persists',
        (tester) async {
      await AppSettings.instance.setScoreAlerts(false);
      await pump(tester);

      await toggle(tester, 'Signal Alerts');

      expect(notes.permissionRequests, 1);
      expect(AppSettings.instance.scoreAlerts.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('gmp-score-alerts'), isTrue);
    });

    testWidgets('turning it off never prompts', (tester) async {
      await AppSettings.instance.setScoreAlerts(true);
      await pump(tester);

      await toggle(tester, 'Signal Alerts');

      expect(notes.permissionRequests, 0);
      expect(AppSettings.instance.scoreAlerts.value, isFalse);
    });
  });

  group('the backend-deferred toggles', () {
    // News and Push persist the choice but are delivered by the (deferred)
    // cloud backend, so they are deliberately not wrapped in `_grant` —
    // prompting for an OS permission they do not yet use would be a lie.

    testWidgets('News Alerts persists without prompting', (tester) async {
      await pump(tester);

      await toggle(tester, 'News Alerts');

      expect(notes.permissionRequests, 0);
      expect(AppSettings.instance.newsAlerts.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('gmp-news-alerts'), isTrue);
    });

    testWidgets('Push Notifications persists without prompting',
        (tester) async {
      await pump(tester);

      await toggle(tester, 'Push Notifications');

      expect(notes.permissionRequests, 0);
      expect(AppSettings.instance.pushNotifications.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('gmp-push-notifications'), isTrue);
    });
  });

  testWidgets('an off→on→off cycle prompts exactly once', (tester) async {
    await AppSettings.instance.setPriceAlerts(false);
    await pump(tester);

    await toggle(tester, 'Price Alerts');
    await toggle(tester, 'Price Alerts');

    expect(notes.permissionRequests, 1);
    expect(AppSettings.instance.priceAlerts.value, isFalse);
  });
}
