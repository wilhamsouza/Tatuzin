import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/owner_providers.dart';
import '../core/auth/owner_return_location.dart';
import '../core/models/owner_models.dart';
import '../core/widgets/owner_shell_scaffold.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/billing/presentation/owner_billing_page.dart';
import '../features/clients/presentation/owner_clients_page.dart';
import '../features/company/presentation/owner_company_page.dart';
import '../features/dashboard/presentation/owner_dashboard_page.dart';
import '../features/devices/presentation/owner_devices_page.dart';
import '../features/employees/presentation/owner_employees_page.dart';
import '../features/finance/presentation/owner_finance_page.dart';
import '../features/legal/presentation/data_deletion_page.dart';
import '../features/legal/presentation/privacy_policy_page.dart';
import '../features/products/presentation/owner_products_page.dart';
import '../features/products/presentation/owner_catalog_page.dart';
import '../features/inventory/presentation/owner_inventory_page.dart';
import '../features/inventory/presentation/owner_inventory_count_page.dart';
import '../features/reports/presentation/owner_cash_report_page.dart';
import '../features/reports/presentation/owner_reports_page.dart';
import '../features/sales/presentation/owner_sales_page.dart';
import '../features/settings/presentation/owner_settings_page.dart';

const ownerRoutePaths = <String>[
  '/',
  '/login',
  '/privacidade',
  '/exclusao-de-dados',
  '/dashboard',
  '/sales',
  '/clients',
  '/finance',
  '/products',
  '/products/analysis',
  '/inventory',
  '/reports',
  '/reports/cash',
  '/company',
  '/billing',
  '/employees',
  '/devices',
  '/settings',
];

const publicOwnerRoutePaths = <String>{
  '/login',
  '/privacidade',
  '/exclusao-de-dados',
};

bool isPublicOwnerRoute(String path) => publicOwnerRoutePaths.contains(path);

String? ownerRouteRedirect({
  required String path,
  required bool isRestoring,
  required bool isAuthenticated,
}) {
  final isLoginRoute = path == '/login';
  final isPublicRoute = isPublicOwnerRoute(path);

  if (isRestoring) return null;
  if (!isAuthenticated) {
    return isPublicRoute ? null : '/login';
  }
  if (isLoginRoute) {
    return '/dashboard';
  }
  return null;
}

final ownerRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.read(ownerAuthControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authController,
    redirect: (context, state) {
      if (!authController.isRestoring &&
          !authController.isAuthenticated &&
          !isPublicOwnerRoute(state.uri.path)) {
        return Uri(
          path: '/login',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (!authController.isRestoring &&
          authController.isAuthenticated &&
          state.uri.path == '/login') {
        final target = ownerReturnLocation(state.uri.queryParameters['from']);
        if (target != null) return target;
      }
      return ownerRouteRedirect(
        path: state.uri.path,
        isRestoring: authController.isRestoring,
        isAuthenticated: authController.isAuthenticated,
      );
    },
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, __) => '/dashboard'),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/privacidade',
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/exclusao-de-dados',
        builder: (context, state) => const DataDeletionPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          if (authController.isRestoring || authController.session == null) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      semanticsLabel: 'Restaurando acesso',
                    ),
                    SizedBox(height: 16),
                    Text('Restaurando acesso…'),
                  ],
                ),
              ),
            );
          }
          final session = authController.session;
          final license = session?.company.license;
          if (session != null && license?.isPro != true) {
            return OwnerPlanBlockedPage(license: license);
          }
          return OwnerShellScaffold(
            currentLocation: state.uri.path,
            title: _titleForLocation(state.uri.path),
            child: child,
          );
        },
        routes: <RouteBase>[
          _ownerPageRoute(
            path: '/dashboard',
            builder: (context, state) => const OwnerDashboardPage(),
          ),
          _ownerPageRoute(
            path: '/sales',
            builder: (context, state) => const OwnerSalesPage(),
          ),
          _ownerPageRoute(
            path: '/clients',
            builder: (context, state) => const OwnerClientsPage(),
          ),
          _ownerPageRoute(
            path: '/finance',
            builder: (context, state) => const OwnerFinancePage(),
          ),
          _ownerPageRoute(
            path: '/products',
            builder: (context, state) => const OwnerCatalogPage(),
          ),
          _ownerPageRoute(
            path: '/products/analysis',
            builder: (context, state) => const OwnerProductsPage(),
          ),
          _ownerPageRoute(
            path: '/products/:productId',
            builder: (context, state) => OwnerProductDetailPage(
              productId: state.pathParameters['productId']!,
            ),
          ),
          _ownerPageRoute(
            path: '/inventory',
            builder: (context, state) => const OwnerInventoryPage(),
          ),
          _ownerPageRoute(
            path: '/inventory/items/:productId',
            builder: (context, state) => OwnerInventoryItemPage(
              productId: state.pathParameters['productId']!,
              variantId: state.uri.queryParameters['productVariantId'],
            ),
          ),
          _ownerPageRoute(
            path: '/inventory/counts/:sessionId',
            builder: (context, state) => OwnerInventoryCountPage(
              sessionId: state.pathParameters['sessionId']!,
            ),
          ),
          _ownerPageRoute(
            path: '/reports',
            builder: (context, state) => const OwnerReportsPage(),
          ),
          _ownerPageRoute(
            path: '/reports/cash',
            builder: (context, state) =>
                OwnerCashReportPage(query: state.uri.queryParameters),
          ),
          _ownerPageRoute(
            path: '/company',
            builder: (context, state) => const OwnerCompanyPage(),
          ),
          _ownerPageRoute(
            path: '/billing',
            builder: (context, state) => const OwnerBillingPage(),
          ),
          _ownerPageRoute(
            path: '/employees',
            builder: (context, state) => const OwnerEmployeesPage(),
          ),
          _ownerPageRoute(
            path: '/devices',
            builder: (context, state) => const OwnerDevicesPage(),
          ),
          _ownerPageRoute(
            path: '/settings',
            builder: (context, state) => const OwnerSettingsPage(),
          ),
        ],
      ),
    ],
  );
});

// Scroll belongs to the route page, inside the ShellRoute navigator. Wrapping
// the navigator itself makes long pages overflow its bounded viewport.
GoRoute _ownerPageRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
}) => GoRoute(
  path: path,
  builder: (context, state) => SingleChildScrollView(
    key: PageStorageKey('owner-page-${state.uri.path}'),
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 1100 ? 16 : 24),
    child: builder(context, state),
  ),
);

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
    return location.startsWith('/products/analysis')
        ? 'Análise de produtos'
        : 'Produtos';
  }
  if (location.startsWith('/inventory')) {
    return 'Estoque';
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

class OwnerPlanBlockedPage extends StatelessWidget {
  const OwnerPlanBlockedPage({super.key, required this.license});

  final OwnerLicenseSnapshot? license;

  @override
  Widget build(BuildContext context) {
    final waiting = license?.isWaitingForProConfirmation == true;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      waiting
                          ? Icons.hourglass_top_rounded
                          : Icons.workspace_premium_rounded,
                      color: colorScheme.primary,
                      size: 42,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      waiting
                          ? 'Aguardando confirmacao do Mercado Pago'
                          : 'Painel do dono disponivel no plano PRO',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      waiting
                          ? 'Assim que a assinatura for confirmada, o painel web sera liberado automaticamente.'
                          : 'Ative o PRO pelo app Tatuzin para acessar gestao da equipe, relatorios avancados, comissoes, multi-dispositivo e painel web.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
