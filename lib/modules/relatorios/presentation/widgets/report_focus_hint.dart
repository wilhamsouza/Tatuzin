import 'package:flutter/material.dart';

import '../../../../app/theme/app_design_tokens.dart';
import '../../data/support/report_drilldown_support.dart';
import 'report_context_badge.dart';

class ReportFocusHint extends StatelessWidget {
  const ReportFocusHint({super.key, required this.hint});

  final ReportFocusHintData hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.sectionBackground,
        borderRadius: BorderRadius.circular(context.appLayout.radiusLg),
        border: Border.all(color: colors.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                hint.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (hint.isFocusOnly)
                const ReportContextBadge(
                  label: 'Foco de leitura',
                  icon: Icons.visibility_rounded,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
