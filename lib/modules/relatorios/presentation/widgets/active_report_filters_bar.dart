import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/support/report_filter_preset_support.dart';
import '../providers/report_providers.dart';
import 'report_filter_chip.dart';

class ActiveReportFiltersBar extends ConsumerWidget {
  const ActiveReportFiltersBar({
    super.key,
    required this.page,
  });

  final ReportPageKey page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final config = ReportFilterPresetSupport.configFor(page);
    final hasActiveFilters =
        (config.supports(ReportFilterField.grouping) &&
            filter.grouping != config.defaultGrouping) ||
        (config.supports(ReportFilterField.onlyCanceled) && filter.onlyCanceled) ||
        (config.supports(ReportFilterField.includeCanceled) &&
            filter.includeCanceled) ||
        (config.supports(ReportFilterField.customer) &&
            filter.customerId != null) ||
        (config.supports(ReportFilterField.category) &&
            filter.categoryId != null) ||
        (config.supports(ReportFilterField.product) &&
            filter.productId != null) ||
        (config.supports(ReportFilterField.variant) &&
            filter.variantId != null) ||
        (config.supports(ReportFilterField.paymentMethod) &&
            filter.paymentMethod != null) ||
        (config.supports(ReportFilterField.supplier) &&
            filter.supplierId != null) ||
        (config.supports(ReportFilterField.focus) && filter.focus != null);

    if (!hasActiveFilters) {
      return const SizedBox.shrink();
    }

    final needsOptionLabels =
        (config.supports(ReportFilterField.customer) &&
            filter.customerId != null) ||
        (config.supports(ReportFilterField.category) &&
            filter.categoryId != null) ||
        (config.supports(ReportFilterField.product) &&
            filter.productId != null) ||
        (config.supports(ReportFilterField.variant) &&
            filter.variantId != null) ||
        (config.supports(ReportFilterField.supplier) &&
            filter.supplierId != null);
    final labels = needsOptionLabels
        ? ref.watch(reportFilterOptionLabelsProvider).valueOrNull ??
            const ReportFilterOptionLabels()
        : const ReportFilterOptionLabels();
    final controller = ref.read(reportFilterProvider.notifier);
    final descriptors = ReportFilterPresetSupport.activeFiltersForPage(
      page: page,
      filter: filter,
      labels: labels,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final chips = [
          for (final descriptor in descriptors)
            ReportFilterChip(
              label: descriptor.displayLabel,
              onRemoved: () {
                controller.replace(
                  ReportFilterPresetSupport.removeField(
                    page,
                    filter,
                    descriptor.field,
                  ),
                );
              },
            ),
        ];

        if (constraints.maxWidth < 720) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < chips.length; index++) ...[
                  chips[index],
                  if (index < chips.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          );
        }

        return Wrap(spacing: 8, runSpacing: 8, children: chips);
      },
    );
  }
}
