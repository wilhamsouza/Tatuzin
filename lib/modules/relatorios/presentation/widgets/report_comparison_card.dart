import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/theme/app_design_tokens.dart';

class ReportComparisonCard extends StatelessWidget {
  const ReportComparisonCard({
    super.key,
    required this.title,
    required this.currentValue,
    required this.previousValue,
    required this.deltaLabel,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String currentValue;
  final String previousValue;
  final String deltaLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: _ComparisonBlock(
              label: 'Atual',
              value: currentValue,
              palette: colors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ComparisonBlock(
              label: 'Anterior',
              value: previousValue,
              palette: colors.interactive,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ComparisonBlock(
              label: 'Variacao',
              value: deltaLabel,
              palette: deltaLabel.startsWith('-')
                  ? colors.cashflowNegative
                  : colors.cashflowPositive,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonBlock extends StatelessWidget {
  const _ComparisonBlock({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final AppTonePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
