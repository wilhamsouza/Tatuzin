import '../../../../app/core/formatters/app_formatters.dart';
import '../../../estoque/domain/entities/inventory_item.dart';
import '../../../estoque/domain/entities/inventory_movement.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/report_cashflow_summary.dart';
import '../../domain/entities/report_customer_ranking_row.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_inventory_health_summary.dart';
import '../../domain/entities/report_overview_summary.dart';
import '../../domain/entities/report_profitability_row.dart';
import '../../domain/entities/report_purchase_summary.dart';
import '../../domain/entities/report_sales_trend_point.dart';
import '../../domain/entities/report_sold_product_summary.dart';
import '../../domain/entities/report_variant_summary.dart';
import 'report_filter_preset_support.dart';

enum ReportExportMode { summary, detailed }

extension ReportExportModeX on ReportExportMode {
  String get label {
    switch (this) {
      case ReportExportMode.summary:
        return 'Resumo';
      case ReportExportMode.detailed:
        return 'Detalhado';
    }
  }

  String get fileSuffix {
    switch (this) {
      case ReportExportMode.summary:
        return 'resumo';
      case ReportExportMode.detailed:
        return 'detalhado';
    }
  }
}

class ReportExportMetric {
  const ReportExportMetric({
    required this.label,
    required this.value,
    this.caption,
  });

  final String label;
  final String value;
  final String? caption;
}

class ReportExportTable {
  const ReportExportTable({
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.emptyMessage = 'Sem dados no periodo.',
  });

  final String title;
  final String? subtitle;
  final List<String> columns;
  final List<List<String>> rows;
  final String emptyMessage;
}

class ReportExportDocument {
  const ReportExportDocument({
    required this.page,
    required this.mode,
    required this.title,
    required this.fileStem,
    required this.businessName,
    required this.generatedAt,
    required this.periodLabel,
    required this.filterSummary,
    this.navigationSummary,
    required this.metrics,
    required this.tables,
    required this.csvHeaders,
    required this.csvRows,
  });

  final ReportPageKey page;
  final ReportExportMode mode;
  final String title;
  final String fileStem;
  final String businessName;
  final DateTime generatedAt;
  final String periodLabel;
  final List<String> filterSummary;
  final String? navigationSummary;
  final List<ReportExportMetric> metrics;
  final List<ReportExportTable> tables;
  final List<String> csvHeaders;
  final List<List<String>> csvRows;
}

