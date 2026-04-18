import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../estoque/domain/entities/inventory_movement.dart';
import '../../data/support/report_donut_support.dart';
import '../../data/support/report_export_mapper.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_donut_slice.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_inventory_health_summary.dart';
import '../providers/report_providers.dart';
import '../widgets/inventory_health_card.dart';
import '../widgets/report_donut_chart_card.dart';
import '../widgets/report_empty_state.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';
import '../widgets/report_period_bar.dart';

class InventoryReportsPage extends ConsumerWidget {
  const InventoryReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final inventoryAsync = ref.watch(inventoryHealthReportProvider);
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorio de estoque')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(inventoryHealthReportProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space5,
            layout.pagePadding,
            layout.pagePadding,
          ),
          children: [
            const AppPageHeader(
              title: 'Visao gerencial do estoque',
              subtitle:
                  'Itens criticos, valor do estoque e movimentacoes mais relevantes do periodo.',
              badgeLabel: 'Estoque',
              badgeIcon: Icons.inventory_2_outlined,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            const ReportPeriodBar(),
            SizedBox(height: layout.sectionGap),
            ReportFilterToolbar(
              page: ReportPageKey.inventory,
              onExportPdf: (mode) => _exportPdf(ref, mode),
              onExportCsv: (mode) => _exportCsv(ref, mode),
            ),
            SizedBox(height: layout.sectionGap),
            inventoryAsync.when(
              data: (summary) => Column(
                children: [
                  ReportKpiGrid(
                    items: [
                      ReportKpiItem(
                        label: 'Itens zerados',
                        value: '${summary.zeroedItemsCount}',
                        caption: 'Sem saldo no momento',
                        icon: Icons.remove_shopping_cart_outlined,
                        accentColor: context.appColors.cashflowNegative.base,
                      ),
                      ReportKpiItem(
                        label: 'Abaixo do minimo',
                        value: '${summary.belowMinimumItemsCount}',
                        caption: 'Pedem reposicao',
                        icon: Icons.priority_high_rounded,
                        accentColor: context.appColors.warning.base,
                      ),
                      ReportKpiItem(
                        label: 'Valor a custo',
                        value: AppFormatters.currencyFromCents(
                          summary.inventoryCostValueCents,
                        ),
                        caption: 'Estimativa pelo custo cadastrado',
                        icon: Icons.payments_outlined,
                        accentColor: context.appColors.info.base,
                      ),
                      ReportKpiItem(
                        label: 'Valor a venda',
                        value: AppFormatters.currencyFromCents(
                          summary.inventorySaleValueCents,
                        ),
                        caption: 'Potencial bruto em estoque',
                        icon: Icons.local_offer_outlined,
                        accentColor: context.appColors.sales.base,
                      ),
                      ReportKpiItem(
                        label: 'Divergencias',
                        value: '${summary.divergenceItemsCount}',
                        caption: 'Diferencas em inventario fisico',
                        icon: Icons.fact_check_outlined,
                        accentColor: context.appColors.interactive.base,
                      ),
                    ],
                  ),
                  SizedBox(height: layout.sectionGap),
                  ReportDonutChartCard(
                    title: 'Saude do estoque',
                    subtitle:
                        'Leitura visual entre itens saudaveis e pontos de atencao.',
                    slices: _buildHealthSlices(context, summary),
                    totalLabel: 'Itens monitorados',
                    totalValue: '${summary.totalItemsCount}',
                    insight: _buildHealthInsight(summary),
                    emptyTitle: 'Sem estoque monitorado',
                    emptyMessage:
                        'Os indicadores de saude vao aparecer aqui quando houver itens cadastrados.',
                  ),
                  SizedBox(height: layout.sectionGap),
                  _buildHealthCard(summary, filter),
                  SizedBox(height: layout.sectionGap),
                  AppSectionCard(
                    title: 'Itens mais movimentados',
                    subtitle: 'Quem mais girou no periodo selecionado.',
                    padding: const EdgeInsets.all(14),
                    child: summary.mostMovedItems.isEmpty
                        ? const ReportEmptyState(
                            title: 'Sem giro relevante',
                            message:
                                'Os itens com mais movimentacao vao aparecer aqui.',
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < summary.mostMovedItems.length;
                                index++
                              ) ...[
                                _MovementItemRow(
                                  row: summary.mostMovedItems[index],
                                ),
                                if (index < summary.mostMovedItems.length - 1)
                                  const Divider(height: 18),
                              ],
                            ],
                          ),
                  ),
                  SizedBox(height: layout.sectionGap),
                  AppSectionCard(
                    title: 'Ultimas movimentacoes relevantes',
                    subtitle: 'Recorte mais recente para leitura rapida.',
                    padding: const EdgeInsets.all(14),
                    child: summary.recentMovements.isEmpty
                        ? const ReportEmptyState(
                            title: 'Sem movimentacoes no periodo',
                            message:
                                'As ultimas entradas e saidas vao aparecer aqui.',
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < summary.recentMovements.length;
                                index++
                              ) ...[
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    summary.recentMovements[index].displayName,
                                  ),
                                  subtitle: Text(
                                    '${summary.recentMovements[index].movementType.label} - ${AppFormatters.shortDateTime(summary.recentMovements[index].createdAt)}',
                                  ),
                                  trailing: Text(
                                    AppFormatters.quantityFromMil(
                                      summary
                                          .recentMovements[index]
                                          .quantityDeltaMil
                                          .abs(),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                if (index < summary.recentMovements.length - 1)
                                  const Divider(height: 16),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
              loading: () => const AppStateCard(
                title: 'Carregando estoque',
                message: 'Consolidando a saude do estoque do periodo.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar estoque',
                message: '$error',
                tone: AppStateTone.error,
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(WidgetRef ref, ReportExportMode mode) async {
    final document = await _buildExportDocument(ref, mode);
    await ref.read(reportExportPdfSupportProvider).share(document);
  }

  Future<void> _exportCsv(WidgetRef ref, ReportExportMode mode) async {
    final document = await _buildExportDocument(ref, mode);
    await ref.read(reportExportCsvSupportProvider).share(document);
  }

  Future<ReportExportDocument> _buildExportDocument(
    WidgetRef ref,
    ReportExportMode mode,
  ) async {
    final businessName = ref.read(currentCompanyContextProvider).displayName;
    final filter = ref.read(reportFilterProvider);
    final labels = await ref.read(reportFilterOptionLabelsProvider.future);
    final summary = await ref.read(inventoryHealthReportProvider.future);

    return ReportExportMapper.inventory(
      businessName: businessName,
      generatedAt: DateTime.now(),
      mode: mode,
      filter: filter,
      labels: labels,
      summary: summary,
    );
  }

  List<ReportDonutSlice> _buildHealthSlices(
    BuildContext context,
    ReportInventoryHealthSummary summary,
  ) {
    final colors = context.appColors;
    return ReportDonutSupport.normalize(
      [
        ReportDonutSlice(
          label: 'Saudavel',
          value: summary.healthyItemsCount.toDouble(),
          percentage: 0,
          color: colors.cashflowPositive.base,
          formattedValue: '',
        ),
        ReportDonutSlice(
          label: 'Abaixo do minimo',
          value: summary.belowMinimumOnlyItemsCount.toDouble(),
          percentage: 0,
          color: colors.stockLow.base,
          formattedValue: '',
        ),
        ReportDonutSlice(
          label: 'Zerado',
          value: summary.zeroedItemsCount.toDouble(),
          percentage: 0,
          color: colors.cashflowNegative.base,
          formattedValue: '',
        ),
      ],
      formatValue: (value) => '${value.round()} item(ns)',
      groupedColor: colors.disabled.base,
    );
  }

  String _buildHealthInsight(ReportInventoryHealthSummary summary) {
    if (summary.totalItemsCount <= 0) {
      return 'Ainda nao ha itens suficientes para medir a saude do estoque.';
    }
    final alertCount = summary.alertItemsCount;
    if (alertCount <= 0) {
      return 'Nenhum item monitorado esta em alerta neste momento.';
    }

    final alertPercentage = ReportDonutSupport.formatPercentage(
      ReportDonutSupport.percentageFromValue(
        alertCount.toDouble(),
        summary.totalItemsCount.toDouble(),
      ),
    );
    if (summary.divergenceItemsCount > 0) {
      return '$alertPercentage do estoque esta em alerta e parte do inventario ainda tem divergencia.';
    }
    return '$alertPercentage do estoque esta em alerta.';
  }

  InventoryHealthCard _buildHealthCard(
    ReportInventoryHealthSummary summary,
    ReportFilter filter,
  ) {
    final visibleItems = switch (filter.focus) {
      ReportFocus.inventoryZeroed => summary.criticalItems
          .where((item) => item.isZeroed)
          .toList(growable: false),
      _ => summary.criticalItems,
    };
    final subtitle = switch (filter.focus) {
      ReportFocus.inventoryZeroed =>
        'Somente os itens zerados ficam em destaque nesta leitura.',
      ReportFocus.inventoryDivergence =>
        'A divergencia continua visivel no quadro rapido sem recalcular o estoque.',
      ReportFocus.inventoryAlerts =>
        'Alertas de estoque e divergencias aparecem em primeiro plano.',
      _ => 'Itens que pedem atencao agora.',
    };
    return InventoryHealthCard(
      summary: summary,
      visibleCriticalItems: visibleItems,
      subtitle: subtitle,
    );
  }
}

class _MovementItemRow extends StatelessWidget {
  const _MovementItemRow({required this.row});

  final dynamic row;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            row.label as String,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          '${AppFormatters.quantityFromMil(row.quantityMil as int)} mov.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
