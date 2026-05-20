import 'package:go_router/go_router.dart';

import '../../../modules/auth/presentation/pages/forgot_password_page.dart';
import '../../../modules/auth/presentation/pages/change_initial_password_page.dart';
import '../../../modules/auth/presentation/pages/login_page.dart';
import '../../../modules/auth/presentation/pages/register_page.dart';
import '../../../modules/auth/presentation/pages/reset_password_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildAuthRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.login,
      name: AppRouteNames.login,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: AppRoutePaths.register,
      name: AppRouteNames.register,
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: AppRoutePaths.forgotPassword,
      name: AppRouteNames.forgotPassword,
      builder: (context, state) => const ForgotPasswordPage(),
    ),
    GoRoute(
      path: AppRoutePaths.resetPassword,
      name: AppRouteNames.resetPassword,
      builder: (context, state) => ResetPasswordPage(
        initialToken: parseOptionalStringQueryParam(state, 'token'),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.changeInitialPassword,
      name: AppRouteNames.changeInitialPassword,
      builder: (context, state) => const ChangeInitialPasswordPage(),
    ),
  ];
}
