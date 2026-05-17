import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/estoque/presentation/pages/inventory_adjustment_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_count_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_count_session_detail_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_movements_page.dart';
import '../../../modules/produtos/presentation/pages/products_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildInventoryRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.inventory,
      name: AppRouteNames.inventory,
      builder: (context, state) =>
          const ProductsPage(initialTab: ProductHubTab.inventory),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryCounts,
      name: AppRouteNames.inventoryCounts,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: InventoryCountPage(),
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
          (sessionId) => InventoryCountSessionDetailPage(sessionId: sessionId),
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryMovements,
      name: AppRouteNames.inventoryMovements,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: InventoryMovementsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryAdjustment,
      name: AppRouteNames.inventoryAdjustment,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.inventoryAdvanced,
        child: InventoryAdjustmentPage(),
      ),
    ),
  ];
}
