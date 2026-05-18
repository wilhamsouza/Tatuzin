import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_metric_card.dart';

class ReportKpiItem {
  const ReportKpiItem({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.accentColor,
    this.onTap,
    this.delta,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color? accentColor;
  final VoidCallback? onTap;
  final AppMetricDelta? delta;
}

class ReportKpiGrid extends StatelessWidget {
  const ReportKpiGrid({super.key, required this.items});

  final List<ReportKpiItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final useSingleColumn = width < 390;
        final crossAxisCount = useSingleColumn
            ? 1
            : width >= 1100
            ? 4
            : width >= 760
            ? 3
            : 2;

        final itemHeight = useSingleColumn
            ? 132.0
            : width >= 760
            ? 176.0
            : 190.0;

        return GridView.builder(
          key: const ValueKey('report_kpi_grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: itemHeight,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AppMetricCard(
              label: item.label,
              value: item.value,
              caption: item.caption,
              icon: item.icon,
              accentColor: item.accentColor,
              onTap: item.onTap,
              horizontal: useSingleColumn,
              delta: item.delta,
            );
          },
        );
      },
    );
  }
}
