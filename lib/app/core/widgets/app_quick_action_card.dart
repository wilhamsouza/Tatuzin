import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_card.dart';

class AppQuickActionCard extends StatelessWidget {
  const AppQuickActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.palette,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final AppTonePalette? palette;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final layout = context.appLayout;
    final resolvedPalette = palette ?? tokens.brand;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(layout.cardPadding - 2),
      color: resolvedPalette.surface,
      borderColor: resolvedPalette.border,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(layout.radiusMd),
            ),
            child: Padding(
              padding: EdgeInsets.all(layout.space4),
              child: Icon(
                icon,
                size: layout.iconLg,
                color: resolvedPalette.base,
              ),
            ),
          ),
          SizedBox(width: layout.space6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: layout.space2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: resolvedPalette.onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: layout.space4),
          Icon(
            Icons.chevron_right_rounded,
            size: layout.iconMd,
            color: resolvedPalette.onSurface.withValues(alpha: 0.82),
          ),
        ],
      ),
    );
  }
}
