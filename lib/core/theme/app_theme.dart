import 'package:flutter/material.dart';

/// Gold Master Pro visual identity: near-black surfaces, rich gold
/// accents, thin gold-tinted card borders, green/red for bull/bear.
class AppTheme {
  AppTheme._();

  // Brand palette (from the GMP design language).
  static const Color background = Color(0xFF0A0A0B);
  static const Color surface = Color(0xFF15140F);
  static const Color surfaceAlt = Color(0xFF1D1A12);
  static const Color gold = Color(0xFFE3B84C);
  static const Color goldBright = Color(0xFFF6D57A);
  static const Color goldDeep = Color(0xFF9E7B1E);
  static const Color bull = Color(0xFF25C685);
  static const Color bear = Color(0xFFE5484D);
  static const Color textPrimary = Color(0xFFF3F1EA);
  static const Color textSecondary = Color(0xFF8E8A7E);
  static const Color hairline = Color(0x29E3B84C); // gold @ ~16%

  /// Gold gradient used on primary buttons and accents.
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFF3D06A), Color(0xFFCB9A2E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Uppercase, letter-spaced gold section label.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 12,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: gold,
  );

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: gold,
      surface: surface,
      onSurface: textPrimary,
      outline: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
      ).apply(bodyColor: textPrimary, displayColor: textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        centerTitle: true,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D0C0A),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? gold
                  : textSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color:
                  states.contains(WidgetState.selected) ? gold : textSecondary,
            )),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: gold.withValues(alpha: 0.18),
        side: const BorderSide(color: hairline),
        labelStyle: const TextStyle(color: textPrimary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
