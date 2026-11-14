import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

/// Mobile feed palette, scoped to the home so other workflows keep their theme.
abstract final class DashboardTheme {
  static ThemeData of(BuildContext context) {
    final theme = Theme.of(context);
    final baseTokens = theme.extension<AppColorTokens>();
    if (baseTokens == null) return theme;
    final dark = theme.brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF7025C9),
          brightness: theme.brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primaryContainer: dark
              ? const Color(0xFF38234C)
              : const Color(0xFFF0E5FF),
          onPrimaryContainer: dark
              ? const Color(0xFFF0E5FF)
              : const Color(0xFF321451),
        );
    final brand = AppTonePalette(
      base: scheme.primary,
      onBase: scheme.onPrimary,
      surface: scheme.primaryContainer,
      onSurface: scheme.onPrimaryContainer,
      border: scheme.primary.withValues(alpha: 0.24),
    );
    final colors = baseTokens.copyWith(
      pageBackground: dark ? const Color(0xFF17131E) : const Color(0xFFF7F4FC),
      cardBackground: dark ? const Color(0xFF241D2E) : Colors.white,
      sectionBackground: scheme.surfaceContainerLow,
      raisedBackground: scheme.surfaceContainerHigh,
      sunkenBackground: scheme.surfaceContainerHighest,
      outlineSoft: scheme.outlineVariant,
      brand: brand,
      sales: brand,
      selection: brand,
      interactive: context.appColors.interactive.copyWith(
        onSurface: scheme.onSurfaceVariant,
      ),
    );
    return theme.copyWith(
      colorScheme: scheme,
      textTheme: theme.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      scaffoldBackgroundColor: colors.pageBackground,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: colors.pageBackground,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        backgroundColor: colors.cardBackground,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => theme.textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      extensions: [
        ...theme.extensions.values.where((value) => value is! AppColorTokens),
        colors,
      ],
    );
  }
}
