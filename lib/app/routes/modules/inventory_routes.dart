import 'package:go_router/go_router.dart';

import '../../../modules/estoque/presentation/pages/inventory_adjustment_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_count_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_count_session_detail_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_movements_page.dart';
import '../../../modules/estoque/presentation/pages/inventory_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildInventoryRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.inventory,
      name: AppRouteNames.inventory,
      builder: (context, state) => const InventoryPage(),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryCounts,
      name: AppRouteNames.inventoryCounts,
      builder: (context, state) => const InventoryCountPage(),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryCountSessionDetail,
      name: AppRouteNames.inventoryCountSessionDetail,
      builder: (context, state) => buildIntParamRoute(
        state,
        'sessionId',
        (sessionId) => InventoryCountSessionDetailPage(sessionId: sessionId),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryMovements,
      name: AppRouteNames.inventoryMovements,
      builder: (context, state) => const InventoryMovementsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.inventoryAdjustment,
      name: AppRouteNames.inventoryAdjustment,
      builder: (context, state) => const InventoryAdjustmentPage(),
    ),
  ];
}
