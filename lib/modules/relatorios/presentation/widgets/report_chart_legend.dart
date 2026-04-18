import 'package:flutter/material.dart';

import '../../../../app/theme/app_design_tokens.dart';
import '../../data/support/report_donut_support.dart';
import '../../domain/entities/report_donut_slice.dart';

class ReportChartLegend extends StatelessWidget {
  const ReportChartLegend({
    super.key,
    required this.slices,
    this.activeIndex,
    this.onSelect,
  });

  final List<ReportDonutSlice> slices;
  final int? activeIndex;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return Column(
      children: [
        for (var index = 0; index < slices.length; index++) ...[
          _LegendRow(
            slice: slices[index],
            isActive: activeIndex == index,
            onTap: onSelect == null ? null : () => onSelect!(index),
          ),
          if (index < slices.length - 1) SizedBox(height: layout.space4),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.isActive, this.onTap});

  final ReportDonutSlice slice;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final layout = context.appLayout;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(layout.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: layout.space6,
            vertical: layout.space5,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? slice.color.withValues(alpha: 0.12)
                : colors.sectionBackground,
            borderRadius: BorderRadius.circular(layout.radiusLg),
            border: Border.all(
              color: isActive
                  ? slice.color.withValues(alpha: 0.32)
                  : colors.outlineSoft,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: slice.color,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: layout.space5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slice.formattedValue,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ReportDonutSupport.formatPercentage(slice.percentage),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
