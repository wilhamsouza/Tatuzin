import 'package:flutter/material.dart';

abstract final class OwnerTheme {
  static ThemeData light() {
    return _build(Brightness.light);
  }

  static ThemeData dark() {
    return _build(Brightness.dark);
  }

  static ThemeData _build(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF7025C9),
          brightness: brightness,
        ).copyWith(
          primary: brightness == Brightness.dark
              ? const Color(0xFFD1B6FF)
              : const Color(0xFF6526C7),
          onPrimary: brightness == Brightness.dark
              ? const Color(0xFF321451)
              : Colors.white,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'NotoSans',
    );
    final isDark = brightness == Brightness.dark;

    return base.copyWith(
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF17131E)
          : const Color(0xFFF7F5FC),
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? scheme.surfaceContainerLow : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerLow : scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? scheme.inverseSurface : scheme.onSurface,
        contentTextStyle: TextStyle(color: scheme.inversePrimary),
      ),
    );
  }
}
