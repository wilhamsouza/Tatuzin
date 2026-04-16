import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_card.dart';

class AppSummaryBlock extends StatelessWidget {
  const AppSummaryBlock({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.onTap,
    this.palette,
    this.compact = false,
    this.infoMessage,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final VoidCallback? onTap;
  final AppTonePalette? palette;
  final bool compact;
  final String? infoMessage;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final tokens = context.appColors;
    final theme = Theme.of(context);
    final resolvedPalette = palette ?? tokens.brand;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(
        compact ? layout.compactCardPadding : layout.cardPadding,
      ),
      color: resolvedPalette.surface,
      borderColor: resolvedPalette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(layout.radiusSm),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(layout.space3),
                    child: Icon(
                      icon,
                      size: layout.iconSm,
                      color: resolvedPalette.base,
                    ),
                  ),
                ),
              if (icon != null) SizedBox(width: layout.space4),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: resolvedPalette.onSurface.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (infoMessage != null)
                Tooltip(
                  message: infoMessage!,
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: layout.iconMd,
                    color: resolvedPalette.onSurface.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? layout.space3 : layout.space4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: resolvedPalette.onSurface,
            ),
          ),
          if (caption?.isNotEmpty ?? false) ...[
            SizedBox(height: layout.space2),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: resolvedPalette.onSurface.withValues(alpha: 0.82),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
