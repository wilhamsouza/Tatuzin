import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/relatorios/presentation/pages/cash_reports_page.dart';
import '../../../modules/relatorios/presentation/pages/customer_reports_page.dart';
import '../../../modules/relatorios/presentation/pages/inventory_reports_page.dart';
import '../../../modules/relatorios/presentation/pages/profitability_reports_page.dart';
import '../../../modules/relatorios/presentation/pages/purchase_reports_page.dart';
import '../../../modules/relatorios/presentation/pages/reports_page.dart';
import '../../../modules/relatorios/presentation/pages/sales_reports_page.dart';
import '../route_names.dart';

List<RouteBase> buildReportsRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.reports,
      name: AppRouteNames.reports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsDaily,
        child: ReportsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.salesReports,
      name: AppRouteNames.salesReports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsBasic,
        child: SalesReportsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.cashReports,
      name: AppRouteNames.cashReports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsBasic,
        child: CashReportsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryReports,
      name: AppRouteNames.inventoryReports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsAdvanced,
        child: InventoryReportsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.customerReports,
      name: AppRouteNames.customerReports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsAdvanced,
        child: CustomerReportsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.purchaseReports,
      name: AppRouteNames.purchaseReports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsAdvanced,
        child: PurchaseReportsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.profitabilityReports,
      name: AppRouteNames.profitabilityReports,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsAdvanced,
        child: ProfitabilityReportsPage(),
      ),
    ),
  ];
}
