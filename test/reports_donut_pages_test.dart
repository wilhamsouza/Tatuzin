import 'dart:async';

import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/widgets/app_status_badge.dart';
import 'package:erp_pdv_app/app/routes/app_router.dart';
import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_breakdown_row.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_cashflow_point.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_cashflow_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_customer_ranking_row.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_inventory_health_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_overview_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_payment_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_profitability_row.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_purchase_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sales_trend_point.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sold_product_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_variant_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/cash_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/customer_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/inventory_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/purchase_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/profitability_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/sales_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/providers/report_providers.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/widgets/report_donut_chart_card.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final filter = ReportFilter(
    start: DateTime(2026, 4, 1),
    endExclusive: DateTime(2026, 5, 1),
  );

  testWidgets('ReportsPage renders executive donuts', (tester) async {
    await _pumpPage(
      tester,
      const ReportsPage(),
      overrides: [
        reportOverviewProvider.overrideWith((ref) async => _overview(filter)),
        reportPreviousOverviewProvider.overrideWith(
          (ref) async => _overview(filter, netSalesCents: 90000),
        ),
        topProductsReportProvider.overrideWith(
          (ref) async => const <ReportSoldProductSummary>[],
        ),
        inventoryHealthReportProvider.overrideWith(
          (ref) async => _inventorySummary(filter),
        ),
      ],
    );

    expect(find.text('Recebimentos por forma'), findsOneWidget);
    expect(find.text('Saude do estoque'), findsOneWidget);
    expect(find.text('Exportar'), findsNothing);
  });

  testWidgets('SalesReportsPage renders the payment donut', (tester) async {
    await _pumpPage(
      tester,
      const SalesReportsPage(),
      overrides: [
        reportOverviewProvider.overrideWith((ref) async => _overview(filter)),
        salesTrendProvider.overrideWith((ref) async => _salesTrend()),
        topProductsReportProvider.overrideWith(
          (ref) async => const <ReportSoldProductSummary>[],
        ),
        topVariantsReportProvider.overrideWith(
          (ref) async => const <ReportVariantSummary>[],
        ),
      ],
    );

    expect(find.byType(ReportDonutChartCard), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
  });

  testWidgets('CashReportsPage renders the entry origin donut', (tester) async {
    await _pumpPage(
      tester,
      const CashReportsPage(),
      overrides: [
        cashflowReportProvider.overrideWith((ref) async => _cashflow(filter)),
      ],
    );

    expect(find.text('Entradas por origem'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
  });

  testWidgets('InventoryReportsPage renders the stock health donut', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      const InventoryReportsPage(),
      overrides: [
        inventoryHealthReportProvider.overrideWith(
          (ref) async => _inventorySummary(filter),
        ),
      ],
    );

    expect(find.text('Saude do estoque'), findsNWidgets(2));
    expect(find.text('Exportar'), findsOneWidget);
  });

  testWidgets('ProfitabilityReportsPage renders the category donut', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      const ProfitabilityReportsPage(),
      overrides: [
        profitabilityReportProvider.overrideWith(
          (ref) async => _profitabilityRows(),
        ),
        profitabilityCategoryReportProvider.overrideWith(
          (ref) async => _profitabilityCategoryRows(),
        ),
      ],
    );

    expect(find.text('Lucro por categoria'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
  });

  testWidgets('CustomerReportsPage renders export controls', (tester) async {
    await _pumpPage(
      tester,
      const CustomerReportsPage(),
      overrides: [
        customerRankingReportProvider.overrideWith(
          (ref) async => _customerRows(),
        ),
      ],
    );

    expect(find.text('Clientes do periodo'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
  });

  testWidgets('PurchaseReportsPage renders export controls', (tester) async {
    await _pumpPage(
      tester,
      const PurchaseReportsPage(),
      overrides: [
        purchaseSummaryReportProvider.overrideWith(
          (ref) async => _purchaseSummary(filter),
        ),
      ],
    );

    expect(find.text('Compras do periodo'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => page)],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_TestAuthController.new),
        authStatusProvider.overrideWith((ref) => _authStatus()),
        accountCloudStatusProvider.overrideWith((ref) => _cloudStatus()),
        internalMobileSurfaceAccessProvider.overrideWith(
          (ref) => const InternalMobileSurfaceAccess(
            canOpenTechnicalSystem: false,
            canOpenAdminCloud: false,
          ),
        ),
        appRouterProvider.overrideWith((ref) => router),
        ...overrides,
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();
}

AuthStatusSnapshot _authStatus() {
  return const AuthStatusSnapshot(
    isAuthenticated: false,
    isMockAuthenticated: false,
    isRemoteAuthenticated: false,
    isPlatformAdmin: false,
    sessionLabel: 'Modo local',
    userLabel: 'Operador local',
    companyLabel: 'Tatuzin',
    email: null,
    canAttemptRemoteLogin: false,
    endpointLabel: 'Uso local',
    licensePlanLabel: 'Local',
    licenseStatusLabel: 'Ativa',
    licenseExpiresAt: null,
    cloudSyncEnabled: false,
    cloudSyncLabel: 'Uso local',
  );
}

AccountCloudStatusSnapshot _cloudStatus() {
  return const AccountCloudStatusSnapshot(
    statusLabel: 'Modo local',
    statusMessage: 'Uso local ativo.',
    tone: AppStatusTone.neutral,
    icon: Icons.offline_bolt_rounded,
    accountModeLabel: 'Modo local',
    cloudAvailabilityLabel: 'Uso local disponivel',
    syncingNowCount: 0,
    pendingCount: 0,
    errorCount: 0,
    blockedCount: 0,
    conflictCount: 0,
    lastSyncedAt: null,
    nextRetryAt: null,
  );
}

ReportOverviewSummary _overview(
  ReportFilter filter, {
  int netSalesCents = 120000,
}) {
  return ReportOverviewSummary(
    filter: filter,
    grossSalesCents: 130000,
    netSalesCents: netSalesCents,
    totalReceivedCents: 110000,
    costOfGoodsSoldCents: 60000,
    realizedProfitCents: 50000,
    salesCount: 12,
    totalDiscountCents: 5000,
    totalSurchargeCents: 2000,
    pendingFiadoCents: 18000,
    pendingFiadoCount: 3,
    cancelledSalesCount: 1,
    cancelledSalesCents: 4000,
    totalPurchasedCents: 45000,
    totalPurchasePaymentsCents: 30000,
    totalPurchasePendingCents: 15000,
    cashSalesReceivedCents: 70000,
    fiadoReceiptsCents: 15000,
    totalCreditGeneratedCents: 0,
    totalCreditUsedCents: 0,
    totalOutstandingCreditCents: 0,
    topCreditCustomers: const [],
    paymentSummaries: const [
      ReportPaymentSummary(
        paymentMethod: PaymentMethod.pix,
        receivedCents: 60000,
        operationsCount: 8,
      ),
      ReportPaymentSummary(
        paymentMethod: PaymentMethod.card,
        receivedCents: 35000,
        operationsCount: 4,
      ),
      ReportPaymentSummary(
        paymentMethod: PaymentMethod.cash,
        receivedCents: 15000,
        operationsCount: 2,
      ),
    ],
  );
}

ReportCashflowSummary _cashflow(ReportFilter filter) {
  return ReportCashflowSummary(
    filter: filter,
    totalReceivedCents: 90000,
    fiadoReceiptsCents: 20000,
    manualEntriesCents: 10000,
    outflowsCents: 25000,
    withdrawalsCents: 5000,
    netFlowCents: 75000,
    movementRows: const [
      ReportBreakdownRow(label: 'Vendas', amountCents: 70000, count: 8),
      ReportBreakdownRow(
        label: 'Recebimento de fiado',
        amountCents: 20000,
        count: 3,
      ),
      ReportBreakdownRow(label: 'Suprimentos', amountCents: 10000, count: 1),
    ],
    timeline: [
      ReportCashflowPoint(
        bucketStart: DateTime(2026, 4, 1),
        bucketEndExclusive: DateTime(2026, 4, 2),
        label: '01/04',
        inflowCents: 30000,
        outflowCents: 5000,
        netCents: 25000,
      ),
    ],
  );
}

ReportInventoryHealthSummary _inventorySummary(ReportFilter filter) {
  return ReportInventoryHealthSummary(
    filter: filter,
    totalItemsCount: 10,
    zeroedItemsCount: 2,
    belowMinimumItemsCount: 4,
    belowMinimumOnlyItemsCount: 2,
    divergenceItemsCount: 1,
    inventoryCostValueCents: 80000,
    inventorySaleValueCents: 120000,
    criticalItems: [
      InventoryItem(
        productId: 1,
        productVariantId: null,
        productName: 'Cafe Especial',
        sku: 'CAF-1',
        variantColorLabel: null,
        variantSizeLabel: null,
        unitMeasure: 'un',
        currentStockMil: 0,
        minimumStockMil: 1000,
        reorderPointMil: null,
        allowNegativeStock: false,
        costCents: 1000,
        salePriceCents: 1500,
        isActive: true,
        updatedAt: DateTime(2026, 4, 1),
      ),
    ],
    mostMovedItems: const [
      ReportBreakdownRow(label: 'Cafe Especial', quantityMil: 3000),
    ],
    recentMovements: const [],
  );
}

List<ReportSalesTrendPoint> _salesTrend() {
  return [
    ReportSalesTrendPoint(
      bucketStart: DateTime(2026, 4, 1),
      bucketEndExclusive: DateTime(2026, 4, 2),
      label: '01/04',
      salesCount: 5,
      grossSalesCents: 40000,
      netSalesCents: 38000,
    ),
  ];
}

List<ReportProfitabilityRow> _profitabilityRows() {
  return const [
    ReportProfitabilityRow(
      grouping: ReportGrouping.product,
      label: 'Cafe Especial',
      description: 'un',
      quantityMil: 3000,
      revenueCents: 45000,
      costCents: 20000,
      profitCents: 25000,
      marginBasisPoints: 5556,
      productId: 1,
      variantId: null,
      categoryId: 10,
    ),
  ];
}

List<ReportProfitabilityRow> _profitabilityCategoryRows() {
  return const [
    ReportProfitabilityRow(
      grouping: ReportGrouping.category,
      label: 'Bebidas',
      description: null,
      quantityMil: 3000,
      revenueCents: 45000,
      costCents: 20000,
      profitCents: 25000,
      marginBasisPoints: 5556,
      productId: null,
      variantId: null,
      categoryId: 10,
    ),
    ReportProfitabilityRow(
      grouping: ReportGrouping.category,
      label: 'Doces',
      description: null,
      quantityMil: 2000,
      revenueCents: 30000,
      costCents: 18000,
      profitCents: 12000,
      marginBasisPoints: 4000,
      productId: null,
      variantId: null,
      categoryId: 11,
    ),
  ];
}

List<ReportCustomerRankingRow> _customerRows() {
  return [
    ReportCustomerRankingRow(
      customerId: 1,
      customerName: 'Alice',
      isActive: true,
      salesCount: 3,
      totalPurchasedCents: 25000,
      pendingFiadoCents: 5000,
      creditBalanceCents: 0,
      lastPurchaseAt: DateTime(2026, 4, 5),
    ),
  ];
}

ReportPurchaseSummary _purchaseSummary(ReportFilter filter) {
  return ReportPurchaseSummary(
    filter: filter,
    purchasesCount: 4,
    totalPurchasedCents: 50000,
    totalPendingCents: 15000,
    totalPaidCents: 35000,
    supplierRows: const [
      ReportBreakdownRow(label: 'Fornecedor A', amountCents: 30000, count: 2),
    ],
    topItems: const [
      ReportBreakdownRow(
        label: 'Cafe Especial',
        amountCents: 15000,
        quantityMil: 3000,
      ),
    ],
    replenishmentRows: const [
      ReportBreakdownRow(
        label: 'Cafe Especial - Preta / P',
        amountCents: 12000,
        quantityMil: 2000,
      ),
    ],
  );
}

class _TestAuthController extends AuthController {
  @override
  FutureOr<void> build() async {}
}
