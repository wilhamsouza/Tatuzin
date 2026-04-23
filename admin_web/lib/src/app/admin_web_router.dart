import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/admin_debug_log.dart';
import '../core/auth/admin_providers.dart';
import '../core/widgets/admin_shell_scaffold.dart';
import '../features/audit/presentation/audit_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/companies/presentation/companies_page.dart';
import '../features/companies/presentation/company_detail_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/licenses/presentation/licenses_page.dart';
import '../features/management/crm/presentation/crm_customer_detail_page.dart';
import '../features/management/crm/presentation/crm_customers_page.dart';
import '../features/management/dashboard/presentation/management_dashboard_page.dart';
import '../features/management/governance/presentation/hybrid_governance_page.dart';
import '../features/management/reports/presentation/management_reports_page.dart';
import '../features/sync_health/presentation/sync_health_page.dart';

final adminRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.read(adminAuthControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authController,
    redirect: (context, state) {
      final path = state.uri.path;
      final isLoginRoute = path == '/login';

      if (authController.isRestoring) {
        final redirect = isLoginRoute ? null : '/login';
        adminDebugLog('router.redirect', {
          'path': path,
          'reason': 'restoring_session',
          'redirect': redirect,
        });
        return redirect;
      }

      if (!authController.isAuthenticated) {
        final redirect = isLoginRoute ? null : '/login';
        adminDebugLog('router.redirect', {
          'path': path,
          'reason': 'not_authenticated',
          'redirect': redirect,
        });
        return redirect;
      }

      if (!authController.isPlatformAdmin) {
        final redirect = isLoginRoute ? null : '/login';
        adminDebugLog('router.redirect', {
          'path': path,
          'reason': 'not_platform_admin',
          'redirect': redirect,
        });
        return redirect;
      }

      if (isLoginRoute) {
        adminDebugLog('router.redirect', {
          'path': path,
          'reason': 'authenticated_admin',
          'redirect': '/dashboard',
        });
        return '/dashboard';
      }

      adminDebugLog('router.redirect', {
        'path': path,
        'reason': 'allow_route',
        'redirect': null,
      });
      return null;
    },
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, __) => '/dashboard'),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) {
          return AdminShellScaffold(
            currentLocation: state.uri.path,
            title: _titleForLocation(state.uri.path),
            child: child,
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/management/dashboard',
            builder: (context, state) => const ManagementDashboardPage(),
          ),
          GoRoute(
            path: '/management/reports',
            builder: (context, state) => const ManagementReportsPage(),
          ),
          GoRoute(
            path: '/management/governance',
            builder: (context, state) => const HybridGovernancePage(),
          ),
          GoRoute(
            path: '/management/crm/customers',
            builder: (context, state) => CrmCustomersPage(
              initialCompanyId: state.uri.queryParameters['companyId'],
              initialSearch: state.uri.queryParameters['search'],
              initialTag: state.uri.queryParameters['tag'],
            ),
          ),
          GoRoute(
            path: '/management/crm/customers/:customerId',
            builder: (context, state) {
              final customerId = state.pathParameters['customerId'] ?? '';
              return CrmCustomerDetailPage(
                customerId: customerId,
                initialCompanyId: state.uri.queryParameters['companyId'],
              );
            },
          ),
          GoRoute(
            path: '/companies',
            builder: (context, state) => const CompaniesPage(),
          ),
          GoRoute(
            path: '/companies/:companyId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return CompanyDetailPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/licenses',
            builder: (context, state) => const LicensesPage(),
          ),
          GoRoute(
            path: '/sync-health',
            builder: (context, state) => const SyncHealthPage(),
          ),
          GoRoute(
            path: '/audit',
            builder: (context, state) => const AuditPage(),
          ),
        ],
      ),
    ],
  );
});

String _titleForLocation(String location) {
  if (location.startsWith('/companies/')) {
    return 'Detalhe da empresa';
  }
  if (location.startsWith('/management/dashboard')) {
    return 'Dashboard Gerencial';
  }
  if (location.startsWith('/management/reports')) {
    return 'Relatorios Gerenciais';
  }
  if (location.startsWith('/management/governance')) {
    return 'Governanca Hibrida';
  }
  if (location.startsWith('/management/crm/customers/')) {
    return 'Cliente CRM';
  }
  if (location.startsWith('/management/crm/customers')) {
    return 'CRM Gerencial';
  }
  if (location.startsWith('/companies')) {
    return 'Empresas';
  }
  if (location.startsWith('/licenses')) {
    return 'Licencas';
  }
  if (location.startsWith('/sync-health')) {
    return 'Saude da sync';
  }
  if (location.startsWith('/audit')) {
    return 'Auditoria';
  }
  return 'Dashboard da Plataforma';
}
