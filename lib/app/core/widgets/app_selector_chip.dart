import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

enum AppSelectorChipTone { neutral, info, success, warning, danger, brand }

class AppSelectorChip extends StatelessWidget {
  const AppSelectorChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.icon,
    this.count,
    this.tone = AppSelectorChipTone.neutral,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final IconData? icon;
  final int? count;
  final AppSelectorChipTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final layout = context.appLayout;
    final palette = _palette(tokens);
    final background = selected ? palette.surface : tokens.sectionBackground;
    final foreground = selected
        ? palette.onSurface
        : tokens.interactive.onSurface;
    final borderColor = selected ? palette.border : tokens.outlineSoft;

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(layout.radiusPill),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelected == null ? null : () => onSelected!(!selected),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.space5,
            vertical: layout.space4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: layout.iconSm, color: foreground),
                SizedBox(width: layout.space3),
              ],
              Text(
                count == null ? label : '$label ($count)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppTonePalette _palette(AppColorTokens tokens) {
    switch (tone) {
      case AppSelectorChipTone.info:
        return tokens.info;
      case AppSelectorChipTone.success:
        return tokens.success;
      case AppSelectorChipTone.warning:
        return tokens.warning;
      case AppSelectorChipTone.danger:
        return tokens.danger;
      case AppSelectorChipTone.brand:
        return tokens.brand;
      case AppSelectorChipTone.neutral:
        return tokens.selection;
    }
  }
}
