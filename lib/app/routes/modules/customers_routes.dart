import 'package:go_router/go_router.dart';

import '../../../modules/clientes/domain/entities/client.dart';
import '../../../modules/clientes/presentation/pages/client_credit_statement_page.dart';
import '../../../modules/clientes/presentation/pages/client_form_page.dart';
import '../../../modules/clientes/presentation/pages/clients_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildCustomersRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.clients,
      name: AppRouteNames.clients,
      builder: (context, state) => const ClientsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.clientForm,
      name: AppRouteNames.clientForm,
      builder: (context, state) =>
          ClientFormPage(initialClient: routeExtraAs<Client>(state)),
    ),
    GoRoute(
      path: AppRoutePaths.clientCreditStatement,
      name: AppRouteNames.clientCreditStatement,
      builder: (context, state) => buildIntParamRoute(
        state,
        'clientId',
        (clientId) => ClientCreditStatementPage(
          clientId: clientId,
          initialClient: routeExtraAs<Client>(state),
        ),
      ),
    ),
  ];
}
