import 'package:go_router/go_router.dart';

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
      builder: (context, state) => const ReportsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.salesReports,
      name: AppRouteNames.salesReports,
      builder: (context, state) => const SalesReportsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.cashReports,
      name: AppRouteNames.cashReports,
      builder: (context, state) => const CashReportsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryReports,
      name: AppRouteNames.inventoryReports,
      builder: (context, state) => const InventoryReportsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.customerReports,
      name: AppRouteNames.customerReports,
      builder: (context, state) => const CustomerReportsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.purchaseReports,
      name: AppRouteNames.purchaseReports,
      builder: (context, state) => const PurchaseReportsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.profitabilityReports,
      name: AppRouteNames.profitabilityReports,
      builder: (context, state) => const ProfitabilityReportsPage(),
    ),
  ];
}
