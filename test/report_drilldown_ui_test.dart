import 'dart:async';

import 'package:erp_pdv_app/app/core/session/auth_provider.dart';
import 'package:erp_pdv_app/app/core/widgets/app_status_badge.dart';
import 'package:erp_pdv_app/app/routes/app_router.dart';
import 'package:erp_pdv_app/app/routes/route_names.dart';
import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:erp_pdv_app/modules/clientes/domain/entities/client.dart';
import 'package:erp_pdv_app/modules/categorias/domain/entities/category.dart';
import 'package:erp_pdv_app/modules/fornecedores/domain/entities/supplier.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/relatorios/data/support/report_filter_preset_support.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_inventory_health_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_overview_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_payment_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sales_trend_point.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sold_product_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_variant_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/pages/sales_reports_page.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/providers/report_providers.dart';
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

  testWidgets('hub KPI opens sales page with drill-down context', (
    tester,
  ) async {
    _prepareSurface(tester);
    final router = GoRouter(
      routes: [
        GoRoute(
          name: AppRouteNames.reports,
          path: '/',
          builder: (context, state) => const ReportsPage(),
        ),
        GoRoute(
          name: AppRouteNames.salesReports,
          path: '/sales',
          builder: (context, state) => const SalesReportsPage(),
        ),
      ],
    );
    final container = _buildContainer(
      extraOverrides: [
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
        salesTrendProvider.overrideWith((ref) async => _salesTrend()),
        topVariantsReportProvider.overrideWith(
          (ref) async => const <ReportVariantSummary>[],
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRouterFlow(
      tester,
      container: container,
      router: router,
    );

    await tester.tap(find.text('Vendas liquidas').first);
    await tester.pumpAndSettle();

    expect(find.text('Relatorio de vendas'), findsOneWidget);
    expect(find.text('Drill-down ativo'), findsOneWidget);
    expect(
      container
          .read(reportPageSessionProvider)
          .drilldownFor(ReportPageKey.sales)
          ?.sourceLabel,
      'KPI Vendas liquidas',
    );
  });

  testWidgets('sales drill-down can be cleared back to the previous view', (
    tester,
  ) async {
    _prepareSurface(tester);
    final container = _buildContainer(
      labels: const ReportFilterOptionLabels(products: {1: 'Cafe Especial'}),
      initialFilter: filter,
      extraOverrides: [
        reportOverviewProvider.overrideWith((ref) async => _overview(filter)),
        salesTrendProvider.overrideWith((ref) async => _salesTrend()),
        topProductsReportProvider.overrideWith(
          (ref) async => const [
            ReportSoldProductSummary(
              productId: 1,
              productName: 'Cafe Especial',
              quantityMil: 3000,
              unitMeasure: 'un',
              soldAmountCents: 45000,
              totalCostCents: 20000,
            ),
          ],
        ),
        topVariantsReportProvider.overrideWith(
          (ref) async => const <ReportVariantSummary>[],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SalesReportsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cafe Especial').first);
    await tester.pumpAndSettle();

    expect(container.read(reportFilterProvider).productId, 1);
    expect(find.text('Drill-down ativo'), findsOneWidget);

    await tester.tap(find.text('Voltar ao recorte anterior'));
    await tester.pumpAndSettle();

    expect(container.read(reportFilterProvider).productId, isNull);
    expect(find.text('Drill-down ativo'), findsNothing);
  });
}

void _prepareSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ProviderContainer _buildContainer({
  ReportFilterOptionLabels labels = const ReportFilterOptionLabels(),
  ReportFilter? initialFilter,
  List<Override> extraOverrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      reportClientOptionsProvider.overrideWith((ref) async => const <Client>[]),
      reportCategoryOptionsProvider.overrideWith(
        (ref) async => const <Category>[],
      ),
      reportProductOptionsProvider.overrideWith(
        (ref) async => const <Product>[],
      ),
      reportVariantOptionsProvider.overrideWith(
        (ref) async => const <ReportVariantFilterOption>[],
      ),
      reportSupplierOptionsProvider.overrideWith(
        (ref) async => const <Supplier>[],
      ),
      reportFilterOptionLabelsProvider.overrideWith((ref) async => labels),
      ...extraOverrides,
    ],
  );

  if (initialFilter != null) {
    container.read(reportFilterProvider.notifier).replace(initialFilter);
  }
  return container;
}

Future<void> _pumpRouterFlow(
  WidgetTester tester, {
  required ProviderContainer container,
  required GoRouter router,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
    criticalItems: const [],
    mostMovedItems: const [],
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

class _TestAuthController extends AuthController {
  @override
  FutureOr<void> build() async {}
}
