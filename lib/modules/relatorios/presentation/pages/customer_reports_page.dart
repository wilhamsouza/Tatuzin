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
import '../../data/support/report_export_mapper.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_customer_ranking_row.dart';
import '../providers/report_providers.dart';
import '../widgets/report_data_origin_banner.dart';
import '../widgets/report_empty_state.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';

class CustomerReportsPage extends ConsumerWidget {
  const CustomerReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customerRankingReportProvider);
    final filter = ref.watch(reportFilterProvider);
    final layout = context.appLayout;
    final controller = ref.read(reportFilterProvider.notifier);

    void applyDrilldown({
      required ReportFilter nextFilter,
      required String sourceLabel,
      required String message,
      bool isFocusOnly = false,
    }) {
      controller.applyDrilldown(
        page: ReportPageKey.customers,
        nextFilter: nextFilter,
        sourcePage: ReportPageKey.customers,
        sourceLabel: sourceLabel,
        message: message,
        isFocusOnly: isFocusOnly,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorio de clientes')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(customerRankingReportProvider.future);
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
              title: 'Clientes do periodo',
              subtitle:
                  'Quem mais comprou, quem esta com fiado aberto, haver e menor atividade recente.',
              badgeLabel: 'Clientes',
              badgeIcon: Icons.people_alt_outlined,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            ReportFilterToolbar(
              page: ReportPageKey.customers,
              onExportPdf: (mode) => _exportPdf(ref, mode),
              onExportCsv: (mode) => _exportCsv(ref, mode),
            ),
            const ReportDataOriginBanner(page: ReportPageKey.customers),
            SizedBox(height: layout.sectionGap),
            customersAsync.when(
              data: (customers) {
                final topCustomers = [...customers]
                  ..sort(
                    (a, b) =>
                        b.totalPurchasedCents.compareTo(a.totalPurchasedCents),
                  );
                final openFiado =
                    customers
                        .where((row) => row.hasPendingFiado)
                        .toList(growable: false)
                      ..sort(
                        (a, b) =>
                            b.pendingFiadoCents.compareTo(a.pendingFiadoCents),
                      );
                final withCredit =
                    customers
                        .where((row) => row.hasCredit)
                        .toList(growable: false)
                      ..sort(
                        (a, b) => b.creditBalanceCents.compareTo(
                          a.creditBalanceCents,
                        ),
                      );
                final inactive =
                    customers
                        .where(
                          (row) =>
                              !row.isActive ||
                              row.lastPurchaseAt == null ||
                              row.lastPurchaseAt!.isBefore(filter.start),
                        )
                        .toList(growable: false)
                      ..sort((a, b) {
                        final aDate = a.lastPurchaseAt;
                        final bDate = b.lastPurchaseAt;
                        if (aDate == null && bDate == null) {
                          return a.customerName.compareTo(b.customerName);
                        }
                        if (aDate == null) {
                          return -1;
                        }
                        if (bDate == null) {
                          return 1;
                        }
                        return aDate.compareTo(bDate);
                      });
                final highestPending = openFiado.isEmpty
                    ? null
                    : openFiado.first;
                final topSection = _CustomerSection(
                  title: 'Top clientes por compra',
                  subtitle:
                      'Quem mais puxou faturamento no periodo. Toque em um cliente para abrir o detalhe.',
                  rows: topCustomers.take(10).toList(growable: false),
                  amountBuilder: (row) => row.totalPurchasedCents,
                  emptyTitle: 'Sem compras no periodo',
                  emptyMessage: 'Os clientes com compras vao aparecer aqui.',
                  onRowTap: (row) => applyDrilldown(
                    nextFilter: filter.copyWith(customerId: row.customerId),
                    sourceLabel: 'Cliente: ${row.customerName}',
                    message:
                        'A leitura foi filtrada para ${row.customerName} mantendo o mesmo recorte atual.',
                  ),
                );
                final fiadoSection = _CustomerSection(
                  title: 'Clientes com fiado aberto',
                  subtitle:
                      'Prioridade para cobranca e acompanhamento. Toque em um cliente para abrir o detalhe.',
                  rows: openFiado.take(10).toList(growable: false),
                  amountBuilder: (row) => row.pendingFiadoCents,
                  emptyTitle: 'Nenhum fiado aberto',
                  emptyMessage:
                      'Os saldos pendentes vao aparecer aqui quando existirem.',
                  onRowTap: (row) => applyDrilldown(
                    nextFilter: filter.copyWith(customerId: row.customerId),
                    sourceLabel: 'Cliente com fiado: ${row.customerName}',
                    message:
                        'A leitura foi filtrada para ${row.customerName} e seu saldo pendente no periodo.',
                  ),
                );
                final creditSection = _CustomerSection(
                  title: 'Clientes com haver',
                  subtitle:
                      'Saldo positivo que ainda pode voltar em venda. Toque em um cliente para abrir o detalhe.',
                  rows: withCredit.take(10).toList(growable: false),
                  amountBuilder: (row) => row.creditBalanceCents,
                  emptyTitle: 'Sem haver em aberto',
                  emptyMessage:
                      'Os clientes com saldo positivo vao aparecer aqui.',
                  onRowTap: (row) => applyDrilldown(
                    nextFilter: filter.copyWith(customerId: row.customerId),
                    sourceLabel: 'Cliente com haver: ${row.customerName}',
                    message:
                        'A leitura foi filtrada para ${row.customerName} e seu saldo positivo atual.',
                  ),
                );
                final inactiveSection = _CustomerSection(
                  title: 'Clientes inativos',
                  subtitle:
                      'Quem esta sumido do periodo atual. Toque em um cliente para abrir o detalhe.',
                  rows: inactive.take(10).toList(growable: false),
                  amountBuilder: (row) => row.totalPurchasedCents,
                  emptyTitle: 'Sem clientes inativos',
                  emptyMessage:
                      'Os clientes sem compra recente vao aparecer aqui.',
                  onRowTap: (row) => applyDrilldown(
                    nextFilter: filter.copyWith(customerId: row.customerId),
                    sourceLabel: 'Cliente inativo: ${row.customerName}',
                    message:
                        'A leitura foi filtrada para ${row.customerName} dentro do mesmo periodo.',
                  ),
                );
                final sections = switch (filter.focus) {
                  ReportFocus.customersWithFiado ||
                  ReportFocus.customersPending => <Widget>[
                    fiadoSection,
                    topSection,
                    creditSection,
                    inactiveSection,
                  ],
                  ReportFocus.customersWithCredit => <Widget>[
                    creditSection,
                    topSection,
                    fiadoSection,
                    inactiveSection,
                  ],
                  ReportFocus.customersTopPurchases => <Widget>[
                    topSection,
                    fiadoSection,
                    creditSection,
                    inactiveSection,
                  ],
                  _ => <Widget>[
                    topSection,
                    fiadoSection,
                    creditSection,
                    inactiveSection,
                  ],
                };

                return Column(
                  children: [
                    ReportKpiGrid(
                      items: [
                        ReportKpiItem(
                          label: 'Top clientes ativos',
                          value:
                              '${topCustomers.where((row) => row.hasPurchases).length}',
                          caption: 'Clientes com compras no recorte',
                          icon: Icons.star_border_rounded,
                          accentColor: context.appColors.info.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(
                              focus: ReportFocus.customersTopPurchases,
                            ),
                            sourceLabel: 'KPI Top clientes ativos',
                            message:
                                'A leitura passa a destacar quem mais comprou no recorte atual.',
                            isFocusOnly: true,
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Com fiado aberto',
                          value: '${openFiado.length}',
                          caption: 'Clientes com saldo pendente',
                          icon: Icons.receipt_long_outlined,
                          accentColor: context.appColors.warning.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(
                              focus: ReportFocus.customersWithFiado,
                            ),
                            sourceLabel: 'KPI Com fiado aberto',
                            message:
                                'A leitura passa a priorizar os clientes com saldo pendente.',
                            isFocusOnly: true,
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Com haver',
                          value: '${withCredit.length}',
                          caption: 'Clientes com saldo positivo',
                          icon: Icons.account_balance_wallet_outlined,
                          accentColor: context.appColors.cashflowPositive.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(
                              focus: ReportFocus.customersWithCredit,
                            ),
                            sourceLabel: 'KPI Com haver',
                            message:
                                'A leitura passa a destacar clientes com saldo positivo.',
                            isFocusOnly: true,
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Inativos',
                          value: '${inactive.length}',
                          caption: 'Sem compra recente no recorte',
                          icon: Icons.person_off_outlined,
                          accentColor: context.appColors.interactive.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(clearFocus: true),
                            sourceLabel: 'KPI Inativos',
                            message:
                                'A leitura permanece no mesmo periodo para revisar clientes sem compra recente.',
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Maior saldo pendente',
                          value: highestPending == null
                              ? 'R\$ 0,00'
                              : AppFormatters.currencyFromCents(
                                  highestPending.pendingFiadoCents,
                                ),
                          caption:
                              highestPending?.customerName ??
                              'Nenhum cliente pendente',
                          icon: Icons.warning_amber_rounded,
                          accentColor: context.appColors.cashflowNegative.base,
                          onTap: highestPending == null
                              ? null
                              : () => applyDrilldown(
                                  nextFilter: filter.copyWith(
                                    customerId: highestPending.customerId,
                                    focus: ReportFocus.customersPending,
                                  ),
                                  sourceLabel:
                                      'Maior saldo pendente: ${highestPending.customerName}',
                                  message:
                                      'A leitura foi filtrada para o cliente com maior saldo pendente no recorte atual.',
                                ),
                        ),
                      ],
                    ),
                    for (var index = 0; index < sections.length; index++) ...[
                      SizedBox(height: layout.sectionGap),
                      sections[index],
                    ],
                  ],
                );
              },
              loading: () => const AppStateCard(
                title: 'Carregando clientes',
                message: 'Organizando o ranking do periodo.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar clientes',
                message: '$error',
                tone: AppStateTone.error,
                compact: true,
                actionLabel: 'Tentar novamente',
                onAction: () =>
                    ref.read(appDataRefreshProvider.notifier).state++,
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
    final rows = await ref.read(customerRankingReportProvider.future);

    return ReportExportMapper.customers(
      businessName: businessName,
      generatedAt: DateTime.now(),
      mode: mode,
      filter: filter,
      labels: labels,
      rows: rows,
      navigationSummary: ref
          .read(reportPageSessionProvider)
          .drilldownFor(ReportPageKey.customers)
          ?.exportLabel,
    );
  }
}

class _CustomerSection extends StatelessWidget {
  const _CustomerSection({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.amountBuilder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.onRowTap,
  });

  final String title;
  final String subtitle;
  final List<ReportCustomerRankingRow> rows;
  final int Function(ReportCustomerRankingRow row) amountBuilder;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<ReportCustomerRankingRow>? onRowTap;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.all(14),
      child: rows.isEmpty
          ? ReportEmptyState(title: emptyTitle, message: emptyMessage)
          : Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  InkWell(
                    onTap: onRowTap == null
                        ? null
                        : () => onRowTap!(rows[index]),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rows[index].customerName,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  rows[index].lastPurchaseAt == null
                                      ? 'Sem compra recente'
                                      : 'Ultima compra ${AppFormatters.shortDate(rows[index].lastPurchaseAt!)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            AppFormatters.currencyFromCents(
                              amountBuilder(rows[index]),
                            ),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (onRowTap != null) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (index < rows.length - 1) const Divider(height: 18),
                ],
              ],
            ),
    );
  }
}
