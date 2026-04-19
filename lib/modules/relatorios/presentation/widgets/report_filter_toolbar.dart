import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_selector_chip.dart';
import '../../data/support/report_drilldown_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../data/support/report_export_mapper.dart';
import '../providers/report_providers.dart';
import 'active_report_filters_bar.dart';
import 'report_clear_filters_button.dart';
import 'report_drilldown_banner.dart';
import 'report_export_button.dart';
import 'report_filter_sheet.dart';
import 'report_focus_hint.dart';
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
    final sessionController = ref.read(reportPageSessionProvider.notifier);
    final sessionState = ref.watch(reportPageSessionProvider);
    final config = ReportFilterPresetSupport.configFor(page);
    final activePreset = ReportFilterPresetSupport.activePresetForPage(
      page,
      filter,
    );
    final lastPreset = sessionState.lastPresetIdFor(page) == null
        ? null
        : ReportFilterPresetSupport.presetById(
            page,
            sessionState.lastPresetIdFor(page)!,
          );
    final clearedState = ReportFilterPresetSupport.clearForPage(page, filter);
    final defaultState = ReportFilterPresetSupport.resetToPageDefault(page);
    final canClear = filter != clearedState;
    final canReset = filter != defaultState;
    final showExport = onExportPdf != null && onExportCsv != null;
    final focusHint = ReportDrilldownSupport.focusHintForPage(page, filter);

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
                onPressed: () {
                  sessionController.clearDrilldown(page);
                  controller.replace(clearedState);
                },
              ),
              ReportResetPageButton(
                enabled: canReset,
                onPressed: () {
                  sessionController.clearDrilldown(page);
                  controller.replace(defaultState);
                },
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
                        sessionController.clearDrilldown(page);
                        sessionController.rememberPreset(
                          page,
                          config.presets[index].id,
                        );
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
            if ((activePreset?.helperText ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                activePreset!.helperText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (activePreset == null &&
                (lastPreset?.helperText ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Ultimo atalho desta tela: ${lastPreset!.label}. ${lastPreset.helperText!}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ReportDrilldownBanner(page: page),
          if (focusHint != null) ...[
            if (ref.watch(
                  reportPageSessionProvider.select(
                    (state) => state.drilldownFor(page) != null,
                  ),
                ))
              const SizedBox(height: 10),
            ReportFocusHint(hint: focusHint),
          ],
          const SizedBox(height: 12),
          ActiveReportFiltersBar(page: page),
        ],
      ),
    );
  }
}
