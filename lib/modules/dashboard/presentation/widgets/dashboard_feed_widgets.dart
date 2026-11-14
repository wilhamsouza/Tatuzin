import 'package:flutter/material.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_card.dart';

class DashboardShortcut extends StatelessWidget {
  const DashboardShortcut({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors.brand;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SizedBox(
      width: 82 * scale.clamp(1, 2),
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.appLayout.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surface.withValues(alpha: 0.55),
                    border: Border.all(color: palette.border, width: 1.5),
                  ),
                  child: Icon(icon, color: palette.base, size: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A naturally sized metric: no fixed grid height or scaled-down currency.
class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.onTap,
    this.accent,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? context.appColors.brand.base;
    final text = Theme.of(context).textTheme;
    return AppCard(
      color: color.withValues(alpha: 0.07),
      borderColor: color.withValues(alpha: 0.16),
      padding: EdgeInsets.all(context.appLayout.compactCardPadding),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const Spacer(),
              if (onTap != null)
                Icon(Icons.chevron_right, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(label, style: text.labelLarge),
          const SizedBox(height: 4),
          Text(
            value,
            style: text.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardMetricLayout extends StatelessWidget {
  const DashboardMetricLayout({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = context.appLayout.gridGap;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = children.length == 1
          ? 1
          : constraints.maxWidth >= 540 && scale < 1.4
          ? 3
          : constraints.maxWidth >= 280 && scale < 1.4
          ? 2
          : 1;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var index = 0; index < children.length; index++)
            SizedBox(
              width: columns == 2 && children.length == 3 && index == 2
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap * (columns - 1)) / columns,
              child: children[index],
            ),
        ],
      );
    },
  );
}
