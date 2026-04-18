import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_period.dart';
import '../providers/report_providers.dart';

class ReportPeriodBar extends ConsumerWidget {
  const ReportPeriodBar({
    super.key,
    this.title = 'Periodo',
    this.subtitle = 'Escolha o recorte que alimenta o relatorio.',
    this.showGrouping = false,
    this.showIncludeCanceled = false,
    this.groupingOptions = const [
      ReportGrouping.day,
      ReportGrouping.week,
      ReportGrouping.month,
    ],
  });

  final String title;
  final String subtitle;
  final bool showGrouping;
  final bool showIncludeCanceled;
  final List<ReportGrouping> groupingOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final period = ref.watch(reportPeriodProvider);
    final controller = ref.read(reportFilterProvider.notifier);
    final lastIncludedDay = filter.endExclusive.subtract(
      const Duration(days: 1),
    );
    final selectedGrouping = groupingOptions.contains(filter.grouping)
        ? filter.grouping
        : groupingOptions.first;

    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final currentPeriod in ReportPeriod.values)
                ChoiceChip(
                  label: Text(currentPeriod.label),
                  selected: period == currentPeriod,
                  onSelected: (_) => controller.applyPeriod(currentPeriod),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Base: ${AppFormatters.shortDate(filter.start)} ate ${AppFormatters.shortDate(lastIncludedDay)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (showGrouping || showIncludeCanceled) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showGrouping)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<ReportGrouping>(
                      initialValue: selectedGrouping,
                      decoration: const InputDecoration(
                        labelText: 'Agrupar por',
                      ),
                      items: groupingOptions
                          .map(
                            (grouping) => DropdownMenuItem(
                              value: grouping,
                              child: Text(grouping.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        controller.setGrouping(value);
                      },
                    ),
                  ),
                if (showIncludeCanceled)
                  FilterChip(
                    label: const Text('Incluir canceladas'),
                    selected: filter.includeCanceled,
                    onSelected: controller.setIncludeCanceled,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
