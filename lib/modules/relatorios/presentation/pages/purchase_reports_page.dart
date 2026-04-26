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
import '../../domain/entities/report_breakdown_row.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_purchase_summary.dart';
import '../providers/report_providers.dart';
import '../widgets/report_data_origin_banner.dart';
import '../widgets/report_empty_state.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';

class PurchaseReportsPage extends ConsumerWidget {
  const PurchaseReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final purchaseAsync = ref.watch(purchaseSummaryReportProvider);
    final layout = context.appLayout;
    final controller = ref.read(reportFilterProvider.notifier);

    void applyDrilldown({
      required ReportFilter nextFilter,
      required String sourceLabel,
      required String message,
      bool isFocusOnly = false,
    }) {
      controller.applyDrilldown(
        page: ReportPageKey.purchases,
        nextFilter: nextFilter,
        sourcePage: ReportPageKey.purchases,
        sourceLabel: sourceLabel,
        message: message,
        isFocusOnly: isFocusOnly,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorio de compras')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(purchaseSummaryReportProvider.future);
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
              title: 'Compras do periodo',
              subtitle:
                  'Entradas por fornecedor, valor pendente, itens mais comprados e reposicao por variante.',
              badgeLabel: 'Compras',
              badgeIcon: Icons.local_shipping_outlined,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            ReportFilterToolbar(
              page: ReportPageKey.purchases,
              onExportPdf: (mode) => _exportPdf(ref, mode),
              onExportCsv: (mode) => _exportCsv(ref, mode),
            ),
            const ReportDataOriginBanner(page: ReportPageKey.purchases),
            SizedBox(height: layout.sectionGap),
            purchaseAsync.when(
              data: (summary) => Column(
                children: [
                  ...[
                    ReportKpiGrid(
                      items: [
                        ReportKpiItem(
                          label: 'Total comprado',
                          value: AppFormatters.currencyFromCents(
                            summary.totalPurchasedCents,
                          ),
                          caption:
                              '${summary.purchasesCount} compra(s) no periodo',
                          icon: Icons.shopping_cart_outlined,
                          accentColor: context.appColors.info.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(clearFocus: true),
                            sourceLabel: 'KPI Total comprado',
                            message:
                                'A leitura volta para a visao geral de compras no mesmo periodo.',
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Total pendente',
                          value: AppFormatters.currencyFromCents(
                            summary.totalPendingCents,
                          ),
                          caption: 'Compromissos ainda em aberto',
                          icon: Icons.schedule_outlined,
                          accentColor: context.appColors.warning.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(
                              focus: ReportFocus.purchasesSuppliers,
                            ),
                            sourceLabel: 'KPI Total pendente',
                            message:
                                'A leitura passa a destacar fornecedores e compromissos em aberto.',
                            isFocusOnly: true,
                          ),
                        ),
                        ReportKpiItem(
                          label: 'Total pago',
                          value: AppFormatters.currencyFromCents(
                            summary.totalPaidCents,
                          ),
                          caption: 'Pagamentos registrados no periodo',
                          icon: Icons.price_check_outlined,
                          accentColor: context.appColors.cashflowPositive.base,
                          onTap: () => applyDrilldown(
                            nextFilter: filter.copyWith(
                              focus: ReportFocus.purchasesSuppliers,
                            ),
                            sourceLabel: 'KPI Total pago',
                            message:
                                'A leitura passa a destacar quem concentrou os pagamentos do periodo.',
                            isFocusOnly: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: layout.sectionGap),
                    ..._orderedSections(
                      context,
                      summary: summary,
                      filter: filter,
                      onDrilldown: applyDrilldown,
                    ),
                  ],
                ],
              ),
              loading: () => const AppStateCard(
                title: 'Carregando compras',
                message: 'Consolidando os dados do periodo.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar compras',
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

  List<Widget> _orderedSections(
    BuildContext context, {
    required ReportPurchaseSummary summary,
    required ReportFilter filter,
    required void Function({
      required ReportFilter nextFilter,
      required String sourceLabel,
      required String message,
      bool isFocusOnly,
    })
    onDrilldown,
  }) {
    final supplierSection = _BreakdownSection(
      title: 'Compras por fornecedor',
      subtitle:
          'Quem concentrou mais abastecimento no periodo. Toque em uma linha para abrir o detalhe.',
      rows: summary.supplierRows,
      emptyTitle: 'Sem fornecedores no periodo',
      emptyMessage: 'Os fornecedores com compras vao aparecer aqui.',
      onRowTap: (row) => onDrilldown(
        nextFilter: row.primaryId == null
            ? filter.copyWith(focus: ReportFocus.purchasesSuppliers)
            : filter.copyWith(
                supplierId: row.primaryId,
                focus: ReportFocus.purchasesSuppliers,
              ),
        sourceLabel: 'Fornecedor: ${row.label}',
        message: row.primaryId == null
            ? 'A leitura destaca fornecedores sem criar um filtro adicional fora da base atual.'
            : 'A leitura foi filtrada para o fornecedor ${row.label} no mesmo periodo.',
        isFocusOnly: row.primaryId == null,
      ),
    );
    final itemsSection = _BreakdownSection(
      title: 'Itens mais comprados',
      subtitle:
          'Produtos e insumos com maior peso nas compras. Toque em uma linha para abrir o detalhe.',
      rows: summary.topItems,
      emptyTitle: 'Sem itens comprados',
      emptyMessage: 'Os itens comprados vao aparecer aqui.',
      showQuantity: true,
      onRowTap: (row) => onDrilldown(
        nextFilter: row.primaryId == null
            ? filter.copyWith(focus: ReportFocus.purchasesItems)
            : filter.copyWith(
                productId: row.primaryId,
                clearVariantId: true,
                focus: ReportFocus.purchasesItems,
              ),
        sourceLabel: 'Item comprado: ${row.label}',
        message: row.primaryId == null
            ? 'A leitura destaca itens comprados sem criar um filtro adicional fora da base atual.'
            : 'A leitura foi filtrada para ${row.label} no mesmo periodo de compras.',
        isFocusOnly: row.primaryId == null,
      ),
    );
    final replenishmentSection = _BreakdownSection(
      title: 'Reposicao por variante',
      subtitle:
          'Leitura rapida das variantes que mais entraram. Toque em uma linha para abrir o detalhe.',
      rows: summary.replenishmentRows,
      emptyTitle: 'Sem reposicao por variante',
      emptyMessage: 'As variantes compradas vao aparecer aqui.',
      showQuantity: true,
      onRowTap: (row) => onDrilldown(
        nextFilter: row.primaryId == null
            ? filter.copyWith(focus: ReportFocus.purchasesReplenishment)
            : filter.copyWith(
                productId: row.primaryId,
                variantId: row.secondaryId,
                clearVariantId: row.secondaryId == null,
                focus: ReportFocus.purchasesReplenishment,
              ),
        sourceLabel: 'Reposicao: ${row.label}',
        message: row.primaryId == null
            ? 'A leitura destaca reposicao sem criar um filtro adicional fora da base atual.'
            : 'A leitura foi filtrada para a reposicao escolhida no mesmo periodo.',
        isFocusOnly: row.primaryId == null,
      ),
    );
    final sections = switch (filter.focus) {
      ReportFocus.purchasesItems => <Widget>[
        itemsSection,
        supplierSection,
        replenishmentSection,
      ],
      ReportFocus.purchasesReplenishment => <Widget>[
        replenishmentSection,
        supplierSection,
        itemsSection,
      ],
      _ => <Widget>[supplierSection, itemsSection, replenishmentSection],
    };

    return [
      for (var index = 0; index < sections.length; index++) ...[
        if (index > 0) SizedBox(height: context.appLayout.sectionGap),
        sections[index],
      ],
    ];
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
    final summary = await ref.read(purchaseSummaryReportProvider.future);

    return ReportExportMapper.purchases(
      businessName: businessName,
      generatedAt: DateTime.now(),
      mode: mode,
      filter: filter,
      labels: labels,
      summary: summary,
      navigationSummary: ref
          .read(reportPageSessionProvider)
          .drilldownFor(ReportPageKey.purchases)
          ?.exportLabel,
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.emptyTitle,
    required this.emptyMessage,
    this.showQuantity = false,
    this.onRowTap,
  });

  final String title;
  final String subtitle;
  final List<ReportBreakdownRow> rows;
  final String emptyTitle;
  final String emptyMessage;
  final bool showQuantity;
  final ValueChanged<ReportBreakdownRow>? onRowTap;

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
                                  rows[index].label,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (showQuantity)
                                  Text(
                                    'Quantidade ${AppFormatters.quantityFromMil(rows[index].quantityMil)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  )
                                else
                                  Text(
                                    '${rows[index].count} registro(s)',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            AppFormatters.currencyFromCents(
                              rows[index].amountCents,
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
