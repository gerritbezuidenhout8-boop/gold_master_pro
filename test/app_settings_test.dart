import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to a 1 second interval', () {
    expect(AppSettings.instance.autoRefreshSeconds.value, 1);
  });

  test('offers 1 second as the fastest option', () {
    expect(AppSettings.autoRefreshOptions.first, 1);
    expect(AppSettings.autoRefreshOptions, isNot(contains(0)));
  });

  test('a saved interval still wins over the new default', () async {
    SharedPreferences.setMockInitialValues({'gmp-auto-refresh-seconds': 30});
    AppSettings.instance.autoRefreshSeconds.value = 1;
    await AppSettings.instance.load();
    expect(AppSettings.instance.autoRefreshSeconds.value, 30);

    // Reset for other tests using the singleton.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.setAutoRefresh(1);
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

  test('setPriceAlerts persists and reloads', () async {
    await AppSettings.instance.setPriceAlerts(false);
    expect(AppSettings.instance.priceAlerts.value, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('gmp-price-alerts'), isFalse);

    // A fresh load reads it back.
    AppSettings.instance.priceAlerts.value = true;
    await AppSettings.instance.load();
    expect(AppSettings.instance.priceAlerts.value, isFalse);

    // Reset for other tests using the singleton.
    await AppSettings.instance.setPriceAlerts(true);
  });
}
