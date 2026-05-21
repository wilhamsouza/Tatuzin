import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/owner_providers.dart';
import '../core/widgets/owner_shell_scaffold.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/billing/presentation/owner_billing_page.dart';
import '../features/clients/presentation/owner_clients_page.dart';
import '../features/company/presentation/owner_company_page.dart';
import '../features/dashboard/presentation/owner_dashboard_page.dart';
import '../features/devices/presentation/owner_devices_page.dart';
import '../features/employees/presentation/owner_employees_page.dart';
import '../features/finance/presentation/owner_finance_page.dart';
import '../features/products/presentation/owner_products_page.dart';
import '../features/reports/presentation/owner_reports_page.dart';
import '../features/sales/presentation/owner_sales_page.dart';
import '../features/settings/presentation/owner_settings_page.dart';

const ownerRoutePaths = <String>[
  '/',
  '/login',
  '/dashboard',
  '/sales',
  '/clients',
  '/finance',
  '/products',
  '/reports',
  '/company',
  '/billing',
  '/employees',
  '/devices',
  '/settings',
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
            path: '/sales',
            builder: (context, state) => const OwnerSalesPage(),
          ),
          GoRoute(
            path: '/clients',
            builder: (context, state) => const OwnerClientsPage(),
          ),
          GoRoute(
            path: '/finance',
            builder: (context, state) => const OwnerFinancePage(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const OwnerProductsPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const OwnerReportsPage(),
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
          GoRoute(
            path: '/settings',
            builder: (context, state) => const OwnerSettingsPage(),
          ),
        ],
      ),
    ],
  );
});

String _titleForLocation(String location) {
  if (location.startsWith('/sales')) {
    return 'Vendas';
  }
  if (location.startsWith('/clients')) {
    return 'Clientes / CRM';
  }
  if (location.startsWith('/finance')) {
    return 'Fiado e financeiro';
  }
  if (location.startsWith('/products')) {
    return 'Produtos e estoque';
  }
  if (location.startsWith('/reports')) {
    return 'Relatórios';
  }
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
    return 'Nuvem e sincronizacao';
  }
  if (location.startsWith('/settings')) {
    return 'Configurações';
  }
  return 'Dashboard';
}
