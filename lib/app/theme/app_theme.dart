import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const primary = Color(0xFF7B5234);
  static const secondary = Color(0xFFA1714C);
  static const background = Color(0xFFFFFCF9);
  static const surface = Color(0xFFFFFEFC);
  static const onSurface = Color(0xFF2F241D);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFB7791F);

  static ThemeData light() {
    final seededScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    final colorScheme = seededScheme.copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFF3E6DA),
      onPrimaryContainer: const Color(0xFF4E2F1C),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFF6EADF),
      onSecondaryContainer: const Color(0xFF5A3922),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFBF7F2),
      surfaceContainer: const Color(0xFFF6EFE8),
      surfaceContainerHigh: const Color(0xFFF0E7DE),
      surfaceContainerHighest: const Color(0xFFE8DDD2),
      outline: const Color(0xFFD6C8BD),
      outlineVariant: const Color(0xFFE9DDD4),
      error: error,
      onError: Colors.white,
      errorContainer: const Color(0xFFFEE2E2),
      onErrorContainer: const Color(0xFF7F1D1D),
      tertiary: success,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFDCFCE7),
      onTertiaryContainer: const Color(0xFF166534),
      shadow: const Color(0xFF1F1B2D),
      scrim: const Color(0xFF111827),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: onSurface,
        height: 1.42,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: onSurface,
        height: 1.4,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        height: 1.32,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w600,
      ),
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return base.copyWith(
      textTheme: textTheme,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.surfaceContainerHigh,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
        actionsIconTheme: IconThemeData(color: colorScheme.primary),
        iconTheme: IconThemeData(color: colorScheme.primary),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: border,
        enabledBorder: border,
        disabledBorder: border.copyWith(
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.surfaceContainerHigh;
            }
            return colorScheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurfaceVariant;
            }
            return colorScheme.onPrimary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            return null;
          }),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.surfaceContainerHigh;
            }
            return colorScheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurfaceVariant;
            }
            return colorScheme.onPrimary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurfaceVariant;
            }
            return colorScheme.primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final borderColor = states.contains(WidgetState.disabled)
                ? colorScheme.outlineVariant.withValues(alpha: 0.6)
                : colorScheme.outlineVariant;
            return BorderSide(color: borderColor);
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primary.withValues(alpha: 0.06);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primaryContainer,
        secondarySelectedColor: colorScheme.primaryContainer,
        disabledColor: colorScheme.surfaceContainerHigh,
        labelStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: colorScheme.secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        iconColor: colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: colorScheme.outline),
      ),
    );
  }
}
