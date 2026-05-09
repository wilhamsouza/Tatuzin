import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/owner_providers.dart';
import '../core/widgets/owner_shell_scaffold.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/billing/presentation/owner_billing_page.dart';
import '../features/company/presentation/owner_company_page.dart';
import '../features/dashboard/presentation/owner_dashboard_page.dart';
import '../features/devices/presentation/owner_devices_page.dart';
import '../features/employees/presentation/owner_employees_page.dart';

const ownerRoutePaths = <String>[
  '/',
  '/login',
  '/dashboard',
  '/company',
  '/billing',
  '/employees',
  '/devices',
];

final ownerRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.read(ownerAuthControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authController,
    redirect: (context, state) {
      final path = state.uri.path;
      final isLoginRoute = path == '/login';

      if (authController.isRestoring) {
        return isLoginRoute ? null : '/login';
      }
      if (!authController.isAuthenticated) {
        return isLoginRoute ? null : '/login';
      }
      if (isLoginRoute) {
        return '/dashboard';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, __) => '/dashboard'),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) {
          return OwnerShellScaffold(
            currentLocation: state.uri.path,
            title: _titleForLocation(state.uri.path),
            child: child,
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const OwnerDashboardPage(),
          ),
          GoRoute(
            path: '/company',
            builder: (context, state) => const OwnerCompanyPage(),
          ),
          GoRoute(
            path: '/billing',
            builder: (context, state) => const OwnerBillingPage(),
          ),
          GoRoute(
            path: '/employees',
            builder: (context, state) => const OwnerEmployeesPage(),
          ),
          GoRoute(
            path: '/devices',
            builder: (context, state) => const OwnerDevicesPage(),
          ),
        ],
      ),
    ],
  );
});

String _titleForLocation(String location) {
  if (location.startsWith('/company')) {
    return 'Empresa';
  }
  if (location.startsWith('/billing')) {
    return 'Assinatura e cobranças';
  }
  if (location.startsWith('/employees')) {
    return 'Funcionários';
  }
  if (location.startsWith('/devices')) {
    return 'Dispositivos';
  }
  return 'Dashboard';
}
