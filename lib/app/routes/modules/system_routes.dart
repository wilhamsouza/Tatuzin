import 'package:go_router/go_router.dart';

import '../../../modules/system/presentation/pages/system_page.dart';
import '../../core/session/auth_provider.dart';
import '../route_guards.dart';
import '../route_names.dart';

List<RouteBase> buildSystemRoutes({
  required AuthStatusSnapshot Function() readAuthStatus,
}) {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.system,
      name: AppRouteNames.system,
      redirect: (context, state) => AppRoutePaths.accountCloud,
    ),
    GoRoute(
      path: AppRoutePaths.technicalSystem,
      name: AppRouteNames.technicalSystem,
      redirect: (context, state) {
        final authStatus = readAuthStatus();
        return redirectToAccountUnless(canOpenTechnicalRoute(authStatus));
      },
      builder: (context, state) => const SystemPage(),
    ),
  ];
}
