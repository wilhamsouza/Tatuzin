import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/widgets/product_stock_surface.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/estoque/presentation/pages/inventory_count_session_detail_page.dart';
import '../../../modules/estoque/presentation/pages/stock_workspace_page.dart';
import '../../../modules/estoque/presentation/pages/central_count_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildInventoryRoutes() {
  return <RouteBase>[
    GoRoute(
      path: '/estoque/contagens/:countId',
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: ProductStockSurface(
          child: CentralCountPage(countId: state.pathParameters['countId']),
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventory,
      name: AppRouteNames.inventory,
      builder: (context, state) => ProductStockSurface(
        child: StockWorkspacePage(
          productId: state.uri.queryParameters['productId'],
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryCounts,
      name: AppRouteNames.inventoryCounts,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: ProductStockSurface(child: StockWorkspacePage(initialTab: 2)),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryCountSessionDetail,
      name: AppRouteNames.inventoryCountSessionDetail,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: buildIntParamRoute(
          state,
          'sessionId',
          (sessionId) => ProductStockSurface(
            child: InventoryCountSessionDetailPage(sessionId: sessionId),
          ),
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryMovements,
      name: AppRouteNames.inventoryMovements,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: ProductStockSurface(
          child: StockWorkspacePage(
            initialTab: 1,
            productId: state.uri.queryParameters['productId'],
          ),
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryAdjustment,
      name: AppRouteNames.inventoryAdjustment,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: ProductStockSurface(child: StockWorkspacePage()),
      ),
    ),
  ];
}
