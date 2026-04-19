import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../data/support/report_donut_support.dart';
import '../../data/support/report_export_mapper.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_donut_slice.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_profitability_row.dart';
import '../providers/report_providers.dart';
import '../widgets/profitability_table.dart';
import '../widgets/report_donut_chart_card.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';

class ProfitabilityReportsPage extends ConsumerWidget {
  const ProfitabilityReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final profitabilityAsync = ref.watch(profitabilityReportProvider);
    final profitabilityByCategoryAsync = ref.watch(
      profitabilityCategoryReportProvider,
    );
    final layout = context.appLayout;
    final controller = ref.read(reportFilterProvider.notifier);

    void applyDrilldown({
      required ReportFilter nextFilter,
      required String sourceLabel,
      required String message,
      bool isFocusOnly = false,
    }) {
      controller.applyDrilldown(
        page: ReportPageKey.profitability,
        nextFilter: nextFilter,
        sourcePage: ReportPageKey.profitability,
        sourceLabel: sourceLabel,
        message: message,
        isFocusOnly: isFocusOnly,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorio de lucratividade')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(profitabilityReportProvider.future);
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
              title: 'Margem e lucro',
              subtitle:
                  'Receita, custo, lucro e margem agrupados por produto, variante ou categoria.',
              badgeLabel: 'Lucratividade',
              badgeIcon: Icons.show_chart_rounded,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            ReportFilterToolbar(
              page: ReportPageKey.profitability,
              onExportPdf: (mode) => _exportPdf(ref, mode),
              onExportCsv: (mode) => _exportCsv(ref, mode),
            ),
            SizedBox(height: layout.sectionGap),
            profitabilityAsync.when(
              data: (rows) {
                final metrics = _summarize(rows);
                final visibleRows = filter.focus == ReportFocus.profitabilityTop
                    ? rows.take(10).toList(growable: false)
                    : rows;
                return Column(
                  children: [
                    ReportKpiGrid(
                      items: [
                        ReportKpiItem(
                          label: 'Receita',
                          value: AppFormatters.currencyFromCents(
                            metrics.revenueCents,
                          ),
                          caption: 'Total vendido no agrupamento atual',
                          icon: Icons.sell_outlined,
                          accentColor: context.appColors.sales.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(clearFocus: true),
                            sourceLabel: 'KPI Receita',
                            message:
                                'A leitura volta para a visao principal da lucratividade no agrupamento atual.',
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Custo',
                          value: AppFormatters.currencyFromCents(
                            metrics.costCents,
                          ),
                          caption: 'Custo somado dos itens vendidos',
                          icon: Icons.payments_outlined,
                          accentColor: context.appColors.info.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(clearFocus: true),
                            sourceLabel: 'KPI Custo',
                            message:
                                'A leitura volta para a visao principal de custo no agrupamento atual.',
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Lucro',
                          value: AppFormatters.currencyFromCents(
                            metrics.profitCents,
                          ),
                          caption: 'Resultado bruto do periodo',
                          icon: Icons.trending_up_rounded,
                          accentColor: metrics.profitCents < 0
                              ? context.appColors.cashflowNegative.base
                              : context.appColors.success.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(
                              grouping: ReportGrouping.product,
                              focus: ReportFocus.profitabilityTop,
                            ),
                            sourceLabel: 'KPI Lucro',
                            message:
                                'A leitura passa a destacar os itens mais lucrativos na mesma base atual.',
                            isFocusOnly: true,
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Margem media',
                          value: '${metrics.marginPercent.toStringAsFixed(1)}%',
                          caption: 'Media ponderada pela receita',
                          icon: Icons.percent_rounded,
                          accentColor: context.appColors.interactive.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(clearFocus: true),
                            sourceLabel: 'KPI Margem media',
                            message:
                                'A leitura volta para a visao principal de margem no agrupamento atual.',
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Quantidade vendida',
                          value: AppFormatters.quantityFromMil(
                            metrics.quantityMil,
                          ),
                          caption: 'Volume vendido no periodo',
                          icon: Icons.inventory_2_outlined,
                          accentColor: context.appColors.warning.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(clearFocus: true),
                            sourceLabel: 'KPI Quantidade vendida',
                            message:
                                'A leitura continua no mesmo agrupamento para comparar volume e resultado.',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: layout.sectionGap),
                    profitabilityByCategoryAsync.when(
                      data: (categoryRows) {
                        final slices = _buildCategorySlices(
                          context,
                          categoryRows,
                        );
                        return ReportDonutChartCard(
                          title: 'Lucro por categoria',
                          subtitle:
                              'Participacao das categorias com lucro positivo. Toque na legenda para abrir a categoria.',
                          slices: slices,
                          totalLabel: 'Lucro positivo',
                          totalValue: AppFormatters.currencyFromCents(
                            slices.fold<int>(
                              0,
                              (total, slice) => total + slice.value.round(),
                            ),
                          ),
                          insight: _buildCategoryInsight(slices),
                          onSliceTap: (slice) {
                            final match = categoryRows.firstWhere(
                              (row) => row.label == slice.label,
                              orElse: () => const ReportProfitabilityRow(
                                grouping: ReportGrouping.category,
                                label: '',
                                quantityMil: 0,
                                revenueCents: 0,
                                costCents: 0,
                                profitCents: 0,
                                marginBasisPoints: 0,
                              ),
                            );
                            if (match.categoryId == null) {
                              return;
                            }
                            applyDrilldown(
                              nextFilter: filter.copyWith(
                                categoryId: match.categoryId,
                                clearProductId: true,
                                clearVariantId: true,
                                grouping: ReportGrouping.product,
                                clearFocus: true,
                              ),
                              sourceLabel: 'Categoria: ${slice.label}',
                              message:
                                  'A leitura foi filtrada para a categoria ${slice.label} e abriu o detalhamento por produto.',
                            );
                          },
                          emptyTitle: 'Sem lucro positivo por categoria',
                          emptyMessage:
                              'Quando houver lucro positivo no periodo, a distribuicao por categoria aparece aqui.',
                        );
                      },
                      loading: () => const AppStateCard(
                        title: 'Carregando lucro por categoria',
                        message: 'Organizando a participacao das categorias.',
                        tone: AppStateTone.loading,
                        compact: true,
                      ),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                    SizedBox(height: layout.sectionGap),
                    ProfitabilityTable(
                      rows: visibleRows,
                      title: filter.focus == ReportFocus.profitabilityTop
                          ? 'Mais lucrativos'
                          : 'Lucratividade',
                      subtitle: filter.focus == ReportFocus.profitabilityTop
                          ? 'Top itens por lucro com a mesma base da tela.'
                          : 'Receita, custo e margem por item.',
                      onRowTap: (row) {
                        switch (row.grouping) {
                          case ReportGrouping.category:
                            if (row.categoryId == null) {
                              return;
                            }
                            applyDrilldown(
                              nextFilter: filter.copyWith(
                                categoryId: row.categoryId,
                                clearProductId: true,
                                clearVariantId: true,
                                grouping: ReportGrouping.product,
                                clearFocus: true,
                              ),
                              sourceLabel: 'Categoria: ${row.label}',
                              message:
                                  'A leitura foi filtrada para a categoria ${row.label} e abriu o detalhamento por produto.',
                            );
                            return;
                          case ReportGrouping.product:
                            if (row.productId == null) {
                              return;
                            }
                            applyDrilldown(
                              nextFilter: filter.copyWith(
                                productId: row.productId,
                                clearVariantId: true,
                                grouping: ReportGrouping.variant,
                                clearFocus: true,
                              ),
                              sourceLabel: 'Produto: ${row.label}',
                              message:
                                  'A leitura foi filtrada para ${row.label} e abriu o detalhamento por variante.',
                            );
                            return;
                          case ReportGrouping.variant:
                            if (row.variantId == null) {
                              return;
                            }
                            applyDrilldown(
                              nextFilter: filter.copyWith(
                                productId: row.productId,
                                variantId: row.variantId,
                                grouping: ReportGrouping.variant,
                                clearFocus: true,
                              ),
                              sourceLabel: 'Variante: ${row.label}',
                              message:
                                  'A leitura foi filtrada para a variante escolhida no mesmo recorte.',
                            );
                            return;
                          case ReportGrouping.day:
                          case ReportGrouping.week:
                          case ReportGrouping.month:
                          case ReportGrouping.customer:
                          case ReportGrouping.supplier:
                            return;
                        }
                      },
                    ),
                  ],
                );
              },
              loading: () => const AppStateCard(
                title: 'Carregando lucratividade',
                message: 'Montando o ranking de margem e lucro.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar lucratividade',
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
    final rows = await ref.read(profitabilityReportProvider.future);

    return ReportExportMapper.profitability(
      businessName: businessName,
      generatedAt: DateTime.now(),
      mode: mode,
      filter: filter,
      labels: labels,
      rows: rows,
      navigationSummary: ref
          .read(reportPageSessionProvider)
          .drilldownFor(ReportPageKey.profitability)
          ?.exportLabel,
    );
  }

  List<ReportDonutSlice> _buildCategorySlices(
    BuildContext context,
    List<ReportProfitabilityRow> rows,
  ) {
    final colors = context.appColors;
    final palette = <Color>[
      colors.cashflowPositive.base,
      colors.sales.base,
      colors.info.base,
      colors.warning.base,
      colors.interactive.base,
    ];
    final profitableRows = rows
        .where((row) => row.profitCents > 0)
        .toList(growable: false);

    return ReportDonutSupport.normalize(
      [
        for (var index = 0; index < profitableRows.length; index++)
          ReportDonutSlice(
            label: profitableRows[index].label,
            value: profitableRows[index].profitCents.toDouble(),
            percentage: 0,
            color: palette[index % palette.length],
            formattedValue: '',
          ),
      ],
      formatValue: (value) => AppFormatters.currencyFromCents(value.round()),
      groupedColor: colors.disabled.base,
    );
  }

  String? _buildCategoryInsight(List<ReportDonutSlice> slices) {
    return ReportDonutSupport.buildPrimaryInsight(
      slices,
      builder: (leader) {
        if (leader.percentage >= 45) {
          return '${leader.label} concentra boa parte do lucro positivo.';
        }
        return '${leader.label} lidera o lucro positivo entre as categorias.';
      },
    );
  }

  _ProfitabilityMetrics _summarize(List<ReportProfitabilityRow> rows) {
    final revenueCents = rows.fold<int>(
      0,
      (total, row) => total + row.revenueCents,
    );
    final costCents = rows.fold<int>(0, (total, row) => total + row.costCents);
    final profitCents = rows.fold<int>(
      0,
      (total, row) => total + row.profitCents,
    );
    final quantityMil = rows.fold<int>(
      0,
      (total, row) => total + row.quantityMil,
    );
    final marginPercent = revenueCents <= 0
        ? 0.0
        : (profitCents / revenueCents) * 100;

    return _ProfitabilityMetrics(
      revenueCents: revenueCents,
      costCents: costCents,
      profitCents: profitCents,
      quantityMil: quantityMil,
      marginPercent: marginPercent,
    );
  }
}

class _ProfitabilityMetrics {
  const _ProfitabilityMetrics({
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
    required this.quantityMil,
    required this.marginPercent,
  });

  final int revenueCents;
  final int costCents;
  final int profitCents;
  final int quantityMil;
  final double marginPercent;
}
