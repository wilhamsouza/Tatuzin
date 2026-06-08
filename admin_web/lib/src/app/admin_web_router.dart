import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/admin_debug_log.dart';
import '../core/auth/admin_providers.dart';
import '../core/widgets/admin_route_error_page.dart';
import '../core/widgets/admin_shell_scaffold.dart';
import '../features/audit/presentation/audit_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/billing/presentation/billing_admin_page.dart';
import '../features/billing/presentation/billing_company_detail_page.dart';
import '../features/companies/presentation/companies_page.dart';
import '../features/companies/presentation/company_detail_page.dart';
import '../features/companies/presentation/company_sessions_page.dart';
import '../features/companies/presentation/company_support_page.dart';
import '../features/companies/presentation/company_users_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/devices/presentation/devices_page.dart';
import '../features/licenses/presentation/licenses_page.dart';
import '../features/management/crm/presentation/crm_customer_detail_page.dart';
import '../features/management/crm/presentation/crm_customers_page.dart';
import '../features/management/dashboard/presentation/management_dashboard_page.dart';
import '../features/management/governance/presentation/hybrid_governance_page.dart';
import '../features/management/reports/presentation/management_reports_page.dart';
import '../features/permissions/presentation/admin_permissions_page.dart';
import '../features/plans/presentation/plans_page.dart';
import '../features/sync_center/presentation/sync_center_pages.dart';
import '../features/sync_health/presentation/sync_health_page.dart';
import '../features/tenant_deletion/presentation/tenant_deletion_page.dart';

final adminRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.read(adminAuthControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authController,
    errorBuilder: (context, state) => AdminShellScaffold(
      currentLocation: state.uri.path,
      title: 'Rota invalida',
      child: AdminRouteErrorPage(
        location: state.uri.toString(),
        message: state.error?.toString(),
      ),
    ),
    redirect: (context, state) {
      final path = state.uri.path;
      final isLoginRoute = path == '/login';

      if (authController.isRestoring) {
        adminDebugLog('router.redirect', {
          'path': path,
          'reason': 'restoring_session',
          'redirect': null,
        });
        return null;
      }

      if (!authController.isAuthenticated) {
        final redirect = isLoginRoute
            ? null
            : Uri(
                path: '/login',
                queryParameters: {'from': state.uri.toString()},
              ).toString();
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
        final from = _safeLoginRedirect(state.uri.queryParameters['from']);
        final redirect = from ?? '/dashboard';
        adminDebugLog('router.redirect', {
          'path': path,
          'reason': 'authenticated_admin',
          'redirect': redirect,
        });
        return redirect;
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
            path: '/companies',
            builder: (context, state) => const CompaniesPage(),
          ),
          GoRoute(
            path: '/companies/:companyId/sync',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return SyncCompanyPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId/license',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return LicenseCompanyPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId/support',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return CompanySupportPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId/users',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return CompanyUsersPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId/devices',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return DevicesPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId/sessions',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return CompanySessionsPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return CompanyDetailPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/companies/:companyId/employees',
            redirect: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return '/companies/$companyId/users';
            },
          ),
          GoRoute(
            path: '/sync',
            builder: (context, state) => const SyncCenterPage(),
          ),
          GoRoute(
            path: '/sync/:companyId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              // Alias operacional de /companies/:companyId/sync.
              // Mantido para deep links antigos do Sync Center.
              return SyncCompanyPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/sync/:companyId/events/:eventId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              final eventId = state.pathParameters['eventId'] ?? '';
              return SyncEventDetailPage(
                companyId: companyId,
                eventId: eventId,
              );
            },
          ),
          GoRoute(
            path: '/sync/:companyId/conflicts/:conflictId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              final conflictId = state.pathParameters['conflictId'] ?? '';
              return SyncConflictDetailPage(
                companyId: companyId,
                conflictId: conflictId,
              );
            },
          ),
          GoRoute(
            path: '/devices',
            builder: (context, state) => const DevicesPage(),
          ),
          GoRoute(
            path: '/licenses',
            builder: (context, state) => const LicensesPage(),
          ),
          GoRoute(
            path: '/licenses/:companyId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return LicenseCompanyPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/plans',
            builder: (context, state) => const PlansPage(),
          ),
          GoRoute(
            path: '/permissions',
            builder: (context, state) => AdminPermissionsPage(
              initialAdminUserId: state.uri.queryParameters['adminUserId'],
            ),
          ),
          GoRoute(
            path: '/tenant-deletion',
            builder: (context, state) => const TenantDeletionPage(),
          ),
          GoRoute(
            path: '/admin/permissions',
            redirect: (context, state) {
              final query = state.uri.hasQuery ? '?${state.uri.query}' : '';
              return '/permissions$query';
            },
          ),
          GoRoute(
            path: '/audit',
            builder: (context, state) =>
                AuditPage(initialQueryParameters: state.uri.queryParameters),
          ),

          // Rotas legadas mantidas para compatibilidade interna, fora do menu.
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
            path: '/billing',
            builder: (context, state) => const BillingAdminPage(),
          ),
          GoRoute(
            path: '/billing/:companyId',
            builder: (context, state) {
              final companyId = state.pathParameters['companyId'] ?? '';
              return BillingCompanyDetailPage(companyId: companyId);
            },
          ),
          GoRoute(
            path: '/sync-health',
            builder: (context, state) => const SyncHealthPage(),
          ),
        ],
      ),
    ],
  );
});