abstract final class ReportExportMapper {
  static ReportExportDocument sales({
    required String businessName,
    required DateTime generatedAt,
    required ReportExportMode mode,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
    required ReportOverviewSummary overview,
    required List<ReportSalesTrendPoint> trend,
    required List<ReportSoldProductSummary> topProducts,
    required List<ReportVariantSummary> topVariants,
    String? navigationSummary,
  }) {
    final paymentRows = overview.paymentSummaries
        .map(
          (row) => [
            row.paymentMethod.label,
            '${row.operationsCount}',
            AppFormatters.currencyFromCents(row.receivedCents),
          ],
        )
        .toList(growable: false);

    final trendTable = ReportExportTable(
      title: 'Tendencia resumida',
      subtitle: 'Faixas agrupadas conforme o filtro atual.',
      columns: const ['Faixa', 'Vendas', 'Bruto', 'Liquido'],
      rows: trend
          .map(
            (row) => [
              row.label,
              '${row.salesCount}',
              AppFormatters.currencyFromCents(row.grossSalesCents),
              AppFormatters.currencyFromCents(row.netSalesCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem tendencia para exportar neste periodo.',
    );
    final paymentTable = ReportExportTable(
      title: 'Recebimentos por forma',
      columns: const ['Forma', 'Operacoes', 'Recebido'],
      rows: paymentRows,
      emptyMessage: 'Sem recebimentos por forma no periodo.',
    );
    final topProductsTable = ReportExportTable(
      title: 'Top produtos',
      columns: const ['Produto', 'Quantidade', 'Receita', 'Custo'],
      rows: topProducts
          .map(
            (row) => [
              row.productName,
              '${AppFormatters.quantityFromMil(row.quantityMil)} ${row.unitMeasure}',
              AppFormatters.currencyFromCents(row.soldAmountCents),
              AppFormatters.currencyFromCents(row.totalCostCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem produtos vendidos no periodo.',
    );
    final topVariantsTable = ReportExportTable(
      title: 'Top variantes',
      columns: const ['Modelo', 'Variante', 'Vendida', 'Receita', 'Estoque'],
      rows: topVariants
          .map(
            (row) => [
              row.modelName,
              row.variantSummary,
              AppFormatters.quantityFromMil(row.soldQuantityMil),
              AppFormatters.currencyFromCents(row.grossRevenueCents),
              AppFormatters.quantityFromMil(row.currentStockMil),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem variantes vendidas no periodo.',
    );
    final tables = <ReportExportTable>[
      if (!filter.onlyCanceled) ...[
        if (filter.focus == ReportFocus.salesPaymentMethods) paymentTable,
        trendTable,
        if (filter.focus == ReportFocus.salesProducts) topProductsTable,
        if (filter.focus == ReportFocus.salesProducts) topVariantsTable,
        if (mode == ReportExportMode.detailed &&
            filter.focus != ReportFocus.salesPaymentMethods)
          paymentTable,
        if (filter.focus != ReportFocus.salesProducts) ...[
          topProductsTable,
          topVariantsTable,
        ],
      ],
    ];
    final csvRows = <List<String>>[
      if (!filter.onlyCanceled)
        for (final row in trend)
          [
            'Tendencia',
            row.label,
            'Faixa do periodo',
            '',
            '${row.salesCount}',
            AppFormatters.currencyFromCents(row.grossSalesCents),
            AppFormatters.currencyFromCents(row.netSalesCents),
            '',
            '',
            '',
          ],
      if (!filter.onlyCanceled &&
          (mode == ReportExportMode.detailed ||
              filter.focus == ReportFocus.salesPaymentMethods))
        for (final row in overview.paymentSummaries)
          [
            'Forma de pagamento',
            row.paymentMethod.label,
            'Recebimentos ligados as vendas',
            '',
            '${row.operationsCount}',
            '',
            '',
            AppFormatters.currencyFromCents(row.receivedCents),
            '',
            '',
          ],
      if (!filter.onlyCanceled)
        for (final row in topProducts)
          [
            'Top produto',
            row.productName,
            row.unitMeasure,
            AppFormatters.quantityFromMil(row.quantityMil),
            '',
            '',
            '',
            AppFormatters.currencyFromCents(row.soldAmountCents),
            AppFormatters.currencyFromCents(row.totalCostCents),
            '',
          ],
      if (!filter.onlyCanceled)
        for (final row in topVariants)
          [
            'Top variante',
            row.modelName,
            row.variantSummary,
            AppFormatters.quantityFromMil(row.soldQuantityMil),
            '',
            '',
            '',
            AppFormatters.currencyFromCents(row.grossRevenueCents),
            '',
            AppFormatters.quantityFromMil(row.currentStockMil),
          ],
    ];

    return ReportExportDocument(
      page: ReportPageKey.sales,
      mode: mode,
      title: 'Relatorio de vendas',
      fileStem: 'relatorio_vendas',
      businessName: businessName,
      generatedAt: generatedAt,
      periodLabel: _periodLabel(filter),
      filterSummary: _filterSummary(
        page: ReportPageKey.sales,
        filter: filter,
        labels: labels,
      ),
      navigationSummary: navigationSummary,
      metrics: [
        ReportExportMetric(
          label: 'Vendas brutas',
          value: AppFormatters.currencyFromCents(overview.grossSalesCents),
        ),
        ReportExportMetric(
          label: 'Vendas liquidas',
          value: AppFormatters.currencyFromCents(overview.netSalesCents),
          caption: '${overview.salesCount} venda(s) ativas',
        ),
        ReportExportMetric(
          label: 'Ticket medio',
          value: AppFormatters.currencyFromCents(overview.averageTicketCents),
        ),
        ReportExportMetric(
          label: 'Cancelamentos',
          value: '${overview.cancelledSalesCount}',
          caption: AppFormatters.currencyFromCents(
            overview.cancelledSalesCents,
          ),
        ),
        ReportExportMetric(
          label: 'Descontos',
          value: AppFormatters.currencyFromCents(overview.totalDiscountCents),
        ),
      ],
      tables: tables,
      csvHeaders: const [
        'Secao',
        'Item',
        'Descricao',
        'Quantidade',
        'Operacoes',
        'Bruto',
        'Liquido',
        'Receita',
        'Custo',
        'Estoque',
      ],
      csvRows: csvRows,
    );
  }

  static ReportExportDocument cash({
    required String businessName,
    required DateTime generatedAt,
    required ReportExportMode mode,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
    required ReportCashflowSummary cashflow,
    String? navigationSummary,
  }) {
    final entryOriginRows = _cashEntryOriginRows(cashflow);
    final entryOriginsTable = ReportExportTable(
      title: 'Entradas por origem',
      columns: const ['Origem', 'Valor'],
      rows: entryOriginRows,
      emptyMessage: 'Sem entradas no periodo.',
    );
    final movementTable = ReportExportTable(
      title: 'Resumo por tipo',
      columns: const ['Tipo', 'Movimentos', 'Valor'],
      rows: cashflow.movementRows
          .map(
            (row) => [
              row.label,
              '${row.count}',
              AppFormatters.currencyFromCents(row.amountCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem movimentos no periodo.',
    );
    final timelineTable = ReportExportTable(
      title: 'Linha do tempo',
      columns: const ['Faixa', 'Entradas', 'Saidas', 'Saldo'],
      rows: cashflow.timeline
          .map(
            (row) => [
              row.label,
              AppFormatters.currencyFromCents(row.inflowCents),
              AppFormatters.currencyFromCents(row.outflowCents),
              AppFormatters.currencyFromCents(row.netCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem linha do tempo no periodo.',
    );
    final tables = <ReportExportTable>[
      if (filter.focus == ReportFocus.cashNetFlow) timelineTable,
      entryOriginsTable,
      movementTable,
      if (mode == ReportExportMode.detailed &&
          filter.focus != ReportFocus.cashNetFlow)
        timelineTable,
    ];
    final csvRows = <List<String>>[
      for (final row in entryOriginRows)
        ['Entradas por origem', row[0], '', '', '', '', '', row[1]],
      for (final row in cashflow.movementRows)
        [
          'Resumo por tipo',
          row.label,
          row.description ?? '',
          '${row.count}',
          '',
          '',
          '',
          AppFormatters.currencyFromCents(row.amountCents),
        ],
      if (mode == ReportExportMode.detailed ||
          filter.focus == ReportFocus.cashNetFlow)
        for (final row in cashflow.timeline)
          [
            'Linha do tempo',
            row.label,
            'Faixa do periodo',
            '',
            AppFormatters.currencyFromCents(row.inflowCents),
            AppFormatters.currencyFromCents(row.outflowCents),
            AppFormatters.currencyFromCents(row.netCents),
            '',
          ],
    ];

    return ReportExportDocument(
      page: ReportPageKey.cash,
      mode: mode,
      title: 'Relatorio de caixa',
      fileStem: 'relatorio_caixa',
      businessName: businessName,
      generatedAt: generatedAt,
      periodLabel: _periodLabel(filter),
      filterSummary: _filterSummary(
        page: ReportPageKey.cash,
        filter: filter,
        labels: labels,
      ),
      navigationSummary: navigationSummary,
      metrics: [
        ReportExportMetric(
          label: 'Total recebido',
          value: AppFormatters.currencyFromCents(cashflow.totalReceivedCents),
        ),
        ReportExportMetric(
          label: 'Fiado recebido',
          value: AppFormatters.currencyFromCents(cashflow.fiadoReceiptsCents),
        ),
        ReportExportMetric(
          label: 'Entradas manuais',
          value: AppFormatters.currencyFromCents(cashflow.manualEntriesCents),
        ),
        ReportExportMetric(
          label: 'Saidas',
          value: AppFormatters.currencyFromCents(cashflow.outflowsCents),
        ),
        ReportExportMetric(
          label: 'Retiradas',
          value: AppFormatters.currencyFromCents(cashflow.withdrawalsCents),
        ),
        ReportExportMetric(
          label: 'Fluxo liquido',
          value: AppFormatters.currencyFromCents(cashflow.netFlowCents),
        ),
      ],
      tables: tables,
      csvHeaders: const [
        'Secao',
        'Item',
        'Descricao',
        'Movimentos',
        'Entradas',
        'Saidas',
        'Saldo',
        'Valor',
      ],
      csvRows: csvRows,
    );
  }

  static ReportExportDocument inventory({
    required String businessName,
    required DateTime generatedAt,
    required ReportExportMode mode,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
    required ReportInventoryHealthSummary summary,
    String? navigationSummary,
  }) {
    final healthRows = [
      ['Saudavel', '${summary.healthyItemsCount}'],
      ['Abaixo do minimo', '${summary.belowMinimumOnlyItemsCount}'],
      ['Zerado', '${summary.zeroedItemsCount}'],
      ['Com divergencia', '${summary.divergenceItemsCount}'],
    ];
    final healthTable = ReportExportTable(
      title: 'Saude do estoque',
      columns: const ['Indicador', 'Valor'],
      rows: healthRows,
      emptyMessage: 'Sem saude do estoque para exportar.',
    );
    final criticalItemsTable = ReportExportTable(
      title: 'Itens criticos',
      columns: const ['Item', 'Status', 'Estoque', 'Minimo', 'Atualizado'],
      rows: summary.criticalItems
          .map(_inventoryItemRow)
          .toList(growable: false),
      emptyMessage: 'Sem itens criticos no periodo.',
    );
    final mostMovedTable = ReportExportTable(
      title: 'Itens mais movimentados',
      columns: const ['Item', 'Quantidade'],
      rows: summary.mostMovedItems
          .map(
            (row) => [
              row.label,
              AppFormatters.quantityFromMil(row.quantityMil),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem movimentacao relevante no periodo.',
    );
    final recentMovementsTable = ReportExportTable(
      title: 'Ultimas movimentacoes',
      columns: const ['Item', 'Tipo', 'Quantidade', 'Quando'],
      rows: summary.recentMovements
          .map(_inventoryMovementRow)
          .toList(growable: false),
      emptyMessage: 'Sem movimentacoes recentes no periodo.',
    );
    final tables = <ReportExportTable>[
      healthTable,
      criticalItemsTable,
      if (mode == ReportExportMode.detailed) ...[
        mostMovedTable,
        recentMovementsTable,
      ],
    ];
    final csvRows = <List<String>>[
      for (final row in healthRows)
        ['Saude', row[0], '', row[0], row[1], '', '', ''],
      for (final item in summary.criticalItems)
        [
          'Item critico',
          item.displayName,
          item.variantSummary ?? item.unitMeasure,
          item.status.label,
          AppFormatters.quantityFromMil(item.currentStockMil),
          AppFormatters.quantityFromMil(item.minimumStockMil),
          AppFormatters.currencyFromCents(item.salePriceCents),
          AppFormatters.shortDate(item.updatedAt),
        ],
      if (mode == ReportExportMode.detailed)
        for (final row in summary.mostMovedItems)
          [
            'Mais movimentado',
            row.label,
            '',
            '',
            AppFormatters.quantityFromMil(row.quantityMil),
            '',
            '',
            '',
          ],
      if (mode == ReportExportMode.detailed)
        for (final row in summary.recentMovements)
          [
            'Movimentacao',
            row.displayName,
            row.movementType.label,
            row.referenceLabel,
            AppFormatters.quantityFromMil(row.quantityDeltaMil.abs()),
            '',
            '',
            AppFormatters.shortDateTime(row.createdAt),
          ],
    ];

    return ReportExportDocument(
      page: ReportPageKey.inventory,
      mode: mode,
      title: 'Relatorio de estoque',
      fileStem: 'relatorio_estoque',
      businessName: businessName,
      generatedAt: generatedAt,
      periodLabel: _periodLabel(filter),
      filterSummary: _filterSummary(
        page: ReportPageKey.inventory,
        filter: filter,
        labels: labels,
      ),
      navigationSummary: navigationSummary,
      metrics: [
        ReportExportMetric(
          label: 'Itens zerados',
          value: '${summary.zeroedItemsCount}',
        ),
        ReportExportMetric(
          label: 'Abaixo do minimo',
          value: '${summary.belowMinimumItemsCount}',
        ),
        ReportExportMetric(
          label: 'Valor a custo',
          value: AppFormatters.currencyFromCents(
            summary.inventoryCostValueCents,
          ),
        ),
        ReportExportMetric(
          label: 'Valor a venda',
          value: AppFormatters.currencyFromCents(
            summary.inventorySaleValueCents,
          ),
        ),
        ReportExportMetric(
          label: 'Divergencias',
          value: '${summary.divergenceItemsCount}',
        ),
      ],
      tables: tables,
      csvHeaders: const [
        'Secao',
        'Item',
        'Descricao',
        'Status',
        'Quantidade',
        'Minimo',
        'Valor',
        'Data',
      ],
      csvRows: csvRows,
    );
  }

  static ReportExportDocument customers({
    required String businessName,
    required DateTime generatedAt,
    required ReportExportMode mode,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
    required List<ReportCustomerRankingRow> rows,
    String? navigationSummary,
  }) {
    final topCustomers = [...rows]
      ..sort((a, b) => b.totalPurchasedCents.compareTo(a.totalPurchasedCents));
    final openFiado =
        rows.where((row) => row.hasPendingFiado).toList(growable: false)
          ..sort(
            (a, b) => b.pendingFiadoCents.compareTo(a.pendingFiadoCents),
          );
    final withCredit =
        rows.where((row) => row.hasCredit).toList(growable: false)
          ..sort(
            (a, b) => b.creditBalanceCents.compareTo(a.creditBalanceCents),
          );
    final inactive =
        rows
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
    final topCustomersTable = ReportExportTable(
      title: 'Top clientes por compra',
      columns: const ['Cliente', 'Compras', 'Valor', 'Ultima compra'],
      rows: topCustomers
          .take(mode == ReportExportMode.summary ? 10 : topCustomers.length)
          .map(
            (row) => [
              row.customerName,
              '${row.salesCount}',
              AppFormatters.currencyFromCents(row.totalPurchasedCents),
              row.lastPurchaseAt == null
                  ? 'Sem compra recente'
                  : AppFormatters.shortDate(row.lastPurchaseAt!),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem compras no periodo.',
    );
    final openFiadoTable = ReportExportTable(
      title: 'Clientes com fiado aberto',
      columns: const ['Cliente', 'Saldo pendente', 'Ultima compra'],
      rows: openFiado
          .take(mode == ReportExportMode.summary ? 10 : openFiado.length)
          .map(
            (row) => [
              row.customerName,
              AppFormatters.currencyFromCents(row.pendingFiadoCents),
              row.lastPurchaseAt == null
                  ? 'Sem compra recente'
                  : AppFormatters.shortDate(row.lastPurchaseAt!),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Nenhum fiado aberto no periodo.',
    );
    final withCreditTable = ReportExportTable(
      title: 'Clientes com haver',
      columns: const ['Cliente', 'Haver', 'Ultima compra'],
      rows: withCredit
          .take(mode == ReportExportMode.summary ? 10 : withCredit.length)
          .map(
            (row) => [
              row.customerName,
              AppFormatters.currencyFromCents(row.creditBalanceCents),
              row.lastPurchaseAt == null
                  ? 'Sem compra recente'
                  : AppFormatters.shortDate(row.lastPurchaseAt!),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem haver em aberto no periodo.',
    );
    final inactiveTable = ReportExportTable(
      title: 'Clientes inativos',
      columns: const ['Cliente', 'Ultima compra', 'Compras no periodo'],
      rows: inactive
          .map(
            (row) => [
              row.customerName,
              row.lastPurchaseAt == null
                  ? 'Sem compra recente'
                  : AppFormatters.shortDate(row.lastPurchaseAt!),
              '${row.salesCount}',
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem clientes inativos no periodo.',
    );
    final tables = <ReportExportTable>[
      if (filter.focus == ReportFocus.customersWithFiado ||
          filter.focus == ReportFocus.customersPending)
        openFiadoTable,
      if (filter.focus == ReportFocus.customersWithCredit) withCreditTable,
      if (filter.focus == ReportFocus.customersTopPurchases) topCustomersTable,
      if (filter.focus == null) ...[
        topCustomersTable,
        openFiadoTable,
        withCreditTable,
      ] else ...[
        if (filter.focus != ReportFocus.customersTopPurchases) topCustomersTable,
        if (filter.focus != ReportFocus.customersWithFiado &&
            filter.focus != ReportFocus.customersPending)
          openFiadoTable,
        if (filter.focus != ReportFocus.customersWithCredit) withCreditTable,
      ],
      if (mode == ReportExportMode.detailed) inactiveTable,
    ];
    final csvRows = <List<String>>[
      for (final row in (mode == ReportExportMode.summary
          ? topCustomers.take(10)
          : rows))
        [
          row.customerName,
          row.isActive ? 'Sim' : 'Nao',
          '${row.salesCount}',
          AppFormatters.currencyFromCents(row.totalPurchasedCents),
          AppFormatters.currencyFromCents(row.pendingFiadoCents),
          AppFormatters.currencyFromCents(row.creditBalanceCents),
          row.lastPurchaseAt == null
              ? ''
              : AppFormatters.shortDate(row.lastPurchaseAt!),
        ],
    ];

    return ReportExportDocument(
      page: ReportPageKey.customers,
      mode: mode,
      title: 'Relatorio de clientes',
      fileStem: 'relatorio_clientes',
      businessName: businessName,
      generatedAt: generatedAt,
      periodLabel: _periodLabel(filter),
      filterSummary: _filterSummary(
        page: ReportPageKey.customers,
        filter: filter,
        labels: labels,
      ),
      navigationSummary: navigationSummary,
      metrics: [
        ReportExportMetric(
          label: 'Top clientes ativos',
          value: '${topCustomers.where((row) => row.hasPurchases).length}',
        ),
        ReportExportMetric(
          label: 'Com fiado aberto',
          value: '${openFiado.length}',
        ),
        ReportExportMetric(
          label: 'Com haver',
          value: '${withCredit.length}',
        ),
        ReportExportMetric(
          label: 'Maior saldo pendente',
          value: openFiado.isEmpty
              ? 'R\$ 0,00'
              : AppFormatters.currencyFromCents(
                  openFiado.first.pendingFiadoCents,
                ),
          caption: openFiado.isEmpty ? null : openFiado.first.customerName,
        ),
      ],
      tables: tables,
      csvHeaders: const [
        'Cliente',
        'Ativo',
        'Compras',
        'Valor comprado',
        'Fiado aberto',
        'Haver',
        'Ultima compra',
      ],
      csvRows: csvRows,
    );
  }

  static ReportExportDocument purchases({
    required String businessName,
    required DateTime generatedAt,
    required ReportExportMode mode,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
    required ReportPurchaseSummary summary,
    String? navigationSummary,
  }) {
    final supplierTable = ReportExportTable(
      title: 'Compras por fornecedor',
      columns: const ['Fornecedor', 'Compras', 'Valor'],
      rows: summary.supplierRows
          .map(
            (row) => [
              row.label,
              '${row.count}',
              AppFormatters.currencyFromCents(row.amountCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem fornecedores no periodo.',
    );
    final topItemsTable = ReportExportTable(
      title: 'Itens mais comprados',
      columns: const ['Item', 'Quantidade', 'Valor'],
      rows: summary.topItems
          .map(
            (row) => [
              row.label,
              AppFormatters.quantityFromMil(row.quantityMil),
              AppFormatters.currencyFromCents(row.amountCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem itens comprados no periodo.',
    );
    final replenishmentTable = ReportExportTable(
      title: 'Reposicao por variante',
      columns: const ['Variante', 'Quantidade', 'Valor'],
      rows: summary.replenishmentRows
          .map(
            (row) => [
              row.label,
              AppFormatters.quantityFromMil(row.quantityMil),
              AppFormatters.currencyFromCents(row.amountCents),
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem reposicao por variante no periodo.',
    );
    final tables = <ReportExportTable>[
      if (filter.focus == ReportFocus.purchasesSuppliers) supplierTable,
      if (filter.focus == ReportFocus.purchasesItems) topItemsTable,
      if (filter.focus == ReportFocus.purchasesReplenishment) replenishmentTable,
      if (filter.focus == null || filter.focus == ReportFocus.purchasesSuppliers)
        if (filter.focus == null) supplierTable,
      if (mode == ReportExportMode.detailed ||
          filter.focus == ReportFocus.purchasesItems)
        if (filter.focus != ReportFocus.purchasesItems) topItemsTable,
      if (mode == ReportExportMode.detailed ||
          filter.focus == ReportFocus.purchasesReplenishment)
        if (filter.focus != ReportFocus.purchasesReplenishment)
          replenishmentTable,
    ];
    final csvRows = <List<String>>[
      for (final row in summary.supplierRows)
        [
          'Fornecedor',
          row.label,
          '',
          '',
          '${row.count}',
          AppFormatters.currencyFromCents(row.amountCents),
        ],
      if (mode == ReportExportMode.detailed ||
          filter.focus == ReportFocus.purchasesItems)
        for (final row in summary.topItems)
          [
            'Item comprado',
            row.label,
            '',
            AppFormatters.quantityFromMil(row.quantityMil),
            '',
            AppFormatters.currencyFromCents(row.amountCents),
          ],
      if (mode == ReportExportMode.detailed ||
          filter.focus == ReportFocus.purchasesReplenishment)
        for (final row in summary.replenishmentRows)
          [
            'Reposicao',
            row.label,
            '',
            AppFormatters.quantityFromMil(row.quantityMil),
            '',
            AppFormatters.currencyFromCents(row.amountCents),
          ],
    ];

    return ReportExportDocument(
      page: ReportPageKey.purchases,
      mode: mode,
      title: 'Relatorio de compras',
      fileStem: 'relatorio_compras',
      businessName: businessName,
      generatedAt: generatedAt,
      periodLabel: _periodLabel(filter),
      filterSummary: _filterSummary(
        page: ReportPageKey.purchases,
        filter: filter,
        labels: labels,
      ),
      navigationSummary: navigationSummary,
      metrics: [
        ReportExportMetric(
          label: 'Total comprado',
          value: AppFormatters.currencyFromCents(summary.totalPurchasedCents),
          caption: '${summary.purchasesCount} compra(s)',
        ),
        ReportExportMetric(
          label: 'Total pendente',
          value: AppFormatters.currencyFromCents(summary.totalPendingCents),
        ),
        ReportExportMetric(
          label: 'Total pago',
          value: AppFormatters.currencyFromCents(summary.totalPaidCents),
        ),
      ],
      tables: tables,
      csvHeaders: const [
        'Secao',
        'Item',
        'Descricao',
        'Quantidade',
        'Compras',
        'Valor',
      ],
      csvRows: csvRows,
    );
  }

  static ReportExportDocument profitability({
    required String businessName,
    required DateTime generatedAt,
    required ReportExportMode mode,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
    required List<ReportProfitabilityRow> rows,
    String? navigationSummary,
  }) {
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
    final exportedRows = mode == ReportExportMode.summary
        ? rows.take(10).toList(growable: false)
        : rows;
    final resultTable = ReportExportTable(
      title: 'Resultado por agrupamento',
      columns: const [
        'Item',
        'Descricao',
        'Quantidade',
        'Receita',
        'Custo',
        'Lucro',
        'Margem',
      ],
      rows: exportedRows
          .map(
            (row) => [
              row.label,
              row.description ?? row.grouping.label,
              AppFormatters.quantityFromMil(row.quantityMil),
              AppFormatters.currencyFromCents(row.revenueCents),
              AppFormatters.currencyFromCents(row.costCents),
              AppFormatters.currencyFromCents(row.profitCents),
              '${row.marginPercent.toStringAsFixed(1)}%',
            ],
          )
          .toList(growable: false),
      emptyMessage: 'Sem lucratividade no periodo.',
    );

    return ReportExportDocument(
      page: ReportPageKey.profitability,
      mode: mode,
      title: 'Relatorio de lucratividade',
      fileStem: 'relatorio_lucratividade',
      businessName: businessName,
      generatedAt: generatedAt,
      periodLabel: _periodLabel(filter),
      filterSummary: _filterSummary(
        page: ReportPageKey.profitability,
        filter: filter,
        labels: labels,
      ),
      navigationSummary: navigationSummary,
      metrics: [
        ReportExportMetric(
          label: 'Receita',
          value: AppFormatters.currencyFromCents(revenueCents),
        ),
        ReportExportMetric(
          label: 'Custo',
          value: AppFormatters.currencyFromCents(costCents),
        ),
        ReportExportMetric(
          label: 'Lucro',
          value: AppFormatters.currencyFromCents(profitCents),
        ),
        ReportExportMetric(
          label: 'Margem media',
          value: '${marginPercent.toStringAsFixed(1)}%',
        ),
        ReportExportMetric(
          label: 'Quantidade vendida',
          value: AppFormatters.quantityFromMil(quantityMil),
        ),
      ],
      tables: [resultTable],
      csvHeaders: const [
        'Item',
        'Descricao',
        'Quantidade',
        'Receita',
        'Custo',
        'Lucro',
        'Margem',
      ],
      csvRows: [
        for (final row in exportedRows)
          [
            row.label,
            row.description ?? row.grouping.label,
            AppFormatters.quantityFromMil(row.quantityMil),
            AppFormatters.currencyFromCents(row.revenueCents),
            AppFormatters.currencyFromCents(row.costCents),
            AppFormatters.currencyFromCents(row.profitCents),
            '${row.marginPercent.toStringAsFixed(1)}%',
          ],
      ],
    );
  }

  static String _periodLabel(ReportFilter filter) {
    return '${AppFormatters.shortDate(filter.start)} ate ${AppFormatters.shortDate(filter.endExclusive.subtract(const Duration(days: 1)))}';
  }

  static List<String> _filterSummary({
    required ReportPageKey page,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
  }) {
    final active = ReportFilterPresetSupport.activeFiltersForPage(
      page: page,
      filter: filter,
      labels: labels,
    );
    if (active.isEmpty) {
      return const ['Sem filtros adicionais.'];
    }
    return active.map((item) => item.displayLabel).toList(growable: false);
  }

  static List<List<String>> _cashEntryOriginRows(ReportCashflowSummary cashflow) {
    final salesEntries =
        (cashflow.totalReceivedCents - cashflow.fiadoReceiptsCents).clamp(
          0,
          cashflow.totalReceivedCents,
        );
    return [
      ['Vendas', AppFormatters.currencyFromCents(salesEntries)],
      [
        'Recebimento de fiado',
        AppFormatters.currencyFromCents(cashflow.fiadoReceiptsCents),
      ],
      [
        'Entradas manuais',
        AppFormatters.currencyFromCents(cashflow.manualEntriesCents),
      ],
    ];
  }

  static List<String> _inventoryItemRow(InventoryItem item) {
    return [
      item.displayName,
      item.status.label,
      AppFormatters.quantityFromMil(item.currentStockMil),
      AppFormatters.quantityFromMil(item.minimumStockMil),
      AppFormatters.shortDate(item.updatedAt),
    ];
  }

  static List<String> _inventoryMovementRow(InventoryMovement movement) {
    return [
      movement.displayName,
      movement.movementType.label,
      AppFormatters.quantityFromMil(movement.quantityDeltaMil.abs()),
      AppFormatters.shortDateTime(movement.createdAt),
    ];
  }
}
