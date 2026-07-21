import 'package:flutter/material.dart';

/// Gold Master Pro visual identity: dark surfaces with a gold accent.
class AppTheme {
  AppTheme._();

  static const Color gold = Color(0xFFD4AF37);
  static const Color goldBright = Color(0xFFF2CC5A);
  static const Color surfaceDark = Color(0xFF15130E);
  static const Color surfaceRaised = Color(0xFF1C1914);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
    ).copyWith(primary: gold, surface: surfaceDark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: goldBright,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceRaised,
        indicatorColor: gold.withValues(alpha: 0.22),
      ),
      cardTheme: const CardThemeData(
        color: surfaceRaised,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}