String _titleForLocation(String location) {
  if (location.startsWith('/companies/') && location.endsWith('/sync')) {
    return 'Sync Center';
  }
  if (location.startsWith('/companies/') && location.endsWith('/license')) {
    return 'Licenca e billing da empresa';
  }
  if (location.startsWith('/companies/') && location.endsWith('/support')) {
    return 'Central de suporte da empresa';
  }
  if (location.startsWith('/companies/') &&
      (location.endsWith('/users') || location.endsWith('/employees'))) {
    return 'Usuarios e funcionarios';
  }
  if (location.startsWith('/companies/') && location.endsWith('/devices')) {
    return 'Dispositivos e sessoes';
  }
  if (location.startsWith('/companies/') && location.endsWith('/sessions')) {
    return 'Sessoes da empresa';
  }
  if (location.startsWith('/licenses/')) {
    return 'Licenca e billing da empresa';
  }
  if (location.startsWith('/companies/')) {
    return 'Empresa';
  }
  if (location.startsWith('/companies')) {
    return 'Empresas';
  }
  if (location.startsWith('/sync-health')) {
    return 'Saude do sync';
  }
  if (location.startsWith('/sync')) {
    return 'Sync Center';
  }
  if (location.startsWith('/devices')) {
    return 'Dispositivos e sessoes';
  }
  if (location.startsWith('/licenses')) {
    return 'Licencas';
  }
  if (location.startsWith('/plans')) {
    return 'Planos';
  }
  if (location.startsWith('/permissions') ||
      location.startsWith('/admin/permissions')) {
    return 'Permissoes administrativas';
  }
  if (location.startsWith('/tenant-deletion')) {
    return 'Exclusao de tenant';
  }
  if (location.startsWith('/audit')) {
    return 'Auditoria';
  }
  if (location.startsWith('/management/dashboard')) {
    return 'Dashboard gerencial';
  }
  if (location.startsWith('/management/reports')) {
    return 'Relatorios gerenciais';
  }
  if (location.startsWith('/management/governance')) {
    return 'Governanca hibrida';
  }
  if (location.startsWith('/management/crm/customers/')) {
    return 'Cliente CRM';
  }
  if (location.startsWith('/management/crm/customers')) {
    return 'CRM gerencial';
  }
  if (location.startsWith('/billing')) {
    return 'Billing';
  }
  return 'Dashboard da plataforma';
}

String? _safeLoginRedirect(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.path.isEmpty ||
      uri.path == '/login') {
    return null;
  }
  return uri.toString();
}
