import 'package:flutter/material.dart';

import '../../../../app/theme/app_design_tokens.dart';

class ReportFilterSection extends StatelessWidget {
  const ReportFilterSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle?.isNotEmpty ?? false) ...[
          SizedBox(height: layout.space2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: layout.space4),
        child,
      ],
    );
  }
}
