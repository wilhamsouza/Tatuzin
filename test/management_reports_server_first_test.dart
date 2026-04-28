import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:erp_pdv_app/modules/relatorios/data/analytics_report_repository.dart';
import 'package:erp_pdv_app/modules/relatorios/data/datasources/analytics_reports_remote_datasource.dart';
import 'package:erp_pdv_app/modules/relatorios/data/support/report_filter_preset_support.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_cashflow_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_customer_ranking_row.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_data_origin_notice.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_data_source_strategy.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_inventory_health_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_overview_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_period.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_profitability_row.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_purchase_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sales_trend_point.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sold_product_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_variant_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/repositories/report_repository.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/providers/report_providers.dart';

void main() {
  group('relatorios gerenciais server-first', () {
    test('classifica relatorios gerenciais e operacional por estrategia', () {
      expect(
        reportStrategyForPage(ReportPageKey.sales),
        ReportDataSourceStrategy.erpManagementServerFirst,
      );
      expect(
        reportStrategyForPage(ReportPageKey.customers),
        ReportDataSourceStrategy.crmManagementServerFirst,
      );
      expect(
        reportStrategyForPage(ReportPageKey.cash),
        ReportDataSourceStrategy.pdvOperationalLocalFirst,
      );
    });

    test(
      'usa analytics remoto primeiro quando ha endpoint compativel',
      () async {
        final remote = _FakeAnalyticsRemoteDatasource();
        final local = _FakeReportRepository();
        final repository = AnalyticsReportRepository(
          remoteDatasource: remote,
          localFallbackRepository: local,
        );

        final points = await repository.fetchSalesTrend(filter: _filter());

        expect(remote.salesByDayCalls, 1);
        expect(local.salesTrendCalls, 0);
        expect(points.single.netSalesCents, 12000);
      },
    );

    test('usa fallback local somente quando analytics falha', () async {
      final remote = _FakeAnalyticsRemoteDatasource(shouldFail: true);
      final local = _FakeReportRepository();
      final repository = AnalyticsReportRepository(
        remoteDatasource: remote,
        localFallbackRepository: local,
      );

      final result = await repository.fetchTopProductsResult(filter: _filter());
      final products = result.data;

      expect(remote.salesByProductCalls, 1);
      expect(local.topProductsCalls, 1);
      expect(products.single.productName, 'Produto local');
      expect(result.notice!.scope, ReportDataOriginScope.sales);
      expect(result.notice!.message, contains('cache local'));
    });

    test('propaga erro quando API e cache falham', () async {
      final remote = _FakeAnalyticsRemoteDatasource(shouldFail: true);
      final local = _FakeReportRepository(shouldFail: true);
      final repository = AnalyticsReportRepository(
        remoteDatasource: remote,
        localFallbackRepository: local,
      );

      await expectLater(
        repository.fetchTopProducts(filter: _filter()),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'cashflowReportProvider operacional usa repositório PDV local',
      () async {
        final remote = _FakeAnalyticsRemoteDatasource();
        final local = _FakeReportRepository();
        final container = ProviderContainer(
          overrides: [
            pdvOperationalReportRepositoryProvider.overrideWithValue(local),
            reportRemoteDatasourceProvider.overrideWithValue(remote),
          ],
        );
        addTearDown(container.dispose);

        final cash = await container.read(cashflowReportProvider.future);

        expect(cash.totalReceivedCents, 7000);
        expect(remote.cashConsolidatedCalls, 0);
        expect(
          reportStrategyForPage(ReportPageKey.cash).label,
          contains('PDV'),
        );
      },
    );

    test(
      'usa fallback local para contrato remoto ausente de estoque',
      () async {
        final remote = _FakeAnalyticsRemoteDatasource();
        final local = _FakeReportRepository();
        final repository = AnalyticsReportRepository(
          remoteDatasource: remote,
          localFallbackRepository: local,
        );

        final result = await repository.fetchInventoryHealthResult(
          filter: _filter(),
        );
        final summary = result.data;

        expect(remote.salesByDayCalls, 0);
        expect(local.inventoryCalls, 1);
        expect(summary.totalItemsCount, 2);
        expect(result.notice!.scope, ReportDataOriginScope.inventory);
        expect(result.notice!.message, contains('Endpoint gerencial ausente'));
      },
    );

    test(
      'usuario comum nao chama endpoint admin e usa fallback sinalizado',
      () async {
        final remote = _FakeAnalyticsRemoteDatasource();
        final local = _FakeReportRepository();
        final container = ProviderContainer(
          overrides: [
            pdvOperationalReportRepositoryProvider.overrideWithValue(local),
            reportRemoteDatasourceProvider.overrideWithValue(remote),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(
          topProductsReportResultProvider.future,
        );
        final notice = result.notice;

        expect(remote.salesByProductCalls, 0);
        expect(local.topProductsCalls, 1);
        expect(notice, isNotNull);
        expect(notice!.message, contains('Endpoint tenant indisponivel'));
      },
    );

    test(
      'provider de variantes retorna notice sem modificar StateProvider no build',
      () async {
        final remote = _FakeAnalyticsRemoteDatasource();
        final local = _FakeReportRepository();
        final container = ProviderContainer(
          overrides: [
            pdvOperationalReportRepositoryProvider.overrideWithValue(local),
            reportRemoteDatasourceProvider.overrideWithValue(remote),
          ],
        );
        addTearDown(container.dispose);

        final variants = await container.read(topVariantsReportProvider.future);
        final notice = container.read(
          reportPageDataOriginNoticeProvider(ReportPageKey.sales),
        );

        expect(variants, isEmpty);
        expect(notice, isNotNull);
        expect(notice!.message, contains('Endpoint gerencial ausente'));
      },
    );
  });
}

ReportFilter _filter() {
  return ReportFilter.fromPeriod(
    ReportPeriod.monthly,
    reference: DateTime(2026, 4, 26),
  );
}

class _FakeAnalyticsRemoteDatasource
    implements AnalyticsReportsRemoteDatasource {
  _FakeAnalyticsRemoteDatasource({this.shouldFail = false});

  final bool shouldFail;
  int cashConsolidatedCalls = 0;
  int salesByDayCalls = 0;
  int salesByProductCalls = 0;

  @override
  Future<RemoteCashConsolidatedReport> fetchCashConsolidated({
    required ReportFilter filter,
  }) async {
    cashConsolidatedCalls++;
    if (shouldFail) {
      throw StateError('remote failed');
    }
    return RemoteCashConsolidatedReport(
      totalInflowCents: 15000,
      totalOutflowCents: 2000,
      totalNetCents: 13000,
      series: [
        RemoteCashConsolidatedPoint(
          date: filter.start,
          cashInflowCents: 15000,
          cashOutflowCents: 2000,
          cashNetCents: 13000,
        ),
      ],
    );
  }

  @override
  Future<RemoteFinancialSummaryReport> fetchFinancialSummary({
    required ReportFilter filter,
  }) async {
    if (shouldFail) {
      throw StateError('remote failed');
    }
    return const RemoteFinancialSummaryReport(
      salesAmountCents: 12000,
      salesCostCents: 5000,
      salesProfitCents: 7000,
      purchasesAmountCents: 3000,
      fiadoPaymentsAmountCents: 1000,
      cashNetCents: 11000,
      financialAdjustmentsCents: 0,
      operatingMarginBasisPoints: 5833,
    );
  }

  @override
  Future<RemoteSalesByCustomerReport> fetchSalesByCustomer({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    if (shouldFail) {
      throw StateError('remote failed');
    }
    return const RemoteSalesByCustomerReport(
      items: [
        RemoteSalesByCustomerItem(
          customerKey: 'customer-1',
          customerId: 'customer-1',
          customerName: 'Cliente remoto',
          salesCount: 2,
          revenueCents: 12000,
          costCents: 5000,
          profitCents: 7000,
          fiadoPaymentsCents: 1000,
        ),
      ],
    );
  }

  @override
  Future<RemoteSalesByDayReport> fetchSalesByDay({
    required ReportFilter filter,
  }) async {
    salesByDayCalls++;
    if (shouldFail) {
      throw StateError('remote failed');
    }
    return RemoteSalesByDayReport(
      series: [
        RemoteSalesByDayPoint(
          date: filter.start,
          salesCount: 2,
          salesAmountCents: 12000,
          salesCostCents: 5000,
          salesProfitCents: 7000,
        ),
      ],
    );
  }

  @override
  Future<RemoteSalesByProductReport> fetchSalesByProduct({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    salesByProductCalls++;
    if (shouldFail) {
      throw StateError('remote failed');
    }
    return const RemoteSalesByProductReport(
      items: [
        RemoteSalesByProductItem(
          productKey: 'product-1',
          productId: 'product-1',
          productName: 'Produto remoto',
          quantityMil: 1000,
          salesCount: 2,
          revenueCents: 12000,
          costCents: 5000,
          profitCents: 7000,
        ),
      ],
    );
  }
}

class _FakeReportRepository implements ReportRepository {
  _FakeReportRepository({this.shouldFail = false});

  final bool shouldFail;
  int salesTrendCalls = 0;
  int topProductsCalls = 0;
  int inventoryCalls = 0;

  void _throwIfNeeded() {
    if (shouldFail) {
      throw StateError('local failed');
    }
  }

  @override
  Future<ReportCashflowSummary> fetchCashflow({
    required ReportFilter filter,
  }) async {
    _throwIfNeeded();
    return ReportCashflowSummary(
      filter: filter,
      totalReceivedCents: 7000,
      fiadoReceiptsCents: 0,
      manualEntriesCents: 0,
      outflowsCents: 0,
      withdrawalsCents: 0,
      netFlowCents: 7000,
      movementRows: const [],
      timeline: const [],
    );
  }

  @override
  Future<List<ReportCustomerRankingRow>> fetchCustomerRanking({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    _throwIfNeeded();
    return const [];
  }

  @override
  Future<ReportInventoryHealthSummary> fetchInventoryHealth({
    required ReportFilter filter,
  }) async {
    inventoryCalls++;
    _throwIfNeeded();
    return ReportInventoryHealthSummary(
      filter: filter,
      totalItemsCount: 2,
      zeroedItemsCount: 0,
      belowMinimumItemsCount: 0,
      belowMinimumOnlyItemsCount: 0,
      divergenceItemsCount: 0,
      inventoryCostValueCents: 1000,
      inventorySaleValueCents: 2000,
      criticalItems: const [],
      mostMovedItems: const [],
      recentMovements: const [],
    );
  }

  @override
  Future<ReportOverviewSummary> fetchOverview({
    required ReportFilter filter,
  }) async {
    _throwIfNeeded();
    return ReportOverviewSummary(
      filter: filter,
      grossSalesCents: 7000,
      netSalesCents: 7000,
      totalReceivedCents: 7000,
      costOfGoodsSoldCents: 3000,
      realizedProfitCents: 4000,
      salesCount: 1,
      totalDiscountCents: 0,
      totalSurchargeCents: 0,
      pendingFiadoCents: 0,
      pendingFiadoCount: 0,
      cancelledSalesCount: 0,
      cancelledSalesCents: 0,
      totalPurchasedCents: 0,
      totalPurchasePaymentsCents: 0,
      totalPurchasePendingCents: 0,
      cashSalesReceivedCents: 7000,
      fiadoReceiptsCents: 0,
      totalCreditGeneratedCents: 0,
      totalCreditUsedCents: 0,
      totalOutstandingCreditCents: 0,
      topCreditCustomers: const [],
      paymentSummaries: const [],
    );
  }

  @override
  Future<List<ReportProfitabilityRow>> fetchProfitability({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    _throwIfNeeded();
    return const [];
  }

  @override
  Future<ReportPurchaseSummary> fetchPurchaseSummary({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    _throwIfNeeded();
    return ReportPurchaseSummary(
      filter: filter,
      purchasesCount: 0,
      totalPurchasedCents: 0,
      totalPendingCents: 0,
      totalPaidCents: 0,
      supplierRows: const [],
      topItems: const [],
      replenishmentRows: const [],
    );
  }

  @override
  Future<List<ReportSalesTrendPoint>> fetchSalesTrend({
    required ReportFilter filter,
  }) async {
    salesTrendCalls++;
    _throwIfNeeded();
    return [
      ReportSalesTrendPoint(
        bucketStart: filter.start,
        bucketEndExclusive: filter.start.add(const Duration(days: 1)),
        label: 'Local',
        salesCount: 1,
        grossSalesCents: 7000,
        netSalesCents: 7000,
      ),
    ];
  }

  @override
  Future<ReportSummary> fetchSummary({
    required ReportPeriod period,
    ReportFilter? filter,
  }) async {
    _throwIfNeeded();
    final effectiveFilter = filter ?? ReportFilter.fromPeriod(period);
    return ReportSummary(
      period: period,
      range: effectiveFilter.range,
      totalSalesCents: 0,
      totalReceivedCents: 0,
      costOfGoodsSoldCents: 0,
      realizedProfitCents: 0,
      salesCount: 0,
      pendingFiadoCents: 0,
      pendingFiadoCount: 0,
      cancelledSalesCount: 0,
      cancelledSalesCents: 0,
      totalPurchasedCents: 0,
      totalPurchasePaymentsCents: 0,
      totalPurchasePendingCents: 0,
      cashSalesReceivedCents: 0,
      fiadoReceiptsCents: 0,
      totalCreditGeneratedCents: 0,
      totalCreditUsedCents: 0,
      totalOutstandingCreditCents: 0,
      topCreditCustomers: const [],
      paymentSummaries: const [],
      soldProducts: const [],
      variantSummaries: const [],
    );
  }

  @override
  Future<List<ReportSoldProductSummary>> fetchTopProducts({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    topProductsCalls++;
    _throwIfNeeded();
    return const [
      ReportSoldProductSummary(
        productId: 1,
        productName: 'Produto local',
        quantityMil: 1000,
        unitMeasure: 'un',
        soldAmountCents: 7000,
        totalCostCents: 3000,
      ),
    ];
  }

  @override
  Future<List<ReportVariantSummary>> fetchTopVariants({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    _throwIfNeeded();
    return const [];
  }
}
