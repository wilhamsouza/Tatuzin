import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/report_breakdown_row.dart';
import '../domain/entities/report_cashflow_point.dart';
import '../domain/entities/report_cashflow_summary.dart';
import '../domain/entities/report_customer_ranking_row.dart';
import '../domain/entities/report_data_origin_notice.dart';
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
import 'datasources/analytics_reports_remote_datasource.dart';

class AnalyticsReportRepository implements ReportRepository {
  const AnalyticsReportRepository({
    required AnalyticsReportsRemoteDatasource remoteDatasource,
    required ReportRepository localFallbackRepository,
    bool canUseRemoteAnalytics = true,
  }) : _remoteDatasource = remoteDatasource,
       _localFallbackRepository = localFallbackRepository,
       _canUseRemoteAnalytics = canUseRemoteAnalytics;

  final AnalyticsReportsRemoteDatasource _remoteDatasource;
  final ReportRepository _localFallbackRepository;
  final bool _canUseRemoteAnalytics;

  static const Duration remoteTimeout = Duration(seconds: 15);
  static const Duration localFallbackTimeout = Duration(seconds: 12);

  @override
  Future<ReportCashflowSummary> fetchCashflow({
    required ReportFilter filter,
  }) async {
    final result = await fetchCashflowResult(filter: filter);
    return result.data;
  }

