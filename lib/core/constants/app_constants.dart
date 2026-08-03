/// App-wide constants for Gold Master Pro.
class AppConstants {
  AppConstants._();

  static const String appName = 'Gold Master Pro';
  static const String symbol = 'XAUUSD';

  /// Shown on the About screen. Keep in step with `version:` in pubspec.yaml.
  static const String appVersion = '1.1.3';

  /// Credited on the About screen.
  static const String author = 'Luan Rohm';

  /// Chart timeframes offered across the app (spec: Chart screen).
  static const List<String> timeframes = [
    'M5',
    'M15',
    'M30',
    'H1',
    'H4',
    'D1',
    'W1',
  ];
}
