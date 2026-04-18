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
import '../../data/support/report_donut_support.dart';
import '../../data/support/report_export_mapper.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_breakdown_row.dart';
import '../../domain/entities/report_cashflow_point.dart';
import '../../domain/entities/report_cashflow_summary.dart';
import '../../domain/entities/report_donut_slice.dart';
import '../../domain/entities/report_filter.dart';
import '../providers/report_providers.dart';
import '../widgets/report_donut_chart_card.dart';
import '../widgets/report_empty_state.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';
import '../widgets/report_period_bar.dart';

class CashReportsPage extends ConsumerWidget {
  const CashReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final cashflowAsync = ref.watch(cashflowReportProvider);
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorio de caixa')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(cashflowReportProvider.future);
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
              title: 'Caixa real do periodo',
              subtitle:
                  'Separacao clara entre recebimentos, entradas manuais, saidas e fluxo liquido.',
              badgeLabel: 'Caixa',
              badgeIcon: Icons.payments_outlined,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            const ReportPeriodBar(
              showGrouping: true,
              groupingOptions: [
                ReportGrouping.day,
                ReportGrouping.week,
                ReportGrouping.month,
              ],
            ),
            SizedBox(height: layout.sectionGap),
            ReportFilterToolbar(
              page: ReportPageKey.cash,
              onExportPdf: (mode) => _exportPdf(ref, mode),
              onExportCsv: (mode) => _exportCsv(ref, mode),
            ),
            SizedBox(height: layout.sectionGap),
            cashflowAsync.when(
              data: (cashflow) => Column(
                children: [
                  ReportKpiGrid(
                    items: [
                      ReportKpiItem(
                        label: 'Total recebido',
                        value: AppFormatters.currencyFromCents(
                          cashflow.totalReceivedCents,
                        ),
                        caption: 'Vendas e fiado recebido',
                        icon: Icons.arrow_downward_rounded,
                        accentColor: context.appColors.cashflowPositive.base,
                      ),
                      ReportKpiItem(
                        label: 'Fiado recebido',
                        value: AppFormatters.currencyFromCents(
                          cashflow.fiadoReceiptsCents,
                        ),
                        caption: 'Recebimentos de notas a prazo',
                        icon: Icons.receipt_long_outlined,
                        accentColor: context.appColors.info.base,
                      ),
                      ReportKpiItem(
                        label: 'Entradas manuais',
                        value: AppFormatters.currencyFromCents(
                          cashflow.manualEntriesCents,
                        ),
                        caption: 'Suprimentos e ajustes positivos',
                        icon: Icons.add_circle_outline,
                        accentColor: context.appColors.interactive.base,
                      ),
                      ReportKpiItem(
                        label: 'Saidas',
                        value: AppFormatters.currencyFromCents(
                          cashflow.outflowsCents,
                        ),
                        caption: 'Tudo que saiu do caixa',
                        icon: Icons.arrow_upward_rounded,
                        accentColor: context.appColors.cashflowNegative.base,
                      ),
                      ReportKpiItem(
                        label: 'Retiradas',
                        value: AppFormatters.currencyFromCents(
                          cashflow.withdrawalsCents,
                        ),
                        caption: 'Sangrias registradas',
                        icon: Icons.remove_circle_outline,
                        accentColor: context.appColors.warning.base,
                      ),
                      ReportKpiItem(
                        label: 'Fluxo liquido',
                        value: AppFormatters.currencyFromCents(
                          cashflow.netFlowCents,
                        ),
                        caption: 'Saldo do periodo em caixa',
                        icon: Icons.account_balance_wallet_outlined,
                        accentColor: cashflow.netFlowCents < 0
                            ? context.appColors.cashflowNegative.base
                            : context.appColors.success.base,
                      ),
                    ],
                  ),
                  SizedBox(height: layout.sectionGap),
                  if (filter.focus == ReportFocus.cashNetFlow) ...[
                    _CashTimelineCard(points: cashflow.timeline),
                    SizedBox(height: layout.sectionGap),
                  ],
                  ReportDonutChartCard(
                    title: 'Entradas por origem',
                    subtitle: 'De onde veio o caixa positivo no periodo.',
                    slices: _buildEntryOriginSlices(context, cashflow),
                    totalLabel: 'Entradas',
                    totalValue: AppFormatters.currencyFromCents(
                      cashflow.totalReceivedCents + cashflow.manualEntriesCents,
                    ),
                    insight: _buildEntryOriginInsight(cashflow),
                    emptyTitle: 'Sem entradas no periodo',
                    emptyMessage:
                        'As origens de entrada vao aparecer aqui quando houver movimento.',
                  ),
                  SizedBox(height: layout.sectionGap),
                  AppSectionCard(
                    title: 'Resumo por tipo de movimento',
                    subtitle: 'Quanto cada tipo pesou no caixa.',
                    padding: const EdgeInsets.all(14),
                    child: cashflow.movementRows.isEmpty
                        ? const ReportEmptyState(
                            title: 'Sem movimentos',
                            message:
                                'Os tipos de movimento vao aparecer aqui conforme o periodo.',
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < cashflow.movementRows.length;
                                index++
                              ) ...[
                                _BreakdownRowTile(
                                  row: cashflow.movementRows[index],
                                ),
                                if (index < cashflow.movementRows.length - 1)
                                  const Divider(height: 18),
                              ],
                            ],
                          ),
                  ),
                  if (filter.focus != ReportFocus.cashNetFlow) ...[
                    SizedBox(height: layout.sectionGap),
                    _CashTimelineCard(points: cashflow.timeline),
                  ],
                ],
              ),
              loading: () => const AppStateCard(
                title: 'Carregando caixa',
                message: 'Consolidando os movimentos do periodo.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar o caixa',
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
    final cashflow = await ref.read(cashflowReportProvider.future);

    return ReportExportMapper.cash(
      businessName: businessName,
      generatedAt: DateTime.now(),
      mode: mode,
      filter: filter,
      labels: labels,
      cashflow: cashflow,
    );
  }

  List<ReportDonutSlice> _buildEntryOriginSlices(
    BuildContext context,
    ReportCashflowSummary cashflow,
  ) {
    final colors = context.appColors;
    final salesEntries =
        (cashflow.totalReceivedCents - cashflow.fiadoReceiptsCents).clamp(
          0,
          cashflow.totalReceivedCents,
        );

    return ReportDonutSupport.normalize(
      [
        ReportDonutSlice(
          label: 'Vendas',
          value: salesEntries.toDouble(),
          percentage: 0,
          color: colors.sales.base,
          formattedValue: '',
        ),
        ReportDonutSlice(
          label: 'Recebimento de fiado',
          value: cashflow.fiadoReceiptsCents.toDouble(),
          percentage: 0,
          color: colors.cashflowPositive.base,
          formattedValue: '',
        ),
        ReportDonutSlice(
          label: 'Entradas manuais',
          value: cashflow.manualEntriesCents.toDouble(),
          percentage: 0,
          color: colors.info.base,
          formattedValue: '',
        ),
      ],
      formatValue: (value) => AppFormatters.currencyFromCents(value.round()),
      groupedColor: colors.disabled.base,
    );
  }

  String _buildEntryOriginInsight(ReportCashflowSummary cashflow) {
    final totalEntries =
        cashflow.totalReceivedCents + cashflow.manualEntriesCents;
    if (totalEntries <= 0) {
      return 'Ainda nao ha entradas registradas no periodo.';
    }

    final salesEntries =
        (cashflow.totalReceivedCents - cashflow.fiadoReceiptsCents).clamp(
          0,
          cashflow.totalReceivedCents,
        );
    final salesPercentage = ReportDonutSupport.formatPercentage(
      ReportDonutSupport.percentageFromValue(
        salesEntries.toDouble(),
        totalEntries.toDouble(),
      ),
    );

    if (salesEntries > cashflow.manualEntriesCents &&
        salesEntries > cashflow.fiadoReceiptsCents) {
      return 'As vendas respondem por $salesPercentage das entradas do caixa.';
    }
    if (cashflow.manualEntriesCents >= salesEntries &&
        cashflow.manualEntriesCents >= cashflow.fiadoReceiptsCents) {
      return 'As entradas manuais lideram o caixa deste periodo.';
    }
    return 'O recebimento de fiado tem peso relevante nas entradas do caixa.';
  }
}

