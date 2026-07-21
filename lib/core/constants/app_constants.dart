/// App-wide constants for Gold Master Pro.
class AppConstants {
  AppConstants._();

  static const String appName = 'Gold Master Pro';
  static const String symbol = 'XAUUSD';

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
