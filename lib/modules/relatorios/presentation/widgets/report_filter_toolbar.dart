import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_selector_chip.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../data/support/report_export_mapper.dart';
import '../providers/report_providers.dart';
import 'active_report_filters_bar.dart';
import 'report_clear_filters_button.dart';
import 'report_export_button.dart';
import 'report_filter_sheet.dart';
import 'report_reset_page_button.dart';

class ReportFilterToolbar extends ConsumerWidget {
  const ReportFilterToolbar({
    super.key,
    required this.page,
    this.onExportPdf,
    this.onExportCsv,
  });

  final ReportPageKey page;
  final Future<void> Function(ReportExportMode mode)? onExportPdf;
  final Future<void> Function(ReportExportMode mode)? onExportCsv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final controller = ref.read(reportFilterProvider.notifier);
    final config = ReportFilterPresetSupport.configFor(page);
    final clearedState = ReportFilterPresetSupport.clearForPage(page, filter);
    final defaultState = ReportFilterPresetSupport.resetToPageDefault(page);
    final canClear = filter != clearedState;
    final canReset = filter != defaultState;
    final showExport = onExportPdf != null && onExportCsv != null;

    return AppSectionCard(
      title: 'Filtros avancados',
      subtitle: 'Refine o recorte, veja o que esta ativo e exporte o resultado.',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    showReportFilterSheet(context, page: page),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Ajustar filtros'),
              ),
              ReportClearFiltersButton(
                enabled: canClear,
                onPressed: () => controller.replace(clearedState),
              ),
              ReportResetPageButton(
                enabled: canReset,
                onPressed: () => controller.replace(defaultState),
              ),
              if (showExport)
                ReportExportButton(
                  onExportPdf: onExportPdf!,
                  onExportCsv: onExportCsv!,
                ),
            ],
          ),
          if (config.presets.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < config.presets.length; index++) ...[
                    AppSelectorChip(
                      label: config.presets[index].label,
                      selected: config.presets[index].matches(filter),
                      onSelected: (_) {
                        controller.replace(
                          ReportFilterPresetSupport.applyPreset(
                            filter,
                            config.presets[index],
                          ),
                        );
                      },
                    ),
                    if (index < config.presets.length - 1)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ActiveReportFiltersBar(page: page),
        ],
      ),
    );
  }
}
