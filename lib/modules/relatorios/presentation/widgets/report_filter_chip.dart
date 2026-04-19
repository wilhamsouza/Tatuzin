import 'package:flutter/material.dart';

import '../../../../app/theme/app_design_tokens.dart';

class ReportFilterChip extends StatelessWidget {
  const ReportFilterChip({
    super.key,
    required this.label,
    required this.onRemoved,
  });

  final String label;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InputChip(
      label: Text(label),
      onDeleted: onRemoved,
      deleteIcon: const Icon(Icons.close_rounded, size: 18),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      side: BorderSide(color: colors.outlineSoft),
      backgroundColor: colors.sectionBackground,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
