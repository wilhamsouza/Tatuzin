import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_card.dart';

class AppMetricCard extends StatelessWidget {
  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.onTap,
    this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final layout = context.appLayout;
    final tokens = context.appColors;
    final effectiveAccent = accentColor ?? colorScheme.primary;

    return AppCard(
      onTap: onTap,
      borderRadius: layout.radiusXl,
      padding: EdgeInsets.all(layout.compactCardPadding - 1),
      color: effectiveAccent.withValues(alpha: 0.08),
      borderColor: effectiveAccent.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(layout.radiusSm),
                ),
                child: Padding(
                  padding: EdgeInsets.all(layout.space3),
                  child: Icon(icon, size: 15, color: effectiveAccent),
                ),
              ),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: layout.iconMd,
                  color: tokens.interactive.onSurface,
                ),
            ],
          ),
          SizedBox(height: layout.space4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: layout.space2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption?.isNotEmpty ?? false) ...[
            SizedBox(height: layout.space2),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
