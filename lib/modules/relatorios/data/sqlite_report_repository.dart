import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/utils/payment_method_note_codec.dart';
import '../../clientes/domain/entities/customer_credit_transaction.dart';
import '../../estoque/domain/entities/inventory_item.dart';
import '../../estoque/domain/entities/inventory_movement.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/report_breakdown_row.dart';
import '../domain/entities/report_cashflow_point.dart';
import '../domain/entities/report_cashflow_summary.dart';
import '../domain/entities/report_customer_credit_summary.dart';
import '../domain/entities/report_customer_ranking_row.dart';
import '../domain/entities/report_filter.dart';
import '../domain/entities/report_inventory_health_summary.dart';
import '../domain/entities/report_overview_summary.dart';
import '../domain/entities/report_payment_summary.dart';
import '../domain/entities/report_period.dart';
import '../domain/entities/report_profitability_row.dart';
import '../domain/entities/report_purchase_summary.dart';
import '../domain/entities/report_sales_trend_point.dart';
import '../domain/entities/report_sold_product_summary.dart';
import '../domain/entities/report_summary.dart';
import '../domain/entities/report_variant_summary.dart';
import '../domain/repositories/report_repository.dart';
import 'support/report_grouping_support.dart';
import 'support/report_sql_filters_support.dart';

class SqliteReportRepository implements ReportRepository {
  SqliteReportRepository(AppDatabase appDatabase)
    : _databaseLoader = (() => appDatabase.database);

  SqliteReportRepository.forDatabase(Future<Database> Function() databaseLoader)
    : _databaseLoader = databaseLoader;

  final Future<Database> Function() _databaseLoader;

  static const String _soldAmountExpression = '''
    COALESCE(
      iv.subtotal_centavos,
      CAST(ROUND((iv.quantidade_mil * iv.valor_unitario_centavos) / 1000.0, 0) AS INTEGER)
    )
  ''';

  static const String _costAmountExpression = '''
    COALESCE(
      iv.custo_total_centavos,
      CAST(ROUND((iv.quantidade_mil * iv.custo_unitario_centavos) / 1000.0, 0) AS INTEGER)
    )
  ''';

  @override
  Future<ReportSummary> fetchSummary({
    required ReportPeriod period,
    ReportFilter? filter,
  }) async {
    final effectiveFilter = filter ?? ReportFilter.fromPeriod(period);
    final overview = await fetchOverview(filter: effectiveFilter);
    final soldProducts = await fetchTopProducts(
      filter: effectiveFilter,
      limit: 200,
    );
    final variants = await fetchTopVariants(
      filter: effectiveFilter,
      limit: 300,
    );

    return ReportSummary(
      period: period,
      range: effectiveFilter.range,
      totalSalesCents: overview.netSalesCents,
      totalReceivedCents: overview.totalReceivedCents,
      costOfGoodsSoldCents: overview.costOfGoodsSoldCents,
      realizedProfitCents: overview.realizedProfitCents,
      salesCount: overview.salesCount,
      pendingFiadoCents: overview.pendingFiadoCents,
      pendingFiadoCount: overview.pendingFiadoCount,
      cancelledSalesCount: overview.cancelledSalesCount,
      cancelledSalesCents: overview.cancelledSalesCents,
      totalPurchasedCents: overview.totalPurchasedCents,
      totalPurchasePaymentsCents: overview.totalPurchasePaymentsCents,
      totalPurchasePendingCents: overview.totalPurchasePendingCents,
      cashSalesReceivedCents: overview.cashSalesReceivedCents,
      fiadoReceiptsCents: overview.fiadoReceiptsCents,
      totalCreditGeneratedCents: overview.totalCreditGeneratedCents,
      totalCreditUsedCents: overview.totalCreditUsedCents,
      totalOutstandingCreditCents: overview.totalOutstandingCreditCents,
      topCreditCustomers: overview.topCreditCustomers,
      paymentSummaries: overview.paymentSummaries,
      soldProducts: soldProducts,
      variantSummaries: variants,
    );
  }

  @override
  Future<ReportOverviewSummary> fetchOverview({
    required ReportFilter filter,
  }) async {
    final database = await _databaseLoader();
    final salesAggregate = await _fetchSalesAggregate(database, filter: filter);
    final costOfGoodsSoldCents = await _fetchCostOfGoodsSold(
      database,
      filter: filter,
    );
    final realizedProfitCents = await _fetchRealizedProfit(
      database,
      filter: filter,
    );
    final pendingFiado = await _fetchPendingFiado(database);
    final cancelledSales = await _fetchCancelledSales(database, filter: filter);
    final purchaseTotals = await _fetchPurchaseTotals(database, filter: filter);
    final purchasePaymentsCents = await _fetchPurchasePaymentsTotal(
      database,
      filter: filter,
    );
    final receivedTotals = await _fetchReceivedTotals(database, filter: filter);
    final creditTotals = await _fetchCreditTotals(database, filter: filter);
    final totalOutstandingCreditCents = await _fetchOutstandingCredit(database);
    final topCreditCustomers = await _fetchTopCreditCustomers(database);
    final paymentSummaries = await _fetchPaymentSummaries(
      database,
      filter: filter,
    );

    return ReportOverviewSummary(
      filter: filter,
      grossSalesCents: salesAggregate.grossSalesCents,
      netSalesCents: salesAggregate.netSalesCents,
      totalReceivedCents: receivedTotals.totalReceivedCents,
      costOfGoodsSoldCents: costOfGoodsSoldCents,
      realizedProfitCents: realizedProfitCents,
      salesCount: salesAggregate.salesCount,
      totalDiscountCents: salesAggregate.totalDiscountCents,
      totalSurchargeCents: salesAggregate.totalSurchargeCents,
      pendingFiadoCents: pendingFiado.totalOpenCents,
      pendingFiadoCount: pendingFiado.count,
      cancelledSalesCount: cancelledSales.count,
      cancelledSalesCents: cancelledSales.totalCents,
      totalPurchasedCents: purchaseTotals.totalPurchasedCents,
      totalPurchasePaymentsCents: purchasePaymentsCents,
      totalPurchasePendingCents: purchaseTotals.totalPendingCents,
      cashSalesReceivedCents: receivedTotals.cashSalesReceivedCents,
      fiadoReceiptsCents: receivedTotals.fiadoReceiptsCents,
      totalCreditGeneratedCents: creditTotals.totalGeneratedCents,
      totalCreditUsedCents: creditTotals.totalUsedCents,
      totalOutstandingCreditCents: totalOutstandingCreditCents,
      topCreditCustomers: topCreditCustomers,
      paymentSummaries: paymentSummaries,
    );
  }

  @override
  Future<List<ReportSalesTrendPoint>> fetchSalesTrend({
    required ReportFilter filter,
  }) async {
    final database = await _databaseLoader();
    final grouping = ReportGroupingSupport.normalizeTimeSeries(filter.grouping);
    final groupingSql = ReportGroupingSupport.timeBucketSql(
      grouping,
      column: 'v.data_venda',
    );
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        ${groupingSql.keyExpression} AS bucket_key,
        COUNT(*) AS sales_count,
        COALESCE(SUM(v.valor_total_centavos), 0) AS gross_sales_cents,
        COALESCE(SUM(v.valor_final_centavos), 0) AS net_sales_cents
      FROM ${TableNames.vendas} v
      WHERE 1 = 1
    ''');

    _appendSalesAggregateFilters(buffer, arguments, filter: filter);
    buffer.write('''
      GROUP BY ${groupingSql.keyExpression}
      ORDER BY ${groupingSql.orderExpression} ASC
    ''');

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map((row) {
          final bucketStart = DateTime.parse(row['bucket_key'] as String);
          return ReportSalesTrendPoint(
            bucketStart: bucketStart,
            bucketEndExclusive: _resolveBucketEndExclusive(
              grouping,
              bucketStart,
            ),
            label: _formatBucketLabel(grouping, bucketStart),
            salesCount: _toInt(row['sales_count']),
            grossSalesCents: _toInt(row['gross_sales_cents']),
            netSalesCents: _toInt(row['net_sales_cents']),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<ReportSoldProductSummary>> fetchTopProducts({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    final database = await _databaseLoader();
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        iv.produto_id AS product_id,
        COALESCE(iv.nome_produto_snapshot, p.nome, 'Produto') AS product_name,
        COALESCE(iv.unidade_medida_snapshot, p.unidade_medida, 'un') AS unit_measure,
        COALESCE(SUM(iv.quantidade_mil), 0) AS quantity_total_mil,
        COALESCE(SUM($_soldAmountExpression), 0) AS sold_amount_cents,
        COALESCE(SUM($_costAmountExpression), 0) AS total_cost_cents
      FROM ${TableNames.itensVenda} iv
      INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
      WHERE 1 = 1
    ''');

