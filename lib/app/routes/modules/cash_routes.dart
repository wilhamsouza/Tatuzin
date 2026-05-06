import 'package:go_router/go_router.dart';

import '../../../modules/caixa/presentation/pages/cash_count_page.dart';
import '../../../modules/caixa/presentation/pages/cash_page.dart';
import '../route_names.dart';

List<RouteBase> buildCashRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.cash,
      name: AppRouteNames.cash,
      builder: (context, state) => const CashPage(),
    ),
    GoRoute(
      path: AppRoutePaths.cashCount,
      name: AppRouteNames.cashCount,
      builder: (context, state) => const CashCountPage(),
    ),
  ];
}
