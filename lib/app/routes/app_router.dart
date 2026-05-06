import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/database/app_database.dart';
import '../core/session/auth_provider.dart';
import '../core/session/session_provider.dart';
import 'modules/account_routes.dart';
import 'modules/admin_routes.dart';
import 'modules/auth_routes.dart';
import 'modules/cash_routes.dart';
import 'modules/customers_routes.dart';
import 'modules/home_routes.dart';
import 'modules/inventory_routes.dart';
import 'modules/orders_routes.dart';
import 'modules/pdv_routes.dart';
import 'modules/products_routes.dart';
import 'modules/purchases_routes.dart';
import 'modules/reports_routes.dart';
import 'modules/sales_routes.dart';
import 'modules/system_routes.dart';
import 'route_guards.dart';
import 'route_names.dart';
import 'route_param_parsers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(appSessionProvider);
  final startupState = ref.watch(appStartupProvider).valueOrNull;

  AuthStatusSnapshot readAuthStatus() => ref.read(authStatusProvider);

  return GoRouter(
    initialLocation: AppRoutePaths.login,
    redirect: (context, state) => appRouteRedirect(
      session: session,
      startupState: startupState,
      state: state,
    ),
    routes: <RouteBase>[
      ...buildAuthRoutes(),
      ...buildHomeRoutes(),
      ...buildAccountRoutes(),
      ...buildProductsRoutes(),
      ...buildInventoryRoutes(),
      ...buildCustomersRoutes(),
      ...buildPurchasesRoutes(),
      ...buildPdvRoutes(),
      ...buildOrdersRoutes(),
      ...buildSalesRoutes(),
      ...buildCashRoutes(),
      ...buildReportsRoutes(),
      ...buildSystemRoutes(readAuthStatus: readAuthStatus),
      ...buildAdminRoutes(readAuthStatus: readAuthStatus),
    ],
    errorBuilder: (context, state) {
      return invalidRoutePage(
        title: 'Rota indisponivel',
        message:
            state.error?.toString() ??
            'Nao foi possivel encontrar a tela solicitada.',
      );
    },
  );
});
