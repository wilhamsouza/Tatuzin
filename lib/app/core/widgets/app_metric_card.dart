import 'package:flutter/material.dart';

import '../theme/app_design_tokens.dart';
import 'app_card.dart';

enum AppMetricDeltaTone { positive, negative, neutral }

class AppMetricDelta {
  const AppMetricDelta({required this.label, required this.tone});

  final String label;
  final AppMetricDeltaTone tone;
}

class AppMetricCard extends StatelessWidget {
  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.onTap,
    this.accentColor,
    this.horizontal = false,
    this.delta,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool horizontal;
  final AppMetricDelta? delta;

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
      child: horizontal
          ? Row(
              children: [
                Expanded(
                  child: _MetricTextBlock(
                    label: label,
                    value: value,
                    caption: caption,
                    delta: delta,
                  ),
                ),
                SizedBox(width: layout.space5),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(layout.radiusSm),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(layout.space3),
                    child: Icon(icon, size: 18, color: effectiveAccent),
                  ),
                ),
                if (onTap != null) ...[
                  SizedBox(width: layout.space2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: layout.iconMd,
                    color: tokens.interactive.onSurface,
                  ),
                ],
              ],
            )
          : Column(
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
                _MetricTextBlock(
                  label: label,
                  value: value,
                  caption: caption,
                  delta: delta,
                ),
              ],
            ),
    );
  }
}

class _MetricTextBlock extends StatelessWidget {
  const _MetricTextBlock({
    required this.label,
    required this.value,
    required this.caption,
    required this.delta,
  });

  final String label;
  final String value;
  final String? caption;
  final AppMetricDelta? delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final layout = context.appLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: layout.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (delta != null) ...[
          SizedBox(height: layout.space2),
          _MetricDeltaBadge(delta: delta!),
        ],
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
    );
  }
}

class _MetricDeltaBadge extends StatelessWidget {
  const _MetricDeltaBadge({required this.delta});

  final AppMetricDelta delta;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final theme = Theme.of(context);
    final palette = switch (delta.tone) {
      AppMetricDeltaTone.positive => tokens.success,
      AppMetricDeltaTone.negative => tokens.danger,
      AppMetricDeltaTone.neutral => tokens.disabled,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(context.appLayout.radiusPill),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          delta.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
