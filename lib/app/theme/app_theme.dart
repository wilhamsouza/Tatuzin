import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

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

    const layoutTokens = AppLayoutTokens(
      radiusSm: 10,
      radiusMd: 12,
      radiusLg: 14,
      radiusXl: 16,
      radiusSheet: 24,
      radiusPill: 999,
      space2: 4,
      space3: 6,
      space4: 8,
      space5: 10,
      space6: 12,
      space7: 14,
      space8: 16,
      space9: 18,
      space10: 20,
      space11: 24,
      pagePadding: 16,
      pagePaddingCompact: 12,
      sectionGap: 14,
      blockGap: 12,
      gridGap: 10,
      iconSm: 16,
      iconMd: 18,
      iconLg: 20,
      inputHeight: 48,
      actionHeight: 48,
      compactActionHeight: 40,
      quickActionHeight: 44,
      cardPadding: 16,
      compactCardPadding: 12,
      headerPadding: 12,
      bottomBarPadding: 12,
      sheetPadding: 16,
      shadowBlur: 14,
      shadowOffsetY: 6,
    );

    final colorTokens = AppColorTokens(
      pageBackground: background,
      cardBackground: colorScheme.surface,
      sectionBackground: colorScheme.surfaceContainerLow,
      raisedBackground: colorScheme.surfaceContainer,
      sunkenBackground: colorScheme.surfaceContainerHighest,
      overlay: colorScheme.scrim.withValues(alpha: 0.42),
      outlineSoft: colorScheme.outlineVariant,
      outlineStrong: colorScheme.outline,
      shadowSoft: colorScheme.shadow.withValues(alpha: 0.08),
      brand: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.primaryContainer.withValues(alpha: 0.58),
        onSurface: colorScheme.onPrimaryContainer,
        border: colorScheme.primary.withValues(alpha: 0.14),
      ),
      info: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.primaryContainer.withValues(alpha: 0.52),
        onSurface: colorScheme.onPrimaryContainer,
        border: colorScheme.primary.withValues(alpha: 0.14),
      ),
      success: AppTonePalette(
        base: colorScheme.tertiary,
        onBase: colorScheme.onTertiary,
        surface: colorScheme.tertiaryContainer.withValues(alpha: 0.72),
        onSurface: colorScheme.onTertiaryContainer,
        border: colorScheme.tertiary.withValues(alpha: 0.18),
      ),
      warning: AppTonePalette(
        base: warning,
        onBase: Colors.white,
        surface: colorScheme.secondaryContainer.withValues(alpha: 0.72),
        onSurface: colorScheme.onSecondaryContainer,
        border: warning.withValues(alpha: 0.18),
      ),
      danger: AppTonePalette(
        base: colorScheme.error,
        onBase: colorScheme.onError,
        surface: colorScheme.errorContainer.withValues(alpha: 0.72),
        onSurface: colorScheme.onErrorContainer,
        border: colorScheme.error.withValues(alpha: 0.18),
      ),
      sales: const AppTonePalette(
        base: Color(0xFF8C6239),
        onBase: Colors.white,
        surface: Color(0xFFF4E6D8),
        onSurface: Color(0xFF5A3922),
        border: Color(0xFFD2B89D),
      ),
      cashflowPositive: const AppTonePalette(
        base: Color(0xFF166534),
        onBase: Colors.white,
        surface: Color(0xFFDCFCE7),
        onSurface: Color(0xFF166534),
        border: Color(0xFF86EFAC),
      ),
      cashflowNegative: const AppTonePalette(
        base: Color(0xFFB91C1C),
        onBase: Colors.white,
        surface: Color(0xFFFEE2E2),
        onSurface: Color(0xFF991B1B),
        border: Color(0xFFFCA5A5),
      ),
      stockLow: const AppTonePalette(
        base: Color(0xFF9A6700),
        onBase: Colors.white,
        surface: Color(0xFFFEF3C7),
        onSurface: Color(0xFF92400E),
        border: Color(0xFFF6C453),
      ),
      interactive: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.surfaceContainerLowest,
        onSurface: colorScheme.onSurface,
        border: colorScheme.outlineVariant,
      ),
      disabled: AppTonePalette(
        base: colorScheme.surfaceContainerHigh,
        onBase: colorScheme.onSurfaceVariant,
        surface: colorScheme.surfaceContainerHigh,
        onSurface: colorScheme.onSurfaceVariant,
        border: colorScheme.outlineVariant.withValues(alpha: 0.72),
      ),
      selection: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.primaryContainer.withValues(alpha: 0.4),
        onSurface: colorScheme.onPrimaryContainer,
        border: colorScheme.primary.withValues(alpha: 0.2),
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorTokens.pageBackground,
      extensions: <ThemeExtension<dynamic>>[colorTokens, layoutTokens],
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
      borderRadius: BorderRadius.circular(layoutTokens.radiusLg),
      borderSide: BorderSide(color: colorTokens.outlineSoft),
    );

    return base.copyWith(
      textTheme: textTheme,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.surfaceContainerHigh,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorTokens.pageBackground,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
        actionsIconTheme: IconThemeData(color: colorScheme.primary),
        iconTheme: IconThemeData(color: colorScheme.primary),
      ),
      cardTheme: CardThemeData(
        color: colorTokens.cardBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: colorTokens.shadowSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusXl),
          side: BorderSide(color: colorTokens.outlineSoft),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorTokens.outlineSoft,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorTokens.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusXl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorTokens.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(layoutTokens.radiusSheet),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorTokens.cardBackground,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: layoutTokens.space8,
          vertical: layoutTokens.space6,
        ),
        border: border,
        enabledBorder: border,
        disabledBorder: border.copyWith(
          borderSide: BorderSide(color: colorTokens.disabled.border),
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
          minimumSize: WidgetStatePropertyAll(
            Size.fromHeight(layoutTokens.actionHeight),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: layoutTokens.space8,
              vertical: layoutTokens.space6,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorTokens.disabled.base;
            }
            return colorScheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorTokens.disabled.onBase;
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
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(layoutTokens.radiusMd),
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.fromHeight(layoutTokens.actionHeight),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: layoutTokens.space8,
              vertical: layoutTokens.space6,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorTokens.disabled.base;
            }
            return colorScheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorTokens.disabled.onBase;
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
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(layoutTokens.radiusMd),
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.fromHeight(layoutTokens.actionHeight),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: layoutTokens.space8,
              vertical: layoutTokens.space6,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorTokens.disabled.onBase;
            }
            return colorScheme.primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final borderColor = states.contains(WidgetState.disabled)
                ? colorTokens.disabled.border
                : colorTokens.outlineSoft;
            return BorderSide(color: borderColor);
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primary.withValues(alpha: 0.06);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(layoutTokens.radiusMd),
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusLg),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorTokens.sectionBackground,
        selectedColor: colorTokens.selection.surface,
        secondarySelectedColor: colorTokens.selection.surface,
        disabledColor: colorTokens.disabled.surface,
        labelStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: textTheme.bodySmall?.copyWith(
          color: colorTokens.selection.onSurface,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusPill),
        ),
        side: BorderSide.none,
        padding: EdgeInsets.symmetric(
          horizontal: layoutTokens.space4,
          vertical: layoutTokens.space2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: colorScheme.secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusLg),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorTokens.selection.surface,
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
        contentPadding: EdgeInsets.symmetric(
          horizontal: layoutTokens.space7,
          vertical: 2,
        ),
        iconColor: colorScheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusMd),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.space3),
        ),
        side: BorderSide(color: colorScheme.outline),
      ),
    );
  }
}