    _appendSalesItemFilters(buffer, arguments, filter: filter);
    buffer.write('''
      GROUP BY
        iv.produto_id,
        COALESCE(iv.nome_produto_snapshot, p.nome, 'Produto'),
        COALESCE(iv.unidade_medida_snapshot, p.unidade_medida, 'un')
      ORDER BY sold_amount_cents DESC, quantity_total_mil DESC, product_name COLLATE NOCASE ASC
      LIMIT ?
    ''');
    arguments.add(limit);

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportSoldProductSummary(
            productId: row['product_id'] as int?,
            productName: row['product_name'] as String? ?? 'Produto',
            quantityMil: _toInt(row['quantity_total_mil']),
            unitMeasure: row['unit_measure'] as String? ?? 'un',
            soldAmountCents: _toInt(row['sold_amount_cents']),
            totalCostCents: _toInt(row['total_cost_cents']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ReportVariantSummary>> fetchTopVariants({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    final database = await _databaseLoader();
    final salesArguments = <Object?>[];
    final soldWhere = StringBuffer('WHERE 1 = 1');
    _appendSalesItemFilters(
      soldWhere,
      salesArguments,
      filter: filter,
      saleAlias: 'v',
      itemAlias: 'iv',
      productAlias: 'p',
    );

    final purchaseArguments = <Object?>[];
    final purchasedWhere = StringBuffer('WHERE 1 = 1');
    _appendPurchaseItemFilters(
      purchasedWhere,
      purchaseArguments,
      filter: filter,
      purchaseAlias: 'c',
      itemAlias: 'ic',
      productAlias: 'p',
    );

    final queryArguments = <Object?>[
      ...salesArguments,
      ...purchaseArguments,
      limit,
    ];

    final rows = await database.rawQuery('''
      WITH sold AS (
        SELECT
          iv.produto_id AS product_id,
          iv.produto_variante_id AS variant_id,
          MAX(
            COALESCE(
              NULLIF(TRIM(p.model_name), ''),
              NULLIF(TRIM(iv.nome_produto_snapshot), ''),
              NULLIF(TRIM(p.nome), ''),
              'Produto'
            )
          ) AS model_name,
          MAX(
            COALESCE(
              NULLIF(TRIM(iv.sku_variante_snapshot), ''),
              NULLIF(TRIM(pv.sku), '')
            )
          ) AS variant_sku,
          MAX(
            COALESCE(
              NULLIF(TRIM(iv.cor_variante_snapshot), ''),
              NULLIF(TRIM(pv.cor), '')
            )
          ) AS color_label,
          MAX(
            COALESCE(
              NULLIF(TRIM(iv.tamanho_variante_snapshot), ''),
              NULLIF(TRIM(pv.tamanho), '')
            )
          ) AS size_label,
          COALESCE(SUM(iv.quantidade_mil), 0) AS sold_quantity_mil,
          COALESCE(SUM($_soldAmountExpression), 0) AS gross_revenue_cents
        FROM ${TableNames.itensVenda} iv
        INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
        LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
        LEFT JOIN ${TableNames.produtoVariantes} pv
          ON pv.id = iv.produto_variante_id
        $soldWhere
        GROUP BY iv.produto_id, iv.produto_variante_id
      ),
      purchased AS (
        SELECT
          ic.produto_id AS product_id,
          ic.produto_variante_id AS variant_id,
          MAX(
            COALESCE(
              NULLIF(TRIM(p.model_name), ''),
              NULLIF(TRIM(ic.nome_item_snapshot), ''),
              NULLIF(TRIM(p.nome), ''),
              'Produto'
            )
          ) AS model_name,
          MAX(
            COALESCE(
              NULLIF(TRIM(ic.sku_variante_snapshot), ''),
              NULLIF(TRIM(pv.sku), '')
            )
          ) AS variant_sku,
          MAX(
            COALESCE(
              NULLIF(TRIM(ic.cor_variante_snapshot), ''),
              NULLIF(TRIM(pv.cor), '')
            )
          ) AS color_label,
          MAX(
            COALESCE(
              NULLIF(TRIM(ic.tamanho_variante_snapshot), ''),
              NULLIF(TRIM(pv.tamanho), '')
            )
          ) AS size_label,
          COALESCE(SUM(ic.quantidade_mil), 0) AS purchased_quantity_mil
        FROM ${TableNames.itensCompra} ic
        INNER JOIN ${TableNames.compras} c ON c.id = ic.compra_id
        LEFT JOIN ${TableNames.produtos} p ON p.id = ic.produto_id
        LEFT JOIN ${TableNames.produtoVariantes} pv
          ON pv.id = ic.produto_variante_id
        $purchasedWhere
        GROUP BY ic.produto_id, ic.produto_variante_id
      ),
      variant_index AS (
        SELECT
          pv.produto_id AS product_id,
          pv.id AS variant_id,
          COALESCE(
            NULLIF(TRIM(p.model_name), ''),
            NULLIF(TRIM(p.nome), ''),
            'Produto'
          ) AS model_name,
          pv.sku AS variant_sku,
          pv.cor AS color_label,
          pv.tamanho AS size_label,
          pv.estoque_mil AS current_stock_mil,
          COALESCE(pv.ordem, 0) AS variant_order
        FROM ${TableNames.produtoVariantes} pv
        INNER JOIN ${TableNames.produtos} p ON p.id = pv.produto_id
        WHERE p.deletado_em IS NULL

        UNION

        SELECT
          sold.product_id,
          sold.variant_id,
          sold.model_name,
          sold.variant_sku,
          sold.color_label,
          sold.size_label,
          COALESCE(pv.estoque_mil, 0) AS current_stock_mil,
          COALESCE(pv.ordem, 9999) AS variant_order
        FROM sold
        LEFT JOIN ${TableNames.produtoVariantes} pv ON pv.id = sold.variant_id

        UNION

        SELECT
          purchased.product_id,
          purchased.variant_id,
          purchased.model_name,
          purchased.variant_sku,
          purchased.color_label,
          purchased.size_label,
          COALESCE(pv.estoque_mil, 0) AS current_stock_mil,
          COALESCE(pv.ordem, 9999) AS variant_order
        FROM purchased
        LEFT JOIN ${TableNames.produtoVariantes} pv
          ON pv.id = purchased.variant_id
      )
      SELECT
        idx.product_id,
        idx.variant_id,
        MAX(idx.model_name) AS model_name,
        MAX(idx.variant_sku) AS variant_sku,
        MAX(idx.color_label) AS color_label,
        MAX(idx.size_label) AS size_label,
        COALESCE(MAX(idx.current_stock_mil), 0) AS current_stock_mil,
        COALESCE(MAX(sold.sold_quantity_mil), 0) AS sold_quantity_mil,
        COALESCE(MAX(purchased.purchased_quantity_mil), 0) AS purchased_quantity_mil,
        COALESCE(MAX(sold.gross_revenue_cents), 0) AS gross_revenue_cents,
        MIN(idx.variant_order) AS variant_order
      FROM variant_index idx
      LEFT JOIN sold
        ON sold.product_id = idx.product_id
        AND (
          sold.variant_id = idx.variant_id
          OR (sold.variant_id IS NULL AND idx.variant_id IS NULL)
        )
      LEFT JOIN purchased
        ON purchased.product_id = idx.product_id
        AND (
          purchased.variant_id = idx.variant_id
          OR (purchased.variant_id IS NULL AND idx.variant_id IS NULL)
        )
      GROUP BY idx.product_id, idx.variant_id
      ORDER BY
        sold_quantity_mil DESC,
        gross_revenue_cents DESC,
        model_name COLLATE NOCASE ASC,
        variant_order ASC,
        color_label COLLATE NOCASE ASC,
        size_label COLLATE NOCASE ASC
      LIMIT ?
    ''', queryArguments);

    return rows
        .map(
          (row) => ReportVariantSummary(
            productId: row['product_id'] as int? ?? 0,
            variantId: row['variant_id'] as int? ?? 0,
            modelName: row['model_name'] as String? ?? 'Produto',
            variantSku: _cleanNullable(row['variant_sku'] as String?),
            colorLabel: _cleanNullable(row['color_label'] as String?),
            sizeLabel: _cleanNullable(row['size_label'] as String?),
            currentStockMil: _toInt(row['current_stock_mil']),
            soldQuantityMil: _toInt(row['sold_quantity_mil']),
            purchasedQuantityMil: _toInt(row['purchased_quantity_mil']),
            grossRevenueCents: _toInt(row['gross_revenue_cents']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ReportProfitabilityRow>> fetchProfitability({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final database = await _databaseLoader();
    final grouping = _resolveProfitabilityGrouping(filter.grouping);
    final arguments = <Object?>[];
    final buffer = StringBuffer(_buildProfitabilityBaseSql(grouping));
    _appendSalesItemFilters(buffer, arguments, filter: filter);
    buffer.write(_buildProfitabilityGroupingSql(grouping));
    buffer.write(' LIMIT ?');
    arguments.add(limit);

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportProfitabilityRow(
            grouping: grouping,
            label: row['label'] as String? ?? 'Sem nome',
            description: _cleanNullable(row['description'] as String?),
            productId: row['product_id'] as int?,
            variantId: row['variant_id'] as int?,
            categoryId: row['category_id'] as int?,
            quantityMil: _toInt(row['quantity_mil']),
            revenueCents: _toInt(row['revenue_cents']),
            costCents: _toInt(row['cost_cents']),
            profitCents: _toInt(row['profit_cents']),
            marginBasisPoints: _toInt(row['margin_basis_points']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ReportCashflowSummary> fetchCashflow({
    required ReportFilter filter,
  }) async {
    final database = await _databaseLoader();
    if (filter.paymentMethod != null) {
      return _fetchCashflowFilteredByPaymentMethod(database, filter: filter);
    }

    final totals = await _fetchCashflowTotals(database, filter: filter);
    final movementRows = await _fetchCashflowBreakdownRows(
      database,
      filter: filter,
    );
    final timeline = await _fetchCashflowTimeline(database, filter: filter);

    return ReportCashflowSummary(
      filter: filter,
      totalReceivedCents: totals.totalReceivedCents,
      fiadoReceiptsCents: totals.fiadoReceiptsCents,
      manualEntriesCents: totals.manualEntriesCents,
      outflowsCents: totals.outflowsCents,
      withdrawalsCents: totals.withdrawalsCents,
      netFlowCents: totals.netFlowCents,
      movementRows: movementRows,
      timeline: timeline,
    );
  }

  @override
  Future<ReportInventoryHealthSummary> fetchInventoryHealth({
    required ReportFilter filter,
  }) async {
    final database = await _databaseLoader();
    final items = await _loadInventoryItems(database, filter: filter);
    final criticalItems =
        items
            .where((item) => item.isZeroed || item.isBelowMinimum)
            .toList(growable: false)
          ..sort((a, b) {
            final severityA = a.isZeroed ? 0 : 1;
            final severityB = b.isZeroed ? 0 : 1;
            if (severityA != severityB) {
              return severityA.compareTo(severityB);
            }
            return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
          });

    final mostMovedItems = await _fetchMostMovedInventoryItems(
      database,
      filter: filter,
    );
    final recentMovements = await _fetchRecentInventoryMovements(
      database,
      filter: filter,
    );
    final divergenceItemsCount = await _fetchInventoryDivergencesCount(
      database,
      filter: filter,
    );

    final zeroedItemsCount = criticalItems
        .where((item) => item.isZeroed)
        .length;
    final belowMinimumItemsCount = criticalItems
        .where((item) => item.isBelowMinimum)
        .length;
    final belowMinimumOnlyItemsCount = items
        .where((item) => !item.isZeroed && item.isBelowMinimum)
        .length;
    final inventoryCostValueCents = items.fold<int>(
      0,
      (total, item) => total + item.estimatedCostCents,
    );
    final inventorySaleValueCents = items.fold<int>(
      0,
      (total, item) =>
          total + ((item.currentStockMil * item.salePriceCents) / 1000).round(),
    );

    return ReportInventoryHealthSummary(
      filter: filter,
      totalItemsCount: items.length,
      zeroedItemsCount: zeroedItemsCount,
      belowMinimumItemsCount: belowMinimumItemsCount,
      belowMinimumOnlyItemsCount: belowMinimumOnlyItemsCount,
      divergenceItemsCount: divergenceItemsCount,
      inventoryCostValueCents: inventoryCostValueCents,
      inventorySaleValueCents: inventorySaleValueCents,
      criticalItems: criticalItems.take(10).toList(growable: false),
      mostMovedItems: mostMovedItems,
      recentMovements: recentMovements,
    );
  }

  @override
  Future<List<ReportCustomerRankingRow>> fetchCustomerRanking({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final database = await _databaseLoader();
    final salesArguments = <Object?>[];
    final salesWhere = StringBuffer('WHERE 1 = 1');
    _appendSalesAggregateFilters(
      salesWhere,
      salesArguments,
      filter: filter,
      includePaymentMethod: false,
    );

    final arguments = <Object?>[...salesArguments, limit];
    final rows = await database.rawQuery('''
      WITH sale_totals AS (
        SELECT
          v.cliente_id AS customer_id,
          COUNT(*) AS sales_count,
          COALESCE(SUM(v.valor_final_centavos), 0) AS total_purchased_cents,
          MAX(v.data_venda) AS last_purchase_at
        FROM ${TableNames.vendas} v
        $salesWhere
          AND v.cliente_id IS NOT NULL
        GROUP BY v.cliente_id
      ),
      pending_fiado AS (
        SELECT
          cliente_id AS customer_id,
          COALESCE(SUM(valor_aberto_centavos), 0) AS pending_fiado_cents
        FROM ${TableNames.fiado}
        WHERE status IN ('pendente', 'parcial')
        GROUP BY cliente_id
      )
      SELECT
        c.id AS customer_id,
        c.nome AS customer_name,
        COALESCE(c.ativo, 1) AS is_active,
        COALESCE(st.sales_count, 0) AS sales_count,
        COALESCE(st.total_purchased_cents, 0) AS total_purchased_cents,
        COALESCE(pf.pending_fiado_cents, 0) AS pending_fiado_cents,
        COALESCE(c.credit_balance, 0) AS credit_balance_cents,
        st.last_purchase_at
      FROM ${TableNames.clientes} c
      LEFT JOIN sale_totals st ON st.customer_id = c.id
      LEFT JOIN pending_fiado pf ON pf.customer_id = c.id
      WHERE c.deletado_em IS NULL
      ORDER BY
        total_purchased_cents DESC,
        pending_fiado_cents DESC,
        credit_balance_cents DESC,
        customer_name COLLATE NOCASE ASC
      LIMIT ?
    ''', arguments);

    return rows
        .map(
          (row) => ReportCustomerRankingRow(
            customerId: row['customer_id'] as int,
            customerName: row['customer_name'] as String? ?? 'Cliente',
            isActive: _toInt(row['is_active']) == 1,
            salesCount: _toInt(row['sales_count']),
            totalPurchasedCents: _toInt(row['total_purchased_cents']),
            pendingFiadoCents: _toInt(row['pending_fiado_cents']),
            creditBalanceCents: _toInt(row['credit_balance_cents']),
            lastPurchaseAt: _parseNullableDate(row['last_purchase_at']),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ReportPurchaseSummary> fetchPurchaseSummary({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final database = await _databaseLoader();
    final totals = await _fetchPurchaseTotals(database, filter: filter);
    final totalPaidCents = await _fetchPurchasePaymentsTotal(
      database,
      filter: filter,
    );
    final supplierRows = await _fetchPurchaseSupplierRows(
      database,
      filter: filter,
      limit: limit,
    );
    final topItems = await _fetchTopPurchasedItems(
      database,
      filter: filter,
      limit: limit,
    );
    final replenishmentRows = await _fetchPurchaseVariantReplenishment(
      database,
      filter: filter,
      limit: limit,
    );

    return ReportPurchaseSummary(
      filter: filter,
      purchasesCount: totals.count,
      totalPurchasedCents: totals.totalPurchasedCents,
      totalPendingCents: totals.totalPendingCents,
      totalPaidCents: totalPaidCents,
      supplierRows: supplierRows,
      topItems: topItems,
      replenishmentRows: replenishmentRows,
    );
  }

  Future<_SalesAggregate> _fetchSalesAggregate(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        COUNT(*) AS sales_count,
        COALESCE(SUM(v.valor_total_centavos), 0) AS gross_sales_cents,
        COALESCE(SUM(v.valor_final_centavos), 0) AS net_sales_cents,
        COALESCE(SUM(v.desconto_centavos), 0) AS total_discount_cents,
        COALESCE(SUM(v.acrescimo_centavos), 0) AS total_surcharge_cents
      FROM ${TableNames.vendas} v
      WHERE 1 = 1
    ''');
    _appendSalesAggregateFilters(buffer, arguments, filter: filter);

    final rows = await database.rawQuery(buffer.toString(), arguments);
    final row = rows.first;
    return _SalesAggregate(
      salesCount: _toInt(row['sales_count']),
      grossSalesCents: _toInt(row['gross_sales_cents']),
      netSalesCents: _toInt(row['net_sales_cents']),
      totalDiscountCents: _toInt(row['total_discount_cents']),
      totalSurchargeCents: _toInt(row['total_surcharge_cents']),
    );
  }

  Future<int> _fetchCostOfGoodsSold(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT COALESCE(SUM($_costAmountExpression), 0) AS total_cost_cents
      FROM ${TableNames.itensVenda} iv
      INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
      WHERE 1 = 1
    ''');
    _appendSalesItemFilters(buffer, arguments, filter: filter);
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _toInt(rows.first['total_cost_cents']);
  }

  Future<int> _fetchRealizedProfit(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final cashArguments = <Object?>[];
    final cashWhere = StringBuffer('''
      WHERE v.status = 'ativa'
        AND v.tipo_venda = 'vista'
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      cashWhere,
      cashArguments,
      column: 'v.data_venda',
      filter: filter,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      cashWhere,
      cashArguments,
      column: 'v.cliente_id',
      value: filter.customerId,
    );
    if (filter.paymentMethod != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        cashWhere,
        cashArguments,
        column: 'v.forma_pagamento',
        value: filter.paymentMethod!.dbValue,
      );
    }
    if (filter.productId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        cashWhere,
        cashArguments,
        column: 'iv.produto_id',
        value: filter.productId,
      );
    }
    if (filter.variantId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        cashWhere,
        cashArguments,
        column: 'iv.produto_variante_id',
        value: filter.variantId,
      );
    }
    if (filter.categoryId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        cashWhere,
        cashArguments,
        column: 'p.categoria_id',
        value: filter.categoryId,
      );
    }

    final cashRows = await database.rawQuery('''
      SELECT COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) AS lucro
      FROM ${TableNames.itensVenda} iv
      INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
      $cashWhere
    ''', cashArguments);

    final fiadoArguments = <Object?>[];
    final fiadoSalesWhere = StringBuffer('''
      WHERE v.status = 'ativa'
        AND v.tipo_venda = 'fiado'
    ''');
    ReportSqlFiltersSupport.appendOptionalEquality(
      fiadoSalesWhere,
      fiadoArguments,
      column: 'v.cliente_id',
      value: filter.customerId,
    );
    if (filter.productId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        fiadoSalesWhere,
        fiadoArguments,
        column: 'iv.produto_id',
        value: filter.productId,
      );
    }
    if (filter.variantId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        fiadoSalesWhere,
        fiadoArguments,
        column: 'iv.produto_variante_id',
        value: filter.variantId,
      );
    }
    if (filter.categoryId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        fiadoSalesWhere,
        fiadoArguments,
        column: 'p.categoria_id',
        value: filter.categoryId,
      );
    }

    final paymentArguments = <Object?>[];
    final paymentWhere = StringBuffer('''
      WHERE lanc.tipo_lancamento = 'pagamento'
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      paymentWhere,
      paymentArguments,
      column: 'lanc.data_lancamento',
      filter: filter,
    );

    final fiadoRows = await database.rawQuery(
      '''
      WITH fiado_margens AS (
        SELECT
          f.id AS fiado_id,
          v.valor_final_centavos AS valor_final_centavos,
          COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) AS margem_total_centavos
        FROM ${TableNames.fiado} f
        INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
        INNER JOIN ${TableNames.itensVenda} iv ON iv.venda_id = v.id
        LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
        $fiadoSalesWhere
        GROUP BY f.id, v.valor_final_centavos
      ),
      pagamentos_periodo AS (
        SELECT
          lanc.fiado_id AS fiado_id,
          COALESCE(SUM(lanc.valor_centavos), 0) AS valor_pago_centavos
        FROM ${TableNames.fiadoLancamentos} lanc
        $paymentWhere
        GROUP BY lanc.fiado_id
      )
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN margem.valor_final_centavos <= 0 THEN 0
              ELSE CAST(
                ROUND(
                  (margem.margem_total_centavos * pagamentos.valor_pago_centavos) /
                  CAST(margem.valor_final_centavos AS REAL),
                  0
                ) AS INTEGER
              )
            END
          ),
          0
        ) AS lucro
      FROM fiado_margens margem
      INNER JOIN pagamentos_periodo pagamentos
        ON pagamentos.fiado_id = margem.fiado_id
    ''',
      [...fiadoArguments, ...paymentArguments],
    );

    return _toInt(cashRows.first['lucro']) + _toInt(fiadoRows.first['lucro']);
  }

  Future<_PendingFiadoAggregate> _fetchPendingFiado(
    DatabaseExecutor database,
  ) async {
    final rows = await database.rawQuery('''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_aberto_centavos), 0) AS total_aberto
      FROM ${TableNames.fiado}
      WHERE status IN ('pendente', 'parcial')
    ''');
    return _PendingFiadoAggregate(
      count: _toInt(rows.first['quantidade']),
      totalOpenCents: _toInt(rows.first['total_aberto']),
    );
  }

  Future<_CountAndAmount> _fetchCancelledSales(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_final_centavos), 0) AS total
      FROM ${TableNames.vendas}
      WHERE status = 'cancelada'
        AND cancelada_em IS NOT NULL
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'cancelada_em',
      filter: filter,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: 'cliente_id',
      value: filter.customerId,
    );

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _CountAndAmount(
      count: _toInt(rows.first['quantidade']),
      totalCents: _toInt(rows.first['total']),
    );
  }

  Future<_PurchaseTotalsAggregate> _fetchPurchaseTotals(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        COUNT(*) AS purchase_count,
        COALESCE(SUM(c.valor_final_centavos), 0) AS total_comprado,
        COALESCE(SUM(c.valor_pendente_centavos), 0) AS total_pendente
      FROM ${TableNames.compras} c
      WHERE c.status != 'cancelada'
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'c.data_compra',
      filter: filter,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: 'c.fornecedor_id',
      value: filter.supplierId,
    );
    if (filter.productId != null ||
        filter.variantId != null ||
        filter.categoryId != null) {
      buffer.write('''
        AND EXISTS (
          SELECT 1
          FROM ${TableNames.itensCompra} ic
          LEFT JOIN ${TableNames.produtos} p ON p.id = ic.produto_id
          WHERE ic.compra_id = c.id
      ''');
      if (filter.productId != null) {
        buffer.write(' AND ic.produto_id = ?');
        arguments.add(filter.productId);
      }
      if (filter.variantId != null) {
        buffer.write(' AND ic.produto_variante_id = ?');
        arguments.add(filter.variantId);
      }
      if (filter.categoryId != null) {
        buffer.write(' AND p.categoria_id = ?');
        arguments.add(filter.categoryId);
      }
      buffer.write(')');
    }

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _PurchaseTotalsAggregate(
      count: _toInt(rows.first['purchase_count']),
      totalPurchasedCents: _toInt(rows.first['total_comprado']),
      totalPendingCents: _toInt(rows.first['total_pendente']),
    );
  }

  Future<int> _fetchPurchasePaymentsTotal(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT COALESCE(SUM(cp.valor_centavos), 0) AS total_pago
      FROM ${TableNames.compraPagamentos} cp
      INNER JOIN ${TableNames.compras} c ON c.id = cp.compra_id
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'cp.data_hora',
      filter: filter,
    );
    if (filter.productId != null ||
        filter.variantId != null ||
        filter.categoryId != null) {
      buffer.write('''
        AND EXISTS (
          SELECT 1
          FROM ${TableNames.itensCompra} ic
          LEFT JOIN ${TableNames.produtos} p ON p.id = ic.produto_id
          WHERE ic.compra_id = c.id
      ''');
      if (filter.productId != null) {
        buffer.write(' AND ic.produto_id = ?');
        arguments.add(filter.productId);
      }
      if (filter.variantId != null) {
        buffer.write(' AND ic.produto_variante_id = ?');
        arguments.add(filter.variantId);
      }
      if (filter.categoryId != null) {
        buffer.write(' AND p.categoria_id = ?');
        arguments.add(filter.categoryId);
      }
      buffer.write(')');
    }
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _toInt(rows.first['total_pago']);
  }

  Future<_ReceivedTotalsAggregate> _fetchReceivedTotals(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        COALESCE(SUM(CASE WHEN mov.tipo_movimento = 'venda' THEN mov.valor_centavos ELSE 0 END), 0) AS vendas_recebidas,
        COALESCE(SUM(CASE WHEN mov.tipo_movimento = 'recebimento_fiado' THEN mov.valor_centavos ELSE 0 END), 0) AS fiado_recebido,
        COALESCE(SUM(mov.valor_centavos), 0) AS total_recebido
      FROM ${TableNames.caixaMovimentos} mov
      LEFT JOIN ${TableNames.vendas} sale
        ON mov.referencia_tipo = 'venda'
        AND sale.id = mov.referencia_id
      WHERE mov.tipo_movimento IN ('venda', 'recebimento_fiado', 'cancelamento')
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'mov.criado_em',
      filter: filter,
    );
    if (filter.customerId != null) {
      buffer.write('''
        AND (
          sale.cliente_id = ?
          OR EXISTS (
            SELECT 1
            FROM ${TableNames.fiadoLancamentos} lanc
            WHERE lanc.caixa_movimento_id = mov.id
              AND lanc.cliente_id = ?
          )
        )
      ''');
      arguments.add(filter.customerId);
      arguments.add(filter.customerId);
    }
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _ReceivedTotalsAggregate(
      cashSalesReceivedCents: _toInt(rows.first['vendas_recebidas']),
      fiadoReceiptsCents: _toInt(rows.first['fiado_recebido']),
      totalReceivedCents: _toInt(rows.first['total_recebido']),
    );
  }

  Future<_CreditTotalsAggregate> _fetchCreditTotals(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN type IN (
                '${CustomerCreditTransactionType.manualCredit}',
                '${CustomerCreditTransactionType.overpaymentCredit}',
                '${CustomerCreditTransactionType.saleReturnCredit}',
                '${CustomerCreditTransactionType.saleCancelCredit}',
                '${CustomerCreditTransactionType.changeLeftAsCredit}'
              ) AND amount > 0 THEN amount
              ELSE 0
            END
          ),
          0
        ) AS total_gerado,
        COALESCE(
          SUM(
            CASE
              WHEN type = '${CustomerCreditTransactionType.creditUsedInSale}'
              THEN ABS(amount)
              ELSE 0
            END
          ),
          0
        ) AS total_utilizado
      FROM ${TableNames.customerCreditTransactions}
      WHERE is_reversed = 0
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'created_at',
      filter: filter,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: 'customer_id',
      value: filter.customerId,
    );

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _CreditTotalsAggregate(
      totalGeneratedCents: _toInt(rows.first['total_gerado']),
      totalUsedCents: _toInt(rows.first['total_utilizado']),
    );
  }

  Future<int> _fetchOutstandingCredit(DatabaseExecutor database) async {
    final rows = await database.rawQuery('''
      SELECT COALESCE(SUM(credit_balance), 0) AS total_credito
      FROM ${TableNames.clientes}
      WHERE deletado_em IS NULL
    ''');
    return _toInt(rows.first['total_credito']);
  }

  Future<List<ReportCustomerCreditSummary>> _fetchTopCreditCustomers(
    DatabaseExecutor database,
  ) async {
    final rows = await database.rawQuery('''
      SELECT
        id,
        nome,
        credit_balance
      FROM ${TableNames.clientes}
      WHERE deletado_em IS NULL
        AND credit_balance > 0
      ORDER BY credit_balance DESC, nome COLLATE NOCASE ASC
      LIMIT 5
    ''');

    return rows
        .map(
          (row) => ReportCustomerCreditSummary(
            customerId: row['id'] as int,
            customerName: row['nome'] as String? ?? 'Cliente',
            balanceCents: _toInt(row['credit_balance']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ReportPaymentSummary>> _fetchPaymentSummaries(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        mov.valor_centavos,
        mov.descricao,
        sale.forma_pagamento AS sale_payment_method
      FROM ${TableNames.caixaMovimentos} mov
      LEFT JOIN ${TableNames.vendas} sale
        ON mov.referencia_tipo = 'venda'
        AND sale.id = mov.referencia_id
      WHERE mov.tipo_movimento IN ('venda', 'recebimento_fiado')
        AND mov.valor_centavos > 0
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'mov.criado_em',
      filter: filter,
    );
    if (filter.customerId != null) {
      buffer.write('''
        AND (
          sale.cliente_id = ?
          OR EXISTS (
            SELECT 1
            FROM ${TableNames.fiadoLancamentos} lanc
            WHERE lanc.caixa_movimento_id = mov.id
              AND lanc.cliente_id = ?
          )
        )
      ''');
      arguments.add(filter.customerId);
      arguments.add(filter.customerId);
    }
    buffer.write(' ORDER BY mov.criado_em DESC, mov.id DESC');
    final rows = await database.rawQuery(buffer.toString(), arguments);

    final paymentSummaryMap = <PaymentMethod, _PaymentAccumulator>{};
    for (final row in rows) {
      final paymentMethod =
          PaymentMethodNoteCodec.parse(row['descricao'] as String?) ??
          _paymentMethodFromDb(row['sale_payment_method'] as String?);
      if (paymentMethod == null) {
        continue;
      }
      if (filter.paymentMethod != null &&
          filter.paymentMethod != paymentMethod) {
        continue;
      }
      final current = paymentSummaryMap.putIfAbsent(
        paymentMethod,
        _PaymentAccumulator.new,
      );
      current.receivedCents += _toInt(row['valor_centavos']);
      current.operationsCount += 1;
    }

    return paymentSummaryMap.entries
        .map(
          (entry) => ReportPaymentSummary(
            paymentMethod: entry.key,
            receivedCents: entry.value.receivedCents,
            operationsCount: entry.value.operationsCount,
          ),
        )
        .toList()
      ..sort((a, b) => b.receivedCents.compareTo(a.receivedCents));
  }

  Future<_CashflowTotalsAggregate> _fetchCashflowTotals(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN mov.tipo_movimento IN ('venda', 'recebimento_fiado') AND mov.valor_centavos > 0
              THEN mov.valor_centavos
              ELSE 0
            END
          ),
          0
        ) AS total_received_cents,
        COALESCE(
          SUM(
            CASE
              WHEN mov.tipo_movimento = 'recebimento_fiado' AND mov.valor_centavos > 0
              THEN mov.valor_centavos
              ELSE 0
            END
          ),
          0
        ) AS fiado_receipts_cents,
        COALESCE(
          SUM(
            CASE
              WHEN mov.tipo_movimento = 'suprimento' THEN mov.valor_centavos
              WHEN mov.tipo_movimento = 'ajuste' AND mov.valor_centavos > 0 THEN mov.valor_centavos
              ELSE 0
            END
          ),
          0
        ) AS manual_entries_cents,
        COALESCE(
          SUM(
            CASE
              WHEN mov.valor_centavos < 0 THEN ABS(mov.valor_centavos)
              ELSE 0
            END
          ),
          0
        ) AS outflows_cents,
        COALESCE(
          SUM(
            CASE
              WHEN mov.tipo_movimento = 'sangria' THEN ABS(mov.valor_centavos)
              ELSE 0
            END
          ),
          0
        ) AS withdrawals_cents,
        COALESCE(SUM(mov.valor_centavos), 0) AS net_flow_cents
      FROM ${TableNames.caixaMovimentos} mov
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'mov.criado_em',
      filter: filter,
    );
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _CashflowTotalsAggregate(
      totalReceivedCents: _toInt(rows.first['total_received_cents']),
      fiadoReceiptsCents: _toInt(rows.first['fiado_receipts_cents']),
      manualEntriesCents: _toInt(rows.first['manual_entries_cents']),
      outflowsCents: _toInt(rows.first['outflows_cents']),
      withdrawalsCents: _toInt(rows.first['withdrawals_cents']),
      netFlowCents: _toInt(rows.first['net_flow_cents']),
    );
  }

  Future<List<ReportBreakdownRow>> _fetchCashflowBreakdownRows(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        mov.tipo_movimento AS movement_type,
        COUNT(*) AS movement_count,
        COALESCE(SUM(mov.valor_centavos), 0) AS amount_cents
      FROM ${TableNames.caixaMovimentos} mov
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'mov.criado_em',
      filter: filter,
    );
    buffer.write('''
      GROUP BY mov.tipo_movimento
      ORDER BY ABS(amount_cents) DESC, movement_type ASC
    ''');

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportBreakdownRow(
            label: _cashMovementLabel(row['movement_type'] as String?),
            description: row['movement_type'] as String?,
            amountCents: _toInt(row['amount_cents']),
            count: _toInt(row['movement_count']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ReportCashflowPoint>> _fetchCashflowTimeline(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final grouping = ReportGroupingSupport.normalizeTimeSeries(filter.grouping);
    final groupingSql = ReportGroupingSupport.timeBucketSql(
      grouping,
      column: 'mov.criado_em',
    );
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        ${groupingSql.keyExpression} AS bucket_key,
        COALESCE(
          SUM(CASE WHEN mov.valor_centavos > 0 THEN mov.valor_centavos ELSE 0 END),
          0
        ) AS inflow_cents,
        COALESCE(
          SUM(CASE WHEN mov.valor_centavos < 0 THEN ABS(mov.valor_centavos) ELSE 0 END),
          0
        ) AS outflow_cents,
        COALESCE(SUM(mov.valor_centavos), 0) AS net_cents
      FROM ${TableNames.caixaMovimentos} mov
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'mov.criado_em',
      filter: filter,
    );
    buffer.write('''
      GROUP BY ${groupingSql.keyExpression}
      ORDER BY ${groupingSql.orderExpression} ASC
    ''');

    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map((row) {
          final bucketStart = DateTime.parse(row['bucket_key'] as String);
          return ReportCashflowPoint(
            bucketStart: bucketStart,
            bucketEndExclusive: _resolveBucketEndExclusive(
              grouping,
              bucketStart,
            ),
            label: _formatBucketLabel(grouping, bucketStart),
            inflowCents: _toInt(row['inflow_cents']),
            outflowCents: _toInt(row['outflow_cents']),
            netCents: _toInt(row['net_cents']),
          );
        })
        .toList(growable: false);
  }

  Future<ReportCashflowSummary> _fetchCashflowFilteredByPaymentMethod(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        mov.tipo_movimento,
        mov.valor_centavos,
        mov.descricao,
        mov.criado_em,
        sale.forma_pagamento AS sale_payment_method
      FROM ${TableNames.caixaMovimentos} mov
      LEFT JOIN ${TableNames.vendas} sale
        ON mov.referencia_tipo = 'venda'
        AND sale.id = mov.referencia_id
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'mov.criado_em',
      filter: filter,
    );
    final rows = await database.rawQuery(buffer.toString(), arguments);

    final breakdownMap = <String, _PaymentFilteredCashBreakdown>{};
    final timelineMap = <String, _PaymentFilteredTimelineAccumulator>{};
    var totalReceivedCents = 0;
    var fiadoReceiptsCents = 0;
    var manualEntriesCents = 0;
    var outflowsCents = 0;
    var withdrawalsCents = 0;
    var netFlowCents = 0;
    final grouping = ReportGroupingSupport.normalizeTimeSeries(filter.grouping);

    for (final row in rows) {
      final paymentMethod =
          PaymentMethodNoteCodec.parse(row['descricao'] as String?) ??
          _paymentMethodFromDb(row['sale_payment_method'] as String?);
      final movementType = row['tipo_movimento'] as String? ?? '';
      if (_movementSupportsPaymentFilter(movementType) &&
          paymentMethod != filter.paymentMethod) {
        continue;
      }
      final amount = _toInt(row['valor_centavos']);
      final createdAt = DateTime.parse(row['criado_em'] as String);
      final bucketStart = _resolveBucketStart(grouping, createdAt);
      final bucketKey = bucketStart.toIso8601String();
      final timelineAccumulator = timelineMap.putIfAbsent(
        bucketKey,
        () => _PaymentFilteredTimelineAccumulator(bucketStart: bucketStart),
      );

      if (amount > 0) {
        timelineAccumulator.inflowCents += amount;
      } else if (amount < 0) {
        timelineAccumulator.outflowCents += amount.abs();
      }
      timelineAccumulator.netCents += amount;
      netFlowCents += amount;

      final breakdown = breakdownMap.putIfAbsent(
        movementType,
        () => _PaymentFilteredCashBreakdown(
          label: _cashMovementLabel(movementType),
        ),
      );
      breakdown.count += 1;
      breakdown.amountCents += amount;

      if ((movementType == 'venda' || movementType == 'recebimento_fiado') &&
          amount > 0) {
        totalReceivedCents += amount;
      }
      if (movementType == 'recebimento_fiado' && amount > 0) {
        fiadoReceiptsCents += amount;
      }
      if (movementType == 'suprimento' ||
          (movementType == 'ajuste' && amount > 0)) {
        manualEntriesCents += amount;
      }
      if (amount < 0) {
        outflowsCents += amount.abs();
      }
      if (movementType == 'sangria' && amount < 0) {
        withdrawalsCents += amount.abs();
      }
    }

    final movementRows =
        breakdownMap.values
            .map(
              (entry) => ReportBreakdownRow(
                label: entry.label,
                amountCents: entry.amountCents,
                count: entry.count,
              ),
            )
            .toList()
          ..sort((a, b) => b.amountCents.abs().compareTo(a.amountCents.abs()));

    final timeline =
        timelineMap.values
            .map(
              (entry) => ReportCashflowPoint(
                bucketStart: entry.bucketStart,
                bucketEndExclusive: _resolveBucketEndExclusive(
                  grouping,
                  entry.bucketStart,
                ),
                label: _formatBucketLabel(grouping, entry.bucketStart),
                inflowCents: entry.inflowCents,
                outflowCents: entry.outflowCents,
                netCents: entry.netCents,
              ),
            )
            .toList()
          ..sort((a, b) => a.bucketStart.compareTo(b.bucketStart));

    return ReportCashflowSummary(
      filter: filter,
      totalReceivedCents: totalReceivedCents,
      fiadoReceiptsCents: fiadoReceiptsCents,
      manualEntriesCents: manualEntriesCents,
      outflowsCents: outflowsCents,
      withdrawalsCents: withdrawalsCents,
      netFlowCents: netFlowCents,
      movementRows: movementRows,
      timeline: timeline,
    );
  }

  Future<List<InventoryItem>> _loadInventoryItems(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer(_inventoryItemsSelectSql);
    if (filter.categoryId != null) {
      buffer.write(' AND p.categoria_id = ?');
      arguments.add(filter.categoryId);
    }
    if (filter.productId != null) {
      buffer.write(' AND p.id = ?');
      arguments.add(filter.productId);
    }
    if (filter.variantId != null) {
      buffer.write(' AND pv.id = ?');
      arguments.add(filter.variantId);
    }
    buffer.write('''
      ORDER BY
        p.nome COLLATE NOCASE ASC,
        COALESCE(pv.ordem, 0) ASC,
        pv.id ASC
    ''');
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows.map(_mapInventoryItem).toList(growable: false);
  }

  Future<int> _fetchInventoryDivergencesCount(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT COUNT(*) AS divergence_count
      FROM ${TableNames.inventoryCountItems} ici
      INNER JOIN ${TableNames.inventoryCountSessions} ics
        ON ics.id = ici.count_session_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = ici.product_id
      WHERE ici.difference_mil != 0
        AND ics.status IN ('reviewed', 'applied')
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'ics.updated_at',
      filter: filter,
    );
    if (filter.categoryId != null) {
      buffer.write(' AND p.categoria_id = ?');
      arguments.add(filter.categoryId);
    }
    if (filter.productId != null) {
      buffer.write(' AND ici.product_id = ?');
      arguments.add(filter.productId);
    }
    if (filter.variantId != null) {
      buffer.write(' AND ici.product_variant_id = ?');
      arguments.add(filter.variantId);
    }
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return _toInt(rows.first['divergence_count']);
  }

  Future<List<ReportBreakdownRow>> _fetchMostMovedInventoryItems(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        im.product_id,
        im.product_variant_id,
        COALESCE(
          NULLIF(TRIM(p.model_name), ''),
          NULLIF(TRIM(p.nome), ''),
          'Produto'
        ) AS product_name,
        COALESCE(
          NULLIF(TRIM(pv.cor), ''),
          NULLIF(TRIM(pv.tamanho), '')
        ) AS variant_label,
        COALESCE(SUM(ABS(im.quantity_delta_mil)), 0) AS quantity_mil,
        COUNT(*) AS movement_count
      FROM ${TableNames.inventoryMovements} im
      INNER JOIN ${TableNames.produtos} p ON p.id = im.product_id
      LEFT JOIN ${TableNames.produtoVariantes} pv
        ON pv.id = im.product_variant_id
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'im.created_at',
      filter: filter,
    );
    if (filter.categoryId != null) {
      buffer.write(' AND p.categoria_id = ?');
      arguments.add(filter.categoryId);
    }
    if (filter.productId != null) {
      buffer.write(' AND im.product_id = ?');
      arguments.add(filter.productId);
    }
    if (filter.variantId != null) {
      buffer.write(' AND im.product_variant_id = ?');
      arguments.add(filter.variantId);
    }
    buffer.write('''
      GROUP BY im.product_id, im.product_variant_id, product_name, variant_label
      ORDER BY quantity_mil DESC, movement_count DESC, product_name COLLATE NOCASE ASC
      LIMIT 10
    ''');
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportBreakdownRow(
            label: _joinNonEmpty([
              row['product_name'] as String? ?? 'Produto',
              _cleanNullable(row['variant_label'] as String?),
            ], separator: ' - '),
            primaryId: row['product_id'] as int?,
            secondaryId: row['product_variant_id'] as int?,
            quantityMil: _toInt(row['quantity_mil']),
            count: _toInt(row['movement_count']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<InventoryMovement>> _fetchRecentInventoryMovements(
    DatabaseExecutor database, {
    required ReportFilter filter,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        im.*,
        p.nome AS product_name,
        COALESCE(NULLIF(TRIM(pv.sku), ''), NULLIF(TRIM(p.codigo_barras), '')) AS sku,
        pv.cor AS variant_color,
        pv.tamanho AS variant_size
      FROM ${TableNames.inventoryMovements} im
      INNER JOIN ${TableNames.produtos} p ON p.id = im.product_id
      LEFT JOIN ${TableNames.produtoVariantes} pv
        ON pv.id = im.product_variant_id
      WHERE 1 = 1
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'im.created_at',
      filter: filter,
    );
    if (filter.categoryId != null) {
      buffer.write(' AND p.categoria_id = ?');
      arguments.add(filter.categoryId);
    }
    if (filter.productId != null) {
      buffer.write(' AND im.product_id = ?');
      arguments.add(filter.productId);
    }
    if (filter.variantId != null) {
      buffer.write(' AND im.product_variant_id = ?');
      arguments.add(filter.variantId);
    }
    buffer.write(' ORDER BY im.created_at DESC, im.id DESC LIMIT 10');
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows.map(_mapInventoryMovement).toList(growable: false);
  }

  Future<List<ReportBreakdownRow>> _fetchPurchaseSupplierRows(
    DatabaseExecutor database, {
    required ReportFilter filter,
    required int limit,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        f.id AS supplier_id,
        COALESCE(NULLIF(TRIM(f.nome_fantasia), ''), f.nome, 'Fornecedor') AS supplier_name,
        COUNT(*) AS purchases_count,
        COALESCE(SUM(c.valor_final_centavos), 0) AS amount_cents
      FROM ${TableNames.compras} c
      INNER JOIN ${TableNames.fornecedores} f ON f.id = c.fornecedor_id
      WHERE c.status != 'cancelada'
    ''');
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: 'c.data_compra',
      filter: filter,
    );
    if (filter.productId != null ||
        filter.variantId != null ||
        filter.categoryId != null) {
      buffer.write('''
        AND EXISTS (
          SELECT 1
          FROM ${TableNames.itensCompra} ic
          LEFT JOIN ${TableNames.produtos} p ON p.id = ic.produto_id
          WHERE ic.compra_id = c.id
      ''');
      if (filter.productId != null) {
        buffer.write(' AND ic.produto_id = ?');
        arguments.add(filter.productId);
      }
      if (filter.variantId != null) {
        buffer.write(' AND ic.produto_variante_id = ?');
        arguments.add(filter.variantId);
      }
      if (filter.categoryId != null) {
        buffer.write(' AND p.categoria_id = ?');
        arguments.add(filter.categoryId);
      }
      buffer.write(')');
    }
    buffer.write('''
      GROUP BY f.id, supplier_name
      ORDER BY amount_cents DESC, purchases_count DESC, supplier_name COLLATE NOCASE ASC
      LIMIT ?
    ''');
    arguments.add(limit);
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportBreakdownRow(
            label: row['supplier_name'] as String? ?? 'Fornecedor',
            primaryId: row['supplier_id'] as int?,
            amountCents: _toInt(row['amount_cents']),
            count: _toInt(row['purchases_count']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ReportBreakdownRow>> _fetchTopPurchasedItems(
    DatabaseExecutor database, {
    required ReportFilter filter,
    required int limit,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        ic.produto_id AS product_id,
        ic.supply_id AS supply_id,
        ic.produto_variante_id AS variant_id,
        COALESCE(ic.nome_item_snapshot, 'Item') AS item_name,
        MAX(ic.unidade_medida_snapshot) AS unit_measure,
        COALESCE(SUM(ic.quantidade_mil), 0) AS quantity_mil,
        COALESCE(SUM(ic.subtotal_centavos), 0) AS amount_cents
      FROM ${TableNames.itensCompra} ic
      INNER JOIN ${TableNames.compras} c ON c.id = ic.compra_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = ic.produto_id
      WHERE 1 = 1
    ''');
    _appendPurchaseItemFilters(buffer, arguments, filter: filter);
    buffer.write('''
      GROUP BY ic.produto_id, ic.supply_id, ic.produto_variante_id, item_name
      ORDER BY amount_cents DESC, quantity_mil DESC, item_name COLLATE NOCASE ASC
      LIMIT ?
    ''');
    arguments.add(limit);
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportBreakdownRow(
            label: row['item_name'] as String? ?? 'Item',
            primaryId: row['product_id'] as int? ?? row['supply_id'] as int?,
            secondaryId: row['variant_id'] as int?,
            amountCents: _toInt(row['amount_cents']),
            quantityMil: _toInt(row['quantity_mil']),
            description: row['unit_measure'] as String?,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ReportBreakdownRow>> _fetchPurchaseVariantReplenishment(
    DatabaseExecutor database, {
    required ReportFilter filter,
    required int limit,
  }) async {
    final arguments = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        ic.produto_id AS product_id,
        ic.produto_variante_id AS variant_id,
        MAX(
          COALESCE(
            NULLIF(TRIM(p.model_name), ''),
            NULLIF(TRIM(ic.nome_item_snapshot), ''),
            NULLIF(TRIM(p.nome), ''),
            'Produto'
          )
        ) AS model_name,
        MAX(
          TRIM(
            COALESCE(
              NULLIF(TRIM(ic.cor_variante_snapshot), ''),
              NULLIF(TRIM(pv.cor), '')
            ) ||
            CASE
              WHEN COALESCE(NULLIF(TRIM(ic.cor_variante_snapshot), ''), NULLIF(TRIM(pv.cor), '')) != ''
                AND COALESCE(NULLIF(TRIM(ic.tamanho_variante_snapshot), ''), NULLIF(TRIM(pv.tamanho), '')) != ''
              THEN ' / '
              ELSE ''
            END ||
            COALESCE(
              NULLIF(TRIM(ic.tamanho_variante_snapshot), ''),
              NULLIF(TRIM(pv.tamanho), '')
            )
          )
        ) AS variant_label,
        COALESCE(SUM(ic.quantidade_mil), 0) AS quantity_mil,
        COALESCE(SUM(ic.subtotal_centavos), 0) AS amount_cents
      FROM ${TableNames.itensCompra} ic
      INNER JOIN ${TableNames.compras} c ON c.id = ic.compra_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = ic.produto_id
      LEFT JOIN ${TableNames.produtoVariantes} pv
        ON pv.id = ic.produto_variante_id
      WHERE 1 = 1
    ''');
    _appendPurchaseItemFilters(buffer, arguments, filter: filter);
    buffer.write('''
      AND ic.produto_variante_id IS NOT NULL
      GROUP BY ic.produto_id, ic.produto_variante_id
      ORDER BY quantity_mil DESC, amount_cents DESC, model_name COLLATE NOCASE ASC
      LIMIT ?
    ''');
    arguments.add(limit);
    final rows = await database.rawQuery(buffer.toString(), arguments);
    return rows
        .map(
          (row) => ReportBreakdownRow(
            label: _joinNonEmpty([
              row['model_name'] as String? ?? 'Produto',
              _cleanNullable(row['variant_label'] as String?),
            ], separator: ' - '),
            primaryId: row['product_id'] as int?,
            secondaryId: row['variant_id'] as int?,
            amountCents: _toInt(row['amount_cents']),
            quantityMil: _toInt(row['quantity_mil']),
          ),
        )
        .toList(growable: false);
  }

  void _appendSalesAggregateFilters(
    StringBuffer buffer,
    List<Object?> arguments, {
    required ReportFilter filter,
    String saleAlias = 'v',
    bool includePaymentMethod = true,
  }) {
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: '$saleAlias.data_venda',
      filter: filter,
    );
    if (!filter.includeCanceled) {
      buffer.write(" AND $saleAlias.status = 'ativa'");
    }
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$saleAlias.cliente_id',
      value: filter.customerId,
    );
    if (includePaymentMethod && filter.paymentMethod != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        buffer,
        arguments,
        column: '$saleAlias.forma_pagamento',
        value: filter.paymentMethod!.dbValue,
      );
    }
    _appendSalesExistsClause(
      buffer,
      arguments,
      filter: filter,
      saleAlias: saleAlias,
    );
  }

  void _appendSalesItemFilters(
    StringBuffer buffer,
    List<Object?> arguments, {
    required ReportFilter filter,
    String saleAlias = 'v',
    String itemAlias = 'iv',
    String productAlias = 'p',
  }) {
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: '$saleAlias.data_venda',
      filter: filter,
    );
    buffer.write(" AND $saleAlias.status = 'ativa'");
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$saleAlias.cliente_id',
      value: filter.customerId,
    );
    if (filter.paymentMethod != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        buffer,
        arguments,
        column: '$saleAlias.forma_pagamento',
        value: filter.paymentMethod!.dbValue,
      );
    }
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$itemAlias.produto_id',
      value: filter.productId,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$itemAlias.produto_variante_id',
      value: filter.variantId,
    );
    if (filter.categoryId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        buffer,
        arguments,
        column: '$productAlias.categoria_id',
        value: filter.categoryId,
      );
    }
  }

  void _appendPurchaseItemFilters(
    StringBuffer buffer,
    List<Object?> arguments, {
    required ReportFilter filter,
    String purchaseAlias = 'c',
    String itemAlias = 'ic',
    String productAlias = 'p',
  }) {
    buffer.write(" AND $purchaseAlias.status != 'cancelada'");
    ReportSqlFiltersSupport.appendDateRange(
      buffer,
      arguments,
      column: '$purchaseAlias.data_compra',
      filter: filter,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$purchaseAlias.fornecedor_id',
      value: filter.supplierId,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$itemAlias.produto_id',
      value: filter.productId,
    );
    ReportSqlFiltersSupport.appendOptionalEquality(
      buffer,
      arguments,
      column: '$itemAlias.produto_variante_id',
      value: filter.variantId,
    );
    if (filter.categoryId != null) {
      ReportSqlFiltersSupport.appendOptionalEquality(
        buffer,
        arguments,
        column: '$productAlias.categoria_id',
        value: filter.categoryId,
      );
    }
  }

  void _appendSalesExistsClause(
    StringBuffer buffer,
    List<Object?> arguments, {
    required ReportFilter filter,
    required String saleAlias,
  }) {
    if (filter.productId == null &&
        filter.variantId == null &&
        filter.categoryId == null) {
      return;
    }
    buffer.write('''
      AND EXISTS (
        SELECT 1
        FROM ${TableNames.itensVenda} iv_filter
        LEFT JOIN ${TableNames.produtos} p_filter ON p_filter.id = iv_filter.produto_id
        WHERE iv_filter.venda_id = $saleAlias.id
    ''');
    if (filter.productId != null) {
      buffer.write(' AND iv_filter.produto_id = ?');
      arguments.add(filter.productId);
    }
    if (filter.variantId != null) {
      buffer.write(' AND iv_filter.produto_variante_id = ?');
      arguments.add(filter.variantId);
    }
    if (filter.categoryId != null) {
      buffer.write(' AND p_filter.categoria_id = ?');
      arguments.add(filter.categoryId);
    }
    buffer.write(')');
  }

  String _buildProfitabilityBaseSql(ReportGrouping grouping) {
    switch (grouping) {
      case ReportGrouping.variant:
        return '''
          SELECT
            iv.produto_id AS product_id,
            iv.produto_variante_id AS variant_id,
            NULL AS category_id,
            MAX(
              COALESCE(
                NULLIF(TRIM(p.model_name), ''),
                NULLIF(TRIM(iv.nome_produto_snapshot), ''),
                NULLIF(TRIM(p.nome), ''),
                'Produto'
              )
            ) AS label,
            MAX(
              TRIM(
                COALESCE(NULLIF(TRIM(iv.cor_variante_snapshot), ''), NULLIF(TRIM(pv.cor), '')) ||
                CASE
                  WHEN COALESCE(NULLIF(TRIM(iv.cor_variante_snapshot), ''), NULLIF(TRIM(pv.cor), '')) != ''
                    AND COALESCE(NULLIF(TRIM(iv.tamanho_variante_snapshot), ''), NULLIF(TRIM(pv.tamanho), '')) != ''
                  THEN ' / '
                  ELSE ''
                END ||
                COALESCE(NULLIF(TRIM(iv.tamanho_variante_snapshot), ''), NULLIF(TRIM(pv.tamanho), ''))
              )
            ) AS description,
            COALESCE(SUM(iv.quantidade_mil), 0) AS quantity_mil,
            COALESCE(SUM($_soldAmountExpression), 0) AS revenue_cents,
            COALESCE(SUM($_costAmountExpression), 0) AS cost_cents,
            COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) AS profit_cents,
            CASE
              WHEN COALESCE(SUM($_soldAmountExpression), 0) <= 0 THEN 0
              ELSE CAST(
                ROUND(
                  COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) * 10000.0 /
                  COALESCE(SUM($_soldAmountExpression), 1),
                  0
                ) AS INTEGER
              )
            END AS margin_basis_points
          FROM ${TableNames.itensVenda} iv
          INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
          LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
          LEFT JOIN ${TableNames.produtoVariantes} pv
            ON pv.id = iv.produto_variante_id
          WHERE 1 = 1
        ''';
      case ReportGrouping.category:
        return '''
          SELECT
            NULL AS product_id,
            NULL AS variant_id,
            p.categoria_id AS category_id,
            COALESCE(cat.nome, 'Sem categoria') AS label,
            NULL AS description,
            COALESCE(SUM(iv.quantidade_mil), 0) AS quantity_mil,
            COALESCE(SUM($_soldAmountExpression), 0) AS revenue_cents,
            COALESCE(SUM($_costAmountExpression), 0) AS cost_cents,
            COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) AS profit_cents,
            CASE
              WHEN COALESCE(SUM($_soldAmountExpression), 0) <= 0 THEN 0
              ELSE CAST(
                ROUND(
                  COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) * 10000.0 /
                  COALESCE(SUM($_soldAmountExpression), 1),
                  0
                ) AS INTEGER
              )
            END AS margin_basis_points
          FROM ${TableNames.itensVenda} iv
          INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
          LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
          LEFT JOIN ${TableNames.categorias} cat ON cat.id = p.categoria_id
          WHERE 1 = 1
        ''';
      case ReportGrouping.product:
      case ReportGrouping.day:
      case ReportGrouping.week:
      case ReportGrouping.month:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return '''
          SELECT
            iv.produto_id AS product_id,
            NULL AS variant_id,
            p.categoria_id AS category_id,
            COALESCE(
              NULLIF(TRIM(iv.nome_produto_snapshot), ''),
              NULLIF(TRIM(p.model_name), ''),
              NULLIF(TRIM(p.nome), ''),
              'Produto'
            ) AS label,
            MAX(COALESCE(iv.unidade_medida_snapshot, p.unidade_medida, 'un')) AS description,
            COALESCE(SUM(iv.quantidade_mil), 0) AS quantity_mil,
            COALESCE(SUM($_soldAmountExpression), 0) AS revenue_cents,
            COALESCE(SUM($_costAmountExpression), 0) AS cost_cents,
            COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) AS profit_cents,
            CASE
              WHEN COALESCE(SUM($_soldAmountExpression), 0) <= 0 THEN 0
              ELSE CAST(
                ROUND(
                  COALESCE(SUM($_soldAmountExpression - $_costAmountExpression), 0) * 10000.0 /
                  COALESCE(SUM($_soldAmountExpression), 1),
                  0
                ) AS INTEGER
              )
            END AS margin_basis_points
          FROM ${TableNames.itensVenda} iv
          INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
          LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
          WHERE 1 = 1
        ''';
    }
  }

  String _buildProfitabilityGroupingSql(ReportGrouping grouping) {
    switch (grouping) {
      case ReportGrouping.variant:
        return '''
          GROUP BY iv.produto_id, iv.produto_variante_id
          ORDER BY profit_cents DESC, revenue_cents DESC, label COLLATE NOCASE ASC
        ''';
      case ReportGrouping.category:
        return '''
          GROUP BY p.categoria_id, COALESCE(cat.nome, 'Sem categoria')
          ORDER BY profit_cents DESC, revenue_cents DESC, label COLLATE NOCASE ASC
        ''';
      case ReportGrouping.product:
      case ReportGrouping.day:
      case ReportGrouping.week:
      case ReportGrouping.month:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return '''
          GROUP BY iv.produto_id, label
          ORDER BY profit_cents DESC, revenue_cents DESC, label COLLATE NOCASE ASC
        ''';
    }
  }

  ReportGrouping _resolveProfitabilityGrouping(ReportGrouping grouping) {
    switch (grouping) {
      case ReportGrouping.variant:
      case ReportGrouping.category:
      case ReportGrouping.product:
        return grouping;
      case ReportGrouping.day:
      case ReportGrouping.week:
      case ReportGrouping.month:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return ReportGrouping.product;
    }
  }

  InventoryItem _mapInventoryItem(Map<String, Object?> row) {
    return InventoryItem(
      productId: row['product_id'] as int,
      productVariantId: row['product_variant_id'] as int?,
      productName: row['product_name'] as String? ?? 'Produto',
      sku: _cleanNullable(row['sku'] as String?),
      variantColorLabel: _cleanNullable(row['variant_color'] as String?),
      variantSizeLabel: _cleanNullable(row['variant_size'] as String?),
      unitMeasure: row['unit_measure'] as String? ?? 'un',
      currentStockMil: _toInt(row['current_stock_mil']),
      minimumStockMil: _toInt(row['minimum_stock_mil']),
      reorderPointMil: row['reorder_point_mil'] as int?,
      allowNegativeStock: _toInt(row['allow_negative_stock']) == 1,
      costCents: _toInt(row['cost_cents']),
      salePriceCents: _toInt(row['sale_price_cents']),
      isActive: _toInt(row['is_active']) == 1,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  InventoryMovement _mapInventoryMovement(Map<String, Object?> row) {
    return InventoryMovement(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      productId: row['product_id'] as int,
      productVariantId: row['product_variant_id'] as int?,
      productName: row['product_name'] as String? ?? 'Produto',
      sku: _cleanNullable(row['sku'] as String?),
      variantColorLabel: _cleanNullable(row['variant_color'] as String?),
      variantSizeLabel: _cleanNullable(row['variant_size'] as String?),
      movementType: inventoryMovementTypeFromStorage(
        row['movement_type'] as String?,
      ),
      quantityDeltaMil: _toInt(row['quantity_delta_mil']),
      stockBeforeMil: _toInt(row['stock_before_mil']),
      stockAfterMil: _toInt(row['stock_after_mil']),
      referenceType: row['reference_type'] as String? ?? 'manual_adjustment',
      referenceId: row['reference_id'] as int?,
      reason: _cleanNullable(row['reason'] as String?),
      notes: _cleanNullable(row['notes'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  DateTime _resolveBucketStart(ReportGrouping grouping, DateTime date) {
    switch (grouping) {
      case ReportGrouping.day:
        return DateTime(date.year, date.month, date.day);
      case ReportGrouping.week:
        final base = DateTime(date.year, date.month, date.day);
        final weekdayOffset = base.weekday - DateTime.monday;
        return base.subtract(Duration(days: weekdayOffset));
      case ReportGrouping.month:
        return DateTime(date.year, date.month);
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return DateTime(date.year, date.month, date.day);
    }
  }

  DateTime _resolveBucketEndExclusive(ReportGrouping grouping, DateTime start) {
    switch (grouping) {
      case ReportGrouping.day:
        return start.add(const Duration(days: 1));
      case ReportGrouping.week:
        return start.add(const Duration(days: 7));
      case ReportGrouping.month:
        return start.month == DateTime.december
            ? DateTime(start.year + 1)
            : DateTime(start.year, start.month + 1);
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return start.add(const Duration(days: 1));
    }
  }

  String _formatBucketLabel(ReportGrouping grouping, DateTime start) {
    switch (grouping) {
      case ReportGrouping.day:
        return _formatDate(start);
      case ReportGrouping.week:
        return 'Sem ${_formatDate(start)}';
      case ReportGrouping.month:
        return '${start.month.toString().padLeft(2, '0')}/${start.year}';
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return _formatDate(start);
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  String _cashMovementLabel(String? rawType) {
    switch (rawType) {
      case 'venda':
        return 'Vendas';
      case 'recebimento_fiado':
        return 'Recebimento de fiado';
      case 'sangria':
        return 'Sangrias';
      case 'suprimento':
        return 'Suprimentos';
      case 'ajuste':
        return 'Ajustes';
      case 'cancelamento':
        return 'Cancelamentos';
      default:
        return 'Movimento';
    }
  }

  bool _movementSupportsPaymentFilter(String movementType) {
    return movementType == 'venda' || movementType == 'recebimento_fiado';
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  DateTime? _parseNullableDate(Object? value) {
    final raw = value as String?;
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.parse(raw);
  }

  String _joinNonEmpty(Iterable<String?> parts, {required String separator}) {
    final filtered = parts
        .map((part) => part?.trim())
        .where((part) => part != null && part.isNotEmpty)
        .cast<String>()
        .toList(growable: false);
    return filtered.join(separator);
  }

  PaymentMethod? _paymentMethodFromDb(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return PaymentMethodX.fromDb(value);
  }

  static const String _inventoryItemsSelectSql =
      '''
    SELECT
      p.id AS product_id,
      pv.id AS product_variant_id,
      p.nome AS product_name,
      COALESCE(NULLIF(TRIM(pv.sku), ''), NULLIF(TRIM(p.codigo_barras), '')) AS sku,
      pv.cor AS variant_color,
      pv.tamanho AS variant_size,
      p.unidade_medida AS unit_measure,
      COALESCE(pv.estoque_mil, p.estoque_mil, 0) AS current_stock_mil,
      COALESCE((
        SELECT s.minimum_stock_mil
        FROM ${TableNames.inventorySettings} s
        WHERE s.product_id = p.id
          AND (
            (pv.id IS NULL AND s.product_variant_id IS NULL)
            OR s.product_variant_id = pv.id
          )
        ORDER BY s.id DESC
        LIMIT 1
      ), 0) AS minimum_stock_mil,
      (
        SELECT s.reorder_point_mil
        FROM ${TableNames.inventorySettings} s
        WHERE s.product_id = p.id
          AND (
            (pv.id IS NULL AND s.product_variant_id IS NULL)
            OR s.product_variant_id = pv.id
          )
        ORDER BY s.id DESC
        LIMIT 1
      ) AS reorder_point_mil,
      COALESCE((
        SELECT s.allow_negative_stock
        FROM ${TableNames.inventorySettings} s
        WHERE s.product_id = p.id
          AND (
            (pv.id IS NULL AND s.product_variant_id IS NULL)
            OR s.product_variant_id = pv.id
          )
        ORDER BY s.id DESC
        LIMIT 1
      ), 0) AS allow_negative_stock,
      p.custo_centavos AS cost_cents,
      p.preco_venda_centavos + COALESCE(pv.preco_adicional_centavos, 0)
        AS sale_price_cents,
      CASE
        WHEN p.ativo = 1 AND COALESCE(pv.ativo, 1) = 1 THEN 1
        ELSE 0
      END AS is_active,
      COALESCE(pv.atualizado_em, p.atualizado_em) AS updated_at
    FROM ${TableNames.produtos} p
    LEFT JOIN ${TableNames.produtoVariantes} pv
      ON pv.produto_id = p.id
    WHERE p.deletado_em IS NULL
  ''';
}

class _SalesAggregate {
  const _SalesAggregate({
    required this.salesCount,
    required this.grossSalesCents,
    required this.netSalesCents,
    required this.totalDiscountCents,
    required this.totalSurchargeCents,
  });

  final int salesCount;
  final int grossSalesCents;
  final int netSalesCents;
  final int totalDiscountCents;
  final int totalSurchargeCents;
}

class _PendingFiadoAggregate {
  const _PendingFiadoAggregate({
    required this.count,
    required this.totalOpenCents,
  });

  final int count;
  final int totalOpenCents;
}

class _CountAndAmount {
  const _CountAndAmount({required this.count, required this.totalCents});

  final int count;
  final int totalCents;
}

class _PurchaseTotalsAggregate {
  const _PurchaseTotalsAggregate({
    required this.count,
    required this.totalPurchasedCents,
    required this.totalPendingCents,
  });

  final int count;
  final int totalPurchasedCents;
  final int totalPendingCents;
}

class _ReceivedTotalsAggregate {
  const _ReceivedTotalsAggregate({
    required this.cashSalesReceivedCents,
    required this.fiadoReceiptsCents,
    required this.totalReceivedCents,
  });

  final int cashSalesReceivedCents;
  final int fiadoReceiptsCents;
  final int totalReceivedCents;
}

class _CreditTotalsAggregate {
  const _CreditTotalsAggregate({
    required this.totalGeneratedCents,
    required this.totalUsedCents,
  });

  final int totalGeneratedCents;
  final int totalUsedCents;
}

class _CashflowTotalsAggregate {
  const _CashflowTotalsAggregate({
    required this.totalReceivedCents,
    required this.fiadoReceiptsCents,
    required this.manualEntriesCents,
    required this.outflowsCents,
    required this.withdrawalsCents,
    required this.netFlowCents,
  });

  final int totalReceivedCents;
  final int fiadoReceiptsCents;
  final int manualEntriesCents;
  final int outflowsCents;
  final int withdrawalsCents;
  final int netFlowCents;
}

class _PaymentAccumulator {
  int receivedCents = 0;
  int operationsCount = 0;
}

class _PaymentFilteredCashBreakdown {
  _PaymentFilteredCashBreakdown({required this.label});

  final String label;
  int count = 0;
  int amountCents = 0;
}

class _PaymentFilteredTimelineAccumulator {
  _PaymentFilteredTimelineAccumulator({required this.bucketStart});

  final DateTime bucketStart;
  int inflowCents = 0;
  int outflowCents = 0;
  int netCents = 0;
}
