import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';

import '../core/database/app_database.dart';
import '../core/session/app_session.dart';
import '../core/session/auth_provider.dart';
import 'route_names.dart';

String? appRouteRedirect({
  required AppSession session,
  required AppStartupState? startupState,
  required GoRouterState state,
}) {
  final path = state.uri.path;

  if (isPublicRoutePath(path)) {
    if (path == AppRoutePaths.login &&
        session.hasOperationalIdentity &&
        startupState?.isSuccess == true) {
      return AppRoutePaths.dashboard;
    }
    return null;
  }

  if (!session.hasOperationalIdentity) {
    return AppRoutePaths.login;
  }

  return null;
}

bool isPublicRoutePath(String path) {
  return path == AppRoutePaths.login ||
      path == AppRoutePaths.register ||
      path == AppRoutePaths.forgotPassword ||
      path == AppRoutePaths.resetPassword;
}

bool canOpenTechnicalRoute(AuthStatusSnapshot authStatus) {
  return kDebugMode ||
      authStatus.isPlatformAdmin ||
      authStatus.isSupportProfile;
}

bool canOpenAdminRoute(AuthStatusSnapshot authStatus) {
  return authStatus.isRemoteAuthenticated && canOpenTechnicalRoute(authStatus);
}

String? redirectToAccountUnless(bool allowed) {
  return allowed ? null : AppRoutePaths.accountCloud;
}
