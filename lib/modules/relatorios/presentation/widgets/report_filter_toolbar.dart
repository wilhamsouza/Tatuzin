import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../data/support/report_drilldown_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../data/support/report_export_mapper.dart';
import '../../data/support/report_date_range_support.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_period.dart';
import '../providers/report_providers.dart';
import 'report_drilldown_banner.dart';
import 'report_export_menu.dart';
import 'report_filter_sheet.dart';
import 'report_focus_hint.dart';

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
    final config = ReportFilterPresetSupport.configFor(page);
    final activePreset = ReportFilterPresetSupport.activePresetForPage(
      page,
      filter,
    );
    final clearedState = ReportFilterPresetSupport.clearForPage(page, filter);
    final defaultState = ReportFilterPresetSupport.resetToPageDefault(page);
    final canClear = filter != clearedState;
    final canReset = filter != defaultState;
    final showExport = onExportPdf != null && onExportCsv != null;
    final focusHint = ReportDrilldownSupport.focusHintForPage(page, filter);
    final filterCount = _activeFilterCount(filter, config);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          borderRadius: context.appLayout.radiusLg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _PeriodChip(
                  label: _periodLabel(filter),
                  onTap: () => showReportFilterSheet(context, page: page),
                ),
              ),
              const SizedBox(width: 8),
              if (filterCount > 0) ...[
                _FilterCountChip(
                  count: filterCount,
                  onTap: () => showReportFilterSheet(context, page: page),
                ),
                const SizedBox(width: 8),
              ],
              _ToolbarIconButton(
                tooltip: 'Ajustar filtros',
                icon: Icons.tune_rounded,
                onPressed: () => showReportFilterSheet(context, page: page),
              ),
              if (showExport) ...[
                const SizedBox(width: 6),
                _CompactExportButton(
                  onExportPdf: onExportPdf!,
                  onExportCsv: onExportCsv!,
                ),
              ],
              if (canClear || canReset || config.presets.isNotEmpty) ...[
                const SizedBox(width: 6),
                _ToolbarOverflowButton(
                  presets: config.presets,
                  activePresetId: activePreset?.id,
                  canClear: canClear,
                  canReset: canReset,
                  onSelected: (action) {
                    switch (action.type) {
                      case _ToolbarActionType.clear:
                        sessionController.clearDrilldown(page);
                        controller.replace(clearedState);
                      case _ToolbarActionType.reset:
                        sessionController.clearDrilldown(page);
                        controller.replace(defaultState);
                      case _ToolbarActionType.preset:
                        final preset = ReportFilterPresetSupport.presetById(
                          page,
                          action.presetId!,
                        );
                        if (preset == null) {
                          return;
                        }
                        sessionController.clearDrilldown(page);
                        sessionController.rememberPreset(page, preset.id);
                        controller.replace(
                          ReportFilterPresetSupport.applyPreset(filter, preset),
                        );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        if (ref.watch(
              reportPageSessionProvider.select(
                (state) => state.drilldownFor(page) != null,
              ),
            ) ||
            focusHint != null) ...[
          const SizedBox(height: 8),
          ReportDrilldownBanner(page: page),
          if (focusHint != null) ...[
            const SizedBox(height: 8),
            ReportFocusHint(hint: focusHint),
          ],
        ],
      ],
    );
  }

  static String _periodLabel(ReportFilter filter) {
    final period = ReportDateRangeSupport.matchPeriod(filter.range);
    final prefix = period?.label ?? 'Personalizado';
    final start = AppFormatters.shortDate(filter.start);
    final lastDay = filter.endExclusive.subtract(const Duration(days: 1));
    final end = AppFormatters.shortDate(lastDay);
    if (start == end) {
      return '$prefix - $start';
    }
    return '$prefix - $start a $end';
  }

  static int _activeFilterCount(
    ReportFilter filter,
    ReportFilterPageConfig config,
  ) {
    var count = 0;
    if (config.supports(ReportFilterField.customer) &&
        filter.customerId != null) {
      count++;
    }
    if (config.supports(ReportFilterField.category) &&
        filter.categoryId != null) {
      count++;
    }
    if (config.supports(ReportFilterField.product) &&
        filter.productId != null) {
      count++;
    }
    if (config.supports(ReportFilterField.variant) &&
        filter.variantId != null) {
      count++;
    }
    if (config.supports(ReportFilterField.supplier) &&
        filter.supplierId != null) {
      count++;
    }
    if (config.supports(ReportFilterField.paymentMethod) &&
        filter.paymentMethod != null) {
      count++;
    }
    if (config.supports(ReportFilterField.onlyCanceled) &&
        filter.onlyCanceled) {
      count++;
    } else if (config.supports(ReportFilterField.includeCanceled) &&
        filter.includeCanceled != config.defaultIncludeCanceled) {
      count++;
    }
    if (config.supports(ReportFilterField.focus) && filter.focus != null) {
      count++;
    }
    if (config.supports(ReportFilterField.grouping) &&
        filter.grouping != config.defaultGrouping) {
      count++;
    }
    return count;
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);

    return Material(
      color: colors.brand.base,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: colors.brand.onBase,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.brand.onBase,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterCountChip extends StatelessWidget {
  const _FilterCountChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final label = count == 1 ? '1 filtro' : '$count filtros';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: colors.warning.surface,
          border: Border.all(color: colors.warning.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.warning.base,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.warning.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: context.appColors.sectionBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _CompactExportButton extends StatefulWidget {
  const _CompactExportButton({
    required this.onExportPdf,
    required this.onExportCsv,
  });

  final Future<void> Function(ReportExportMode mode) onExportPdf;
  final Future<void> Function(ReportExportMode mode) onExportCsv;

  @override
  State<_CompactExportButton> createState() => _CompactExportButtonState();
}

class _CompactExportButtonState extends State<_CompactExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ReportExportMenu(
      enabled: !_busy,
      onSelected: _handleSelection,
      child: IgnorePointer(
        child: _ToolbarIconButton(
          tooltip: _busy ? 'Exportando...' : 'Exportar',
          icon: _busy
              ? Icons.hourglass_top_rounded
              : Icons.file_download_outlined,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _handleSelection(ReportExportSelection selection) async {
    setState(() => _busy = true);
    try {
      switch (selection.format) {
        case ReportExportFormat.pdf:
          await widget.onExportPdf(selection.mode);
        case ReportExportFormat.csv:
          await widget.onExportCsv(selection.mode);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nao foi possivel exportar o relatorio: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

enum _ToolbarActionType { clear, reset, preset }

class _ToolbarAction {
  const _ToolbarAction(this.type, {this.presetId});

  final _ToolbarActionType type;
  final String? presetId;
}

class _ToolbarOverflowButton extends StatelessWidget {
  const _ToolbarOverflowButton({
    required this.presets,
    required this.activePresetId,
    required this.canClear,
    required this.canReset,
    required this.onSelected,
  });

  final List<ReportFilterPreset> presets;
  final String? activePresetId;
  final bool canClear;
  final bool canReset;
  final ValueChanged<_ToolbarAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ToolbarAction>(
      tooltip: 'Mais opcoes',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final preset in presets)
          PopupMenuItem(
            value: _ToolbarAction(
              _ToolbarActionType.preset,
              presetId: preset.id,
            ),
            child: _MenuRow(
              icon: activePresetId == preset.id
                  ? Icons.check_rounded
                  : Icons.bolt_outlined,
              label: preset.label,
            ),
          ),
        if (presets.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(
          enabled: canClear,
          value: const _ToolbarAction(_ToolbarActionType.clear),
          child: const _MenuRow(
            icon: Icons.filter_alt_off_outlined,
            label: 'Limpar filtros',
          ),
        ),
        PopupMenuItem(
          enabled: canReset,
          value: const _ToolbarAction(_ToolbarActionType.reset),
          child: const _MenuRow(
            icon: Icons.restart_alt_rounded,
            label: 'Restaurar padrao',
          ),
        ),
      ],
      child: IgnorePointer(
        child: _ToolbarIconButton(
          tooltip: 'Mais opcoes',
          icon: Icons.more_horiz_rounded,
          onPressed: () {},
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Flexible(child: Text(label)),
      ],
    );
  }
}
