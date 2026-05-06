import 'package:go_router/go_router.dart';

import '../../../modules/admin/presentation/pages/admin_page.dart';
import '../../core/session/auth_provider.dart';
import '../route_guards.dart';
import '../route_names.dart';

List<RouteBase> buildAdminRoutes({
  required AuthStatusSnapshot Function() readAuthStatus,
}) {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.legacyAdmin,
      redirect: (context, state) => AppRoutePaths.accountCloud,
    ),
    GoRoute(
      path: AppRoutePaths.admin,
      name: AppRouteNames.admin,
      redirect: (context, state) {
        final authStatus = readAuthStatus();
        return redirectToAccountUnless(canOpenAdminRoute(authStatus));
      },
      builder: (context, state) => const AdminPage(),
    ),
  ];
}
