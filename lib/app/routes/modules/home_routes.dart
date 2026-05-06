import 'package:go_router/go_router.dart';

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
      path: AppRoutePaths.more,
      name: AppRouteNames.more,
      builder: (context, state) => const MorePage(),
    ),
  ];
}
