import 'package:flutter/material.dart';

import '../theme/app_design_tokens.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isPrimary = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final layout = context.appLayout;
    final foreground = isPrimary ? colors.brand.onBase : colors.brand.base;
    final background = isPrimary ? colors.brand.base : colors.cardBackground;
    final border = isPrimary ? colors.brand.base : colors.outlineSoft;

    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 44,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(layout.radiusMd),
            side: BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Badge(
                isLabelVisible: badgeCount > 0,
                label: Text('$badgeCount'),
                child: Icon(icon, color: foreground, size: layout.iconLg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
