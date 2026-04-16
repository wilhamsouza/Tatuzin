import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

enum AppStatusTone { neutral, info, success, warning, danger }

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppStatusTone.neutral,
    this.icon,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final colors = _colors(context.appColors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(layout.radiusPill),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.space5 - 1,
          vertical: layout.space3 - 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.onSurface),
              SizedBox(width: layout.space2 + 1),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppTonePalette _colors(AppColorTokens tokens) {
    switch (tone) {
      case AppStatusTone.info:
        return tokens.info;
      case AppStatusTone.success:
        return tokens.success;
      case AppStatusTone.warning:
        return tokens.warning;
      case AppStatusTone.danger:
        return tokens.danger;
      case AppStatusTone.neutral:
        return tokens.interactive;
    }
  }
}
