import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../data/support/report_date_range_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_period.dart';
import '../providers/report_providers.dart';
import 'report_filter_chip.dart';

class ActiveReportFiltersBar extends ConsumerWidget {
  const ActiveReportFiltersBar({super.key, required this.page});

  final ReportPageKey page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final config = ReportFilterPresetSupport.configFor(page);
    final matchedPeriod = ReportDateRangeSupport.matchPeriod(filter.range);
    final periodLabel = matchedPeriod == null
        ? 'Periodo: ${AppFormatters.shortDate(filter.start)} ate ${AppFormatters.shortDate(filter.endExclusive.subtract(const Duration(days: 1)))}'
        : 'Periodo: ${matchedPeriod.label}';
    final hasActiveFilters =
        (config.supports(ReportFilterField.grouping) &&
            filter.grouping != config.defaultGrouping) ||
        (config.supports(ReportFilterField.onlyCanceled) &&
            filter.onlyCanceled) ||
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
    final sessionController = ref.read(reportPageSessionProvider.notifier);
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
                sessionController.clearDrilldown(page);
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

        Widget buildPeriodPill() {
          final theme = Theme.of(context);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              periodLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        if (!hasActiveFilters) {
          return buildPeriodPill();
        }

        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildPeriodPill(),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < chips.length; index++) ...[
                      chips[index],
                      if (index < chips.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildPeriodPill(),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        );
      },
    );
  }
}
