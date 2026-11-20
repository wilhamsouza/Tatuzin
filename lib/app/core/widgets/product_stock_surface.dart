import 'package:flutter/material.dart';

import '../theme/app_design_tokens.dart';
import '../theme/dashboard_theme.dart';

/// Reuses the Tatuzin palette for catalog and inventory routes without changing
/// the theme of the PDV, cash, reports or other existing workflows.
class ProductStockSurface extends StatelessWidget {
  const ProductStockSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = DashboardTheme.of(context);
    final scheme = data.colorScheme;
    final tokens = data.extension<AppColorTokens>();
    final foreground = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.38)
          : scheme.primary,
    );
    final overlay = WidgetStatePropertyAll(
      scheme.primary.withValues(alpha: 0.08),
    );
    // AppTheme contains concrete component styles, so recolor those styles as
    // well as ColorScheme while retaining their spacing, shapes and tap sizes.
    return Theme(
      data: data.copyWith(
        cardTheme: data.cardTheme.copyWith(color: tokens?.cardBackground),
        dialogTheme: data.dialogTheme.copyWith(
          backgroundColor: tokens?.cardBackground,
        ),
        bottomSheetTheme: data.bottomSheetTheme.copyWith(
          backgroundColor: tokens?.cardBackground,
        ),
        drawerTheme: data.drawerTheme.copyWith(
          backgroundColor: tokens?.cardBackground,
        ),
        inputDecorationTheme: data.inputDecorationTheme.copyWith(
          hintStyle: data.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          labelStyle: data.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          prefixIconColor: scheme.onSurfaceVariant,
          suffixIconColor: scheme.onSurfaceVariant,
          focusedBorder: data.inputDecorationTheme.focusedBorder?.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.6),
          ),
        ),
        chipTheme: data.chipTheme.copyWith(
          backgroundColor: tokens?.cardBackground,
          selectedColor: scheme.primaryContainer,
          secondarySelectedColor: scheme.primaryContainer,
          checkmarkColor: scheme.onPrimaryContainer,
          labelStyle: data.chipTheme.labelStyle?.copyWith(
            color: scheme.onSurface,
          ),
          secondaryLabelStyle: data.chipTheme.secondaryLabelStyle?.copyWith(
            color: scheme.onPrimaryContainer,
          ),
        ),
        listTileTheme: data.listTileTheme.copyWith(
          iconColor: scheme.primary,
          textColor: scheme.onSurface,
          selectedColor: scheme.primary,
          selectedTileColor: scheme.primaryContainer,
        ),
        checkboxTheme: data.checkboxTheme.copyWith(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.transparent,
          ),
          checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (data.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: 0.12)
                  : scheme.primary,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: 0.38)
                  : scheme.onPrimary,
            ),
            overlayColor: WidgetStatePropertyAll(
              scheme.onPrimary.withValues(alpha: 0.08),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (data.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                foregroundColor: foreground,
                iconColor: foreground,
                overlayColor: overlay,
              ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (data.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: foreground,
            iconColor: foreground,
            overlayColor: overlay,
          ),
        ),
      ),
      child: child,
    );
  }
}
