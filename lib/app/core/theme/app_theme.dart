import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_design_tokens.dart';

abstract final class AppTheme {
  static const primary = AppColors.primary;
  static const secondary = AppColors.primaryLight;
  static const background = AppColors.surface2;
  static const surface = AppColors.surface;
  static const onSurface = AppColors.text1;
  static const success = AppColors.success;
  static const error = AppColors.error;
  static const warning = AppColors.warning;

  static ThemeData dark() {
    final seededScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );

    const darkPage = Color(0xFF0F1110);
    const darkSurface = Color(0xFF121614);
    const darkCard = Color(0xFF1B211E);
    const darkRaised = Color(0xFF222B27);
    const darkSunken = Color(0xFF2B3732);
    const darkOutline = Color(0xFF40534C);
    const darkOutlineSoft = Color(0xFF293A34);
    const darkText = Color(0xFFE7F3EF);
    const darkTextMuted = Color(0xFFB5C8C1);

    final colorScheme = seededScheme.copyWith(
      primary: AppColors.primaryAccent,
      onPrimary: const Color(0xFF053126),
      primaryContainer: const Color(0xFF0B3D31),
      onPrimaryContainer: const Color(0xFFC8F5E7),
      secondary: AppColors.primaryLight,
      onSecondary: const Color(0xFF052D22),
      secondaryContainer: const Color(0xFF123B32),
      onSecondaryContainer: const Color(0xFFC9F2E4),
      surface: darkSurface,
      onSurface: darkText,
      onSurfaceVariant: darkTextMuted,
      surfaceContainerLowest: darkPage,
      surfaceContainerLow: const Color(0xFF151A18),
      surfaceContainer: darkCard,
      surfaceContainerHigh: darkRaised,
      surfaceContainerHighest: darkSunken,
      outline: darkOutline,
      outlineVariant: darkOutlineSoft,
      error: const Color(0xFFFF6B6B),
      onError: const Color(0xFF3F0505),
      errorContainer: const Color(0xFF4A1618),
      onErrorContainer: const Color(0xFFFFD8D8),
      tertiary: const Color(0xFF34D399),
      onTertiary: const Color(0xFF042D22),
      tertiaryContainer: const Color(0xFF0F3D31),
      onTertiaryContainer: const Color(0xFFC6F6E7),
      shadow: Colors.black,
      scrim: Colors.black,
    );

    const layoutTokens = AppLayoutTokens(
      radiusSm: 8,
      radiusMd: 12,
      radiusLg: 16,
      radiusXl: 20,
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
      pagePadding: 18,
      pagePaddingCompact: 12,
      sectionGap: 16,
      blockGap: 12,
      gridGap: 12,
      iconSm: 16,
      iconMd: 18,
      iconLg: 22,
      inputHeight: 48,
      actionHeight: 48,
      compactActionHeight: 40,
      quickActionHeight: 46,
      cardPadding: 16,
      compactCardPadding: 12,
      headerPadding: 16,
      bottomBarPadding: 12,
      sheetPadding: 16,
      shadowBlur: 18,
      shadowOffsetY: 8,
    );

