import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to a 5 second interval', () {
    expect(AppSettings.instance.autoRefreshSeconds.value, 5);
  });

  test('setAutoRefresh updates the notifier and persists', () async {
    await AppSettings.instance.setAutoRefresh(30);
    expect(AppSettings.instance.autoRefreshSeconds.value, 30);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('gmp-auto-refresh-seconds'), 30);

    // A fresh load reads it back.
    AppSettings.instance.autoRefreshSeconds.value = 5;
    await AppSettings.instance.load();
    expect(AppSettings.instance.autoRefreshSeconds.value, 30);

    // Reset for other tests using the singleton.
    await AppSettings.instance.setAutoRefresh(5);
  });

  test('ignores non-positive intervals', () async {
    await AppSettings.instance.setAutoRefresh(5);
    await AppSettings.instance.setAutoRefresh(0);
    expect(AppSettings.instance.autoRefreshSeconds.value, 5);
  });
}
