import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../../modules/dashboard/presentation/pages/dashboard_page.dart';
import '../../../modules/more/presentation/pages/more_page.dart';
import '../route_names.dart';

List<RouteBase> buildHomeRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.dashboard,
      name: AppRouteNames.dashboard,
      builder: (context, state) => const DashboardPage(),
    ),
    GoRoute(
      path: AppRoutePaths.permissionDenied,
      name: AppRouteNames.permissionDenied,
      builder: (context, state) => const PermissionDeniedPage(),
    ),
    GoRoute(
      path: AppRoutePaths.more,
      name: AppRouteNames.more,
      builder: (context, state) => const MorePage(),
    ),
  ];
}
