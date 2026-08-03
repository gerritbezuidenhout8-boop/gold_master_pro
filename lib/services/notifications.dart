import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// One notification GMP wants to put in front of the user.
@immutable
class GmpNotification {
  const GmpNotification({
    required this.id,
    required this.title,
    required this.body,
  });

  /// Stable per-kind id so a newer notification of the same kind replaces
  /// the older one instead of stacking up.
  final int id;
  final String title;
  final String body;

  @override
  String toString() => 'GmpNotification($id, $title, $body)';
}

/// Notification ids, kept in one place so they never collide.
class GmpNotificationIds {
  GmpNotificationIds._();

  /// A new trade plan was issued.
  static const int signal = 1001;

  /// The running signal reached its take-profit or stop.
  static const int signalClosed = 1002;

  /// A price-crossing alert rule fired.
  static const int priceAlert = 1003;
}

/// Where notifications go.
///
/// Swappable like [MarketData] so tests (and platforms without a
/// notification story) never touch a platform channel: the default is the
/// no-op, and `main()` installs the real one.
abstract class Notifications {
  static Notifications instance = const NoopNotifications();

  /// Prepares the platform channel. Safe to call more than once.
  Future<void> init();

  /// Asks the OS for permission to post notifications. Returns false when
  /// the user declined or the platform can't grant it.
  Future<bool> requestPermission();

  /// Posts [notification]. Never throws — a failed notification must not
  /// take down the price stream that triggered it.
  Future<void> show(GmpNotification notification);
}

/// Drops everything. The default, so unit tests and unsupported platforms
/// degrade to the in-app SnackBar rather than crashing.
class NoopNotifications implements Notifications {
  const NoopNotifications();

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> show(GmpNotification notification) async {}
}

/// Records instead of showing — for tests.
class RecordingNotifications implements Notifications {
  final List<GmpNotification> shown = <GmpNotification>[];
  bool granted = true;
  int initCalls = 0;
  int permissionRequests = 0;

  @override
  Future<void> init() async => initCalls++;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> show(GmpNotification notification) async =>
      shown.add(notification);
}

/// Real OS notifications via `flutter_local_notifications`.
///
/// These are *local* notifications: they fire from the running app, so they
/// arrive whether or not GMP is the foreground app, but not once the OS has
/// killed the process. Delivery with the app fully closed needs the server
/// path in docs/alerts_backend.md.
class LocalNotifications implements Notifications {
  LocalNotifications({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Android channel. Registered up-front so the user can tune it in the
  /// system settings before the first signal ever arrives.
  static const AndroidNotificationChannel signalsChannel =
      AndroidNotificationChannel(
    'gmp_signals',
    'Trade signals',
    description: 'High-conviction Gold Master Score setups and price alerts.',
    importance: Importance.high,
  );

  /// The platforms this app actually configures. Elsewhere (web, Linux)
  /// init is skipped and every call is a no-op.
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  Future<void> init() async {
    if (_ready || !_supported) return;
    const darwin = DarwinInitializationSettings(
      // Asked for explicitly in requestPermission() instead, so the prompt
      // appears when the user turns Signal Alerts on rather than at launch.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwin,
      macOS: darwin,
      windows: WindowsInitializationSettings(
        appName: 'Gold Master Pro',
        appUserModelId: 'com.goldmasterpro.gold_master_pro',
        guid: 'f2b8c1e4-6d3a-4b7f-9c15-2a8e5d0b7c34',
      ),
    );
    try {
      await _plugin.initialize(settings: settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(signalsChannel);
      _ready = true;
    } on Exception catch (e) {
      debugPrint('GMP notifications unavailable: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();
    if (!_ready) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      // Windows toasts need no runtime grant.
      return true;
    } on Exception catch (e) {
      debugPrint('GMP notification permission failed: $e');
      return false;
    }
  }

  @override
  Future<void> show(GmpNotification notification) async {
    if (!_supported) return;
    await init();
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'gmp_signals',
        'Trade signals',
        channelDescription:
            'High-conviction Gold Master Score setups and price alerts.',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Gold Master Pro',
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      // Windows needs no per-notification detail; a plain toast is right.
    );
    try {
      await _plugin.show(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        notificationDetails: details,
      );
    } on Exception catch (e) {
      debugPrint('GMP notification failed: $e');
    }
  }
}
