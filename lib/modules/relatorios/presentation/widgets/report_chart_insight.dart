import 'package:flutter/material.dart';

import '../../../../app/theme/app_design_tokens.dart';

class ReportChartInsight extends StatelessWidget {
  const ReportChartInsight({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final layout = context.appLayout;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: layout.space6,
        vertical: layout.space5,
      ),
      decoration: BoxDecoration(
        color: colors.brand.surface,
        borderRadius: BorderRadius.circular(layout.radiusLg),
        border: Border.all(color: colors.brand.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 18,
            color: colors.brand.base,
          ),
          SizedBox(width: layout.space4),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.brand.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