class _BreakdownRowTile extends StatelessWidget {
  const _BreakdownRowTile({required this.row});

  final ReportBreakdownRow row;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            row.label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Text('${row.count} mov.'),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(row.amountCents),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _CashTimelineCard extends StatelessWidget {
  const _CashTimelineCard({required this.points});

  final List<ReportCashflowPoint> points;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Linha do tempo do caixa',
      subtitle: 'Entradas, saidas e saldo por faixa do periodo.',
      padding: const EdgeInsets.all(14),
      child: points.isEmpty
          ? const ReportEmptyState(
              title: 'Sem linha do tempo',
              message:
                  'Os movimentos do caixa vao aparecer aqui quando houver registros.',
            )
          : Column(
              children: [
                for (var index = 0; index < points.length; index++) ...[
                  _CashTimelineRow(point: points[index]),
                  if (index < points.length - 1) const Divider(height: 18),
                ],
              ],
            ),
    );
  }
}

class _CashTimelineRow extends StatelessWidget {
  const _CashTimelineRow({required this.point});

  final ReportCashflowPoint point;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            point.label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            'Entradas ${AppFormatters.currencyFromCents(point.inflowCents)} - Saidas ${AppFormatters.currencyFromCents(point.outflowCents)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(point.netCents),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: point.netCents < 0
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
      ],
    );
  }
}