    final colorTokens = AppColorTokens(
      pageBackground: darkPage,
      cardBackground: darkCard,
      sectionBackground: colorScheme.surfaceContainerLow,
      raisedBackground: colorScheme.surfaceContainerHigh,
      sunkenBackground: colorScheme.surfaceContainerHighest,
      overlay: colorScheme.scrim.withValues(alpha: 0.58),
      outlineSoft: colorScheme.outlineVariant,
      outlineStrong: colorScheme.outline,
      shadowSoft: Colors.black.withValues(alpha: 0.32),
      brand: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.primaryContainer,
        onSurface: colorScheme.onPrimaryContainer,
        border: const Color(0xFF176E59),
      ),
      info: const AppTonePalette(
        base: Color(0xFF60A5FA),
        onBase: Color(0xFF061B3A),
        surface: Color(0xFF102C4F),
        onSurface: Color(0xFFD8EAFE),
        border: Color(0xFF245C9A),
      ),
      success: AppTonePalette(
        base: colorScheme.tertiary,
        onBase: colorScheme.onTertiary,
        surface: colorScheme.tertiaryContainer,
        onSurface: colorScheme.onTertiaryContainer,
        border: const Color(0xFF1F7A5F),
      ),
      warning: const AppTonePalette(
        base: Color(0xFFFBBF24),
        onBase: Color(0xFF332000),
        surface: Color(0xFF3B2A0B),
        onSurface: Color(0xFFFFE8A3),
        border: Color(0xFF745510),
      ),
      danger: AppTonePalette(
        base: colorScheme.error,
        onBase: colorScheme.onError,
        surface: colorScheme.errorContainer,
        onSurface: colorScheme.onErrorContainer,
        border: const Color(0xFF8B2F35),
      ),
      sales: const AppTonePalette(
        base: Color(0xFF2DD4A0),
        onBase: Color(0xFF042D22),
        surface: Color(0xFF123B32),
        onSurface: Color(0xFFC9F2E4),
        border: Color(0xFF176E59),
      ),
      cashflowPositive: const AppTonePalette(
        base: Color(0xFF34D399),
        onBase: Color(0xFF042D22),
        surface: Color(0xFF0F3D31),
        onSurface: Color(0xFFC6F6E7),
        border: Color(0xFF1F7A5F),
      ),
      cashflowNegative: const AppTonePalette(
        base: Color(0xFFFF6B6B),
        onBase: Color(0xFF3F0505),
        surface: Color(0xFF4A1618),
        onSurface: Color(0xFFFFD8D8),
        border: Color(0xFF8B2F35),
      ),
      stockLow: const AppTonePalette(
        base: Color(0xFFFBBF24),
        onBase: Color(0xFF332000),
        surface: Color(0xFF3B2A0B),
        onSurface: Color(0xFFFFE8A3),
        border: Color(0xFF745510),
      ),
      interactive: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.surfaceContainerHigh,
        onSurface: colorScheme.onSurface,
        border: colorScheme.outlineVariant,
      ),
      disabled: AppTonePalette(
        base: colorScheme.surfaceContainerHigh,
        onBase: colorScheme.onSurfaceVariant.withValues(alpha: 0.64),
        surface: colorScheme.surfaceContainerHigh,
        onSurface: colorScheme.onSurfaceVariant.withValues(alpha: 0.64),
        border: colorScheme.outlineVariant.withValues(alpha: 0.72),
      ),
      selection: AppTonePalette(
        base: colorScheme.primary,
        onBase: colorScheme.onPrimary,
        surface: colorScheme.primaryContainer,
        onSurface: colorScheme.onPrimaryContainer,
        border: const Color(0xFF176E59),
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'NotoSans',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorTokens.pageBackground,
      extensions: <ThemeExtension<dynamic>>[colorTokens, layoutTokens],
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurface,
        height: 1.42,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        height: 1.4,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        height: 1.32,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        color: colorScheme.onSurface,
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
        backgroundColor: colorTokens.cardBackground,
        foregroundColor: colorScheme.onSurface,
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
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
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
              return colorScheme.primary.withValues(alpha: 0.08);
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
        backgroundColor: colorTokens.cardBackground,
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
        side: BorderSide(color: colorTokens.outlineSoft),
        padding: EdgeInsets.symmetric(
          horizontal: layoutTokens.space4,
          vertical: layoutTokens.space2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        actionTextColor: colorScheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusLg),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorTokens.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
        textColor: colorScheme.onSurface,
        selectedColor: colorScheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.radiusMd),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(layoutTokens.space3),
        ),
        side: BorderSide(color: colorScheme.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant;
        }),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colorTokens.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(layoutTokens.radiusSheet),
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorTokens.cardBackground,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static ThemeData light() {
    final seededScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    final colorScheme = seededScheme.copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryDim,
      onPrimaryContainer: AppColors.text2,
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.salesBackground,
      onSecondaryContainer: AppColors.text2,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: AppColors.text3,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surface2,
      surfaceContainer: AppColors.surface3,
      surfaceContainerHigh: AppColors.borderLight,
      surfaceContainerHighest: AppColors.border,
      outline: AppColors.border,
      outlineVariant: AppColors.borderLight,
      error: error,
      onError: Colors.white,
      errorContainer: AppColors.errorBackground,
      onErrorContainer: const Color(0xFF7F1D1D),
      tertiary: success,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.successBackground,
      onTertiaryContainer: const Color(0xFF065F46),
      shadow: AppColors.text1,
      scrim: AppColors.text1,
    );

    const layoutTokens = AppLayoutTokens(
      radiusSm: 8,
      radiusMd: 12,
      radiusLg: 16,
      radiusXl: 20,
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
      pagePadding: 18,
      pagePaddingCompact: 12,
      sectionGap: 16,
      blockGap: 12,
      gridGap: 12,
      iconSm: 16,
      iconMd: 18,
      iconLg: 22,
      inputHeight: 48,
      actionHeight: 48,
      compactActionHeight: 40,
      quickActionHeight: 46,
      cardPadding: 16,
      compactCardPadding: 12,
      headerPadding: 16,
      bottomBarPadding: 12,
      sheetPadding: 16,
      shadowBlur: 18,
      shadowOffsetY: 8,
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
        surface: colorScheme.primaryContainer,
        onSurface: colorScheme.onPrimaryContainer,
        border: AppColors.primaryBorder,
      ),
      info: const AppTonePalette(
        base: AppColors.info,
        onBase: Colors.white,
        surface: AppColors.infoBackground,
        onSurface: Color(0xFF1D4ED8),
        border: Color(0xFFBFDBFE),
      ),
      success: AppTonePalette(
        base: colorScheme.tertiary,
        onBase: colorScheme.onTertiary,
        surface: colorScheme.tertiaryContainer,
        onSurface: colorScheme.onTertiaryContainer,
        border: const Color(0xFFA7F3D0),
      ),
      warning: const AppTonePalette(
        base: warning,
        onBase: Colors.white,
        surface: AppColors.warningBackground,
        onSurface: Color(0xFF92400E),
        border: Color(0xFFFCD34D),
      ),
      danger: AppTonePalette(
        base: colorScheme.error,
        onBase: colorScheme.onError,
        surface: colorScheme.errorContainer,
        onSurface: colorScheme.onErrorContainer,
        border: const Color(0xFFFCA5A5),
      ),
      sales: const AppTonePalette(
        base: AppColors.primaryLight,
        onBase: Colors.white,
        surface: AppColors.salesBackground,
        onSurface: AppColors.text2,
        border: AppColors.primaryBorder,
      ),
      cashflowPositive: const AppTonePalette(
        base: AppColors.success,
        onBase: Colors.white,
        surface: AppColors.successBackground,
        onSurface: Color(0xFF065F46),
        border: Color(0xFFA7F3D0),
      ),
      cashflowNegative: const AppTonePalette(
        base: AppColors.error,
        onBase: Colors.white,
        surface: AppColors.errorBackground,
        onSurface: Color(0xFF991B1B),
        border: Color(0xFFFCA5A5),
      ),
      stockLow: const AppTonePalette(
        base: AppColors.warning,
        onBase: Colors.white,
        surface: AppColors.stockBackground,
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
        surface: colorScheme.primaryContainer,
        onSurface: colorScheme.onPrimaryContainer,
        border: AppColors.primaryBorder,
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSans',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorTokens.pageBackground,
      extensions: <ThemeExtension<dynamic>>[colorTokens, layoutTokens],
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
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
        backgroundColor: colorTokens.cardBackground,
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
        backgroundColor: colorTokens.cardBackground,
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
        side: BorderSide(color: colorTokens.outlineSoft),
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
        elevation: 0,
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
      drawerTheme: DrawerThemeData(
        backgroundColor: colorTokens.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(layoutTokens.radiusSheet),
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorTokens.cardBackground,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
