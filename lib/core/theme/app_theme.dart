import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary    = Color(0xFF1565C0);
  static const Color secondary  = Color(0xFF0288D1);
  static const Color success    = Color(0xFF2E7D32);
  static const Color warning    = Color(0xFFF57F17);
  static const Color danger     = Color(0xFFC62828);
  static const Color background = Color(0xFFF4F6FA);

  // ── helpers ──────────────────────────────────────────────────────────────────

  /// Returns a slightly darkened version of [color] (reduced lightness by [amount]).
  static Color _darken(Color color, [double amount = 0.08]) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  // ── dynamic factories ─────────────────────────────────────────────────────────

  /// Light theme using the given [seedColor].
  static ThemeData lightWith(Color seedColor) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light),
        scaffoldBackgroundColor: background,
        appBarTheme: AppBarTheme(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: seedColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(seedColor.withAlpha(25)),
          dataRowMaxHeight: 52,
        ),
      );

  /// Dark theme using the given [seedColor].
  static ThemeData darkWith(Color seedColor) {
    final darkAppBar = _darken(seedColor, 0.12);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: AppBarTheme(
        backgroundColor: darkAppBar,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      // Inputs: dark fill so text is readable
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: false,
      ),
      // Elevated buttons: use seed color so they stand out on dark surface
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: Colors.white,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(seedColor.withAlpha(40)),
        dataRowMaxHeight: 52,
      ),
    );
  }

  // ── static getters (kept for any direct reference, delegate to factories) ─────

  static ThemeData get light => lightWith(primary);
  static ThemeData get dark  => darkWith(primary);
}