  Future<ReportResult<ReportCashflowSummary>> fetchCashflowResult({
    required ReportFilter filter,
  }) async {
    return _remoteFirstResult(
      label: 'management.cashflow',
      scope: ReportDataOriginScope.cash,
      remote: () async {
        final report = await _remoteDatasource
            .fetchCashConsolidated(filter: filter)
            .timeout(remoteTimeout);
        return ReportCashflowSummary(
          filter: filter,
          totalReceivedCents: report.totalInflowCents,
          fiadoReceiptsCents: 0,
          manualEntriesCents: 0,
          outflowsCents: report.totalOutflowCents,
          withdrawalsCents: 0,
          netFlowCents: report.totalNetCents,
          movementRows: <ReportBreakdownRow>[
            ReportBreakdownRow(
              label: 'Entradas remotas',
              amountCents: report.totalInflowCents,
              count: report.series.length,
            ),
            ReportBreakdownRow(
              label: 'Saidas remotas',
              amountCents: report.totalOutflowCents,
              count: report.series.length,
            ),
          ],
          timeline: report.series
              .map(_cashPointFromRemote)
              .toList(growable: false),
        );
      },
      fallback: () => _localFallbackRepository
          .fetchCashflow(filter: filter)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<List<ReportCustomerRankingRow>> fetchCustomerRanking({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final result = await fetchCustomerRankingResult(
      filter: filter,
      limit: limit,
    );
    return result.data;
  }

  Future<ReportResult<List<ReportCustomerRankingRow>>>
  fetchCustomerRankingResult({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    return _localOnlyForMissingContractResult(
      label: 'management.customerRanking',
      scope: ReportDataOriginScope.customers,
      fallback: () => _localFallbackRepository
          .fetchCustomerRanking(filter: filter, limit: limit)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<ReportInventoryHealthSummary> fetchInventoryHealth({
    required ReportFilter filter,
  }) async {
    final result = await fetchInventoryHealthResult(filter: filter);
    return result.data;
  }

  Future<ReportResult<ReportInventoryHealthSummary>>
  fetchInventoryHealthResult({required ReportFilter filter}) async {
    return _localOnlyForMissingContractResult(
      label: 'management.inventoryHealth',
      scope: ReportDataOriginScope.inventory,
      fallback: () => _localFallbackRepository
          .fetchInventoryHealth(filter: filter)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<ReportOverviewSummary> fetchOverview({
    required ReportFilter filter,
  }) async {
    final result = await fetchOverviewResult(filter: filter);
    return result.data;
  }

  Future<ReportResult<ReportOverviewSummary>> fetchOverviewResult({
    required ReportFilter filter,
  }) async {
    return _remoteFirstResult(
      label: 'management.overview',
      scope: ReportDataOriginScope.overview,
      remote: () async {
        final financial = await _remoteDatasource
            .fetchFinancialSummary(filter: filter)
            .timeout(remoteTimeout);
        final trend = await _remoteDatasource
            .fetchSalesByDay(filter: filter)
            .timeout(remoteTimeout);
        final salesCount = trend.series.fold<int>(
          0,
          (total, point) => total + point.salesCount,
        );
        return ReportOverviewSummary(
          filter: filter,
          grossSalesCents: financial.salesAmountCents,
          netSalesCents: financial.salesAmountCents,
          totalReceivedCents:
              financial.cashNetCents + financial.fiadoPaymentsAmountCents,
          costOfGoodsSoldCents: financial.salesCostCents,
          realizedProfitCents: financial.salesProfitCents,
          salesCount: salesCount,
          totalDiscountCents: 0,
          totalSurchargeCents: 0,
          pendingFiadoCents: 0,
          pendingFiadoCount: 0,
          cancelledSalesCount: 0,
          cancelledSalesCents: 0,
          totalPurchasedCents: financial.purchasesAmountCents,
          totalPurchasePaymentsCents: 0,
          totalPurchasePendingCents: 0,
          cashSalesReceivedCents: financial.cashNetCents,
          fiadoReceiptsCents: financial.fiadoPaymentsAmountCents,
          totalCreditGeneratedCents: 0,
          totalCreditUsedCents: 0,
          totalOutstandingCreditCents: 0,
          topCreditCustomers: const [],
          paymentSummaries: <ReportPaymentSummary>[
            ReportPaymentSummary(
              paymentMethod: PaymentMethod.cash,
              receivedCents: financial.cashNetCents,
              operationsCount: salesCount,
            ),
            ReportPaymentSummary(
              paymentMethod: PaymentMethod.fiado,
              receivedCents: financial.fiadoPaymentsAmountCents,
              operationsCount: 0,
            ),
          ],
        );
      },
      fallback: () => _localFallbackRepository
          .fetchOverview(filter: filter)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<List<ReportProfitabilityRow>> fetchProfitability({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final result = await fetchProfitabilityResult(filter: filter, limit: limit);
    return result.data;
  }

  Future<ReportResult<List<ReportProfitabilityRow>>> fetchProfitabilityResult({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    if (filter.grouping != ReportGrouping.product ||
        filter.categoryId != null ||
        filter.productId != null ||
        filter.variantId != null) {
      return _localOnlyForMissingContractResult(
        label: 'management.profitability.${filter.grouping.name}',
        scope: ReportDataOriginScope.profitability,
        fallback: () => _localFallbackRepository
            .fetchProfitability(filter: filter, limit: limit)
            .timeout(localFallbackTimeout),
      );
    }

    return _remoteFirstResult(
      label: 'management.profitability.product',
      scope: ReportDataOriginScope.profitability,
      remote: () async {
        final report = await _remoteDatasource
            .fetchSalesByProduct(filter: filter, limit: limit)
            .timeout(remoteTimeout);
        return report.items
            .map(
              (item) => ReportProfitabilityRow(
                grouping: ReportGrouping.product,
                label: item.productName,
                productId: null,
                quantityMil: item.quantityMil,
                revenueCents: item.revenueCents,
                costCents: item.costCents,
                profitCents: item.profitCents,
                marginBasisPoints: item.revenueCents <= 0
                    ? 0
                    : ((item.profitCents / item.revenueCents) * 10000).round(),
              ),
            )
            .toList(growable: false);
      },
      fallback: () => _localFallbackRepository
          .fetchProfitability(filter: filter, limit: limit)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<ReportPurchaseSummary> fetchPurchaseSummary({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final result = await fetchPurchaseSummaryResult(
      filter: filter,
      limit: limit,
    );
    return result.data;
  }

  Future<ReportResult<ReportPurchaseSummary>> fetchPurchaseSummaryResult({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    return _localOnlyForMissingContractResult(
      label: 'management.purchaseSummary',
      scope: ReportDataOriginScope.purchases,
      fallback: () => _localFallbackRepository
          .fetchPurchaseSummary(filter: filter, limit: limit)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<List<ReportSalesTrendPoint>> fetchSalesTrend({
    required ReportFilter filter,
  }) async {
    final result = await fetchSalesTrendResult(filter: filter);
    return result.data;
  }

  Future<ReportResult<List<ReportSalesTrendPoint>>> fetchSalesTrendResult({
    required ReportFilter filter,
  }) async {
    if (filter.customerId != null ||
        filter.categoryId != null ||
        filter.productId != null ||
        filter.variantId != null ||
        filter.paymentMethod != null ||
        filter.includeCanceled ||
        filter.onlyCanceled) {
      return _localOnlyForMissingContractResult(
        label: 'management.salesTrend.filtered',
        scope: ReportDataOriginScope.sales,
        fallback: () => _localFallbackRepository
            .fetchSalesTrend(filter: filter)
            .timeout(localFallbackTimeout),
      );
    }

    return _remoteFirstResult(
      label: 'management.salesTrend',
      scope: ReportDataOriginScope.sales,
      remote: () async {
        final report = await _remoteDatasource
            .fetchSalesByDay(filter: filter)
            .timeout(remoteTimeout);
        return report.series
            .map((point) {
              final bucketStart = _bucketStart(point.date, filter.grouping);
              return ReportSalesTrendPoint(
                bucketStart: bucketStart,
                bucketEndExclusive: _bucketEndExclusive(
                  bucketStart,
                  filter.grouping,
                ),
                label: _bucketLabel(bucketStart, filter.grouping),
                salesCount: point.salesCount,
                grossSalesCents: point.salesAmountCents,
                netSalesCents: point.salesAmountCents,
              );
            })
            .toList(growable: false);
      },
      fallback: () => _localFallbackRepository
          .fetchSalesTrend(filter: filter)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<ReportSummary> fetchSummary({
    required ReportPeriod period,
    ReportFilter? filter,
  }) async {
    final effectiveFilter = filter ?? ReportFilter.fromPeriod(period);
    final overview = await fetchOverview(filter: effectiveFilter);
    final products = await fetchTopProducts(
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
      soldProducts: products,
      variantSummaries: variants,
    );
  }

  @override
  Future<List<ReportSoldProductSummary>> fetchTopProducts({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    final result = await fetchTopProductsResult(filter: filter, limit: limit);
    return result.data;
  }

  Future<ReportResult<List<ReportSoldProductSummary>>> fetchTopProductsResult({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    if (filter.customerId != null ||
        filter.categoryId != null ||
        filter.productId != null ||
        filter.variantId != null ||
        filter.paymentMethod != null ||
        filter.includeCanceled ||
        filter.onlyCanceled) {
      return _localOnlyForMissingContractResult(
        label: 'management.topProducts.filtered',
        scope: ReportDataOriginScope.sales,
        fallback: () => _localFallbackRepository
            .fetchTopProducts(filter: filter, limit: limit)
            .timeout(localFallbackTimeout),
      );
    }

    return _remoteFirstResult(
      label: 'management.topProducts',
      scope: ReportDataOriginScope.sales,
      remote: () async {
        final report = await _remoteDatasource
            .fetchSalesByProduct(filter: filter, limit: limit)
            .timeout(remoteTimeout);
        return report.items
            .map(
              (item) => ReportSoldProductSummary(
                productId: null,
                productName: item.productName,
                quantityMil: item.quantityMil,
                unitMeasure: 'un',
                soldAmountCents: item.revenueCents,
                totalCostCents: item.costCents,
              ),
            )
            .toList(growable: false);
      },
      fallback: () => _localFallbackRepository
          .fetchTopProducts(filter: filter, limit: limit)
          .timeout(localFallbackTimeout),
    );
  }

  @override
  Future<List<ReportVariantSummary>> fetchTopVariants({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    final result = await fetchTopVariantsResult(filter: filter, limit: limit);
    return result.data;
  }

  Future<ReportResult<List<ReportVariantSummary>>> fetchTopVariantsResult({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    return _localOnlyForMissingContractResult(
      label: 'management.topVariants',
      scope: ReportDataOriginScope.sales,
      fallback: () => _localFallbackRepository
          .fetchTopVariants(filter: filter, limit: limit)
          .timeout(localFallbackTimeout),
    );
  }

  Future<ReportResult<T>> _remoteFirstResult<T>({
    required String label,
    required ReportDataOriginScope scope,
    required Future<T> Function() remote,
    required Future<T> Function() fallback,
  }) async {
    if (!_canUseRemoteAnalytics) {
      AppLogger.warn(
        'report.$label remote skipped; tenant analytics endpoint unavailable',
      );
      return ReportResult<T>(
        data: await fallback(),
        notice: ReportDataOriginNotice(
          scope: scope,
          title: 'Dados gerenciais parciais',
          message:
              'Relatorio gerencial usando dados locais/cache. Endpoint tenant indisponivel.',
        ),
      );
    }

    try {
      AppLogger.info('report.$label remote-first started');
      final result = await remote();
      AppLogger.info('report.$label remote-first finished');
      return ReportResult<T>(
        data: result,
        notice: ReportDataOriginNotice(
          scope: scope,
          title: 'Dados atualizados',
          message: 'Dados atualizados da nuvem.',
        ),
      );
    } catch (error, stackTrace) {
      final isForbiddenAdminEndpoint =
          error is NetworkRequestException && error.cause == 403;
      if (isForbiddenAdminEndpoint) {
        AppLogger.warn(
          'report.$label remote forbidden; using local cache fallback',
        );
      } else {
        AppLogger.error(
          'report.$label remote failed; using local cache fallback',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return ReportResult<T>(
        data: await fallback(),
        notice: ReportDataOriginNotice(
          scope: scope,
          title: isForbiddenAdminEndpoint
              ? 'Dados gerenciais parciais'
              : 'Dados locais/cache',
          message: isForbiddenAdminEndpoint
              ? 'Relatorio gerencial usando dados locais/cache. Endpoint tenant indisponivel.'
              : 'Servidor indisponivel, mostrando cache local.',
        ),
      );
    }
  }

  Future<ReportResult<T>> _localOnlyForMissingContractResult<T>({
    required String label,
    required ReportDataOriginScope scope,
    required Future<T> Function() fallback,
  }) async {
    AppLogger.info(
      'report.$label using local fallback; remote contract absent',
    );
    return ReportResult<T>(
      data: await fallback(),
      notice: ReportDataOriginNotice(
        scope: scope,
        title: 'Dados gerenciais parciais',
        message: 'Endpoint gerencial ausente; exibindo dados locais/cache.',
      ),
    );
  }

  ReportCashflowPoint _cashPointFromRemote(RemoteCashConsolidatedPoint point) {
    final bucketStart = DateTime(
      point.date.year,
      point.date.month,
      point.date.day,
    );
    return ReportCashflowPoint(
      bucketStart: bucketStart,
      bucketEndExclusive: bucketStart.add(const Duration(days: 1)),
      label: _bucketLabel(bucketStart, ReportGrouping.day),
      inflowCents: point.cashInflowCents,
      outflowCents: point.cashOutflowCents,
      netCents: point.cashNetCents,
    );
  }

  DateTime _bucketStart(DateTime date, ReportGrouping grouping) {
    switch (grouping) {
      case ReportGrouping.week:
        final base = DateTime(date.year, date.month, date.day);
        return base.subtract(Duration(days: base.weekday - DateTime.monday));
      case ReportGrouping.month:
        return DateTime(date.year, date.month);
      case ReportGrouping.day:
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return DateTime(date.year, date.month, date.day);
    }
  }

  DateTime _bucketEndExclusive(DateTime start, ReportGrouping grouping) {
    switch (grouping) {
      case ReportGrouping.week:
        return start.add(const Duration(days: 7));
      case ReportGrouping.month:
        return start.month == DateTime.december
            ? DateTime(start.year + 1)
            : DateTime(start.year, start.month + 1);
      case ReportGrouping.day:
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return start.add(const Duration(days: 1));
    }
  }

  String _bucketLabel(DateTime start, ReportGrouping grouping) {
    switch (grouping) {
      case ReportGrouping.week:
        return 'Sem ${_formatDate(start)}';
      case ReportGrouping.month:
        return '${start.month.toString().padLeft(2, '0')}/${start.year}';
      case ReportGrouping.day:
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return _formatDate(start);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}';
  }
}
