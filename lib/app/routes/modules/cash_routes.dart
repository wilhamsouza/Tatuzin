import '../../../modules/caixa/presentation/widgets/cash_workspace_theme.dart';
import '../../../modules/caixa/domain/entities/cash_session.dart';
import '../../../modules/caixa/presentation/pages/cash_closing_page.dart';
import '../../../modules/caixa/presentation/pages/cash_opening_page.dart';
import 'package:go_router/go_router.dart';

import '../../../modules/caixa/presentation/pages/cash_count_page.dart';
import '../../../modules/caixa/presentation/pages/cash_page.dart';
import '../route_names.dart';

List<RouteBase> buildCashRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.cashClose,
      name: AppRouteNames.cashClose,
      redirect: (_, state) =>
          state.extra is CashSession ? null : AppRoutePaths.cash,
      builder: (_, state) => CashWorkspaceTheme(
        child: CashClosingPage(session: state.extra! as CashSession),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.cashOpen,
      name: AppRouteNames.cashOpen,
      builder: (_, state) => CashWorkspaceTheme(
        child: CashOpeningPage(
          autoOpenedSession: state.extra is CashSession
              ? state.extra! as CashSession
              : null,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.cash,
      name: AppRouteNames.cash,
      builder: (context, state) => const CashWorkspaceTheme(child: CashPage()),
    ),
    GoRoute(
      path: AppRoutePaths.cashCount,
      name: AppRouteNames.cashCount,
      builder: (context, state) =>
          const CashWorkspaceTheme(child: CashCountPage()),
    ),
  ];
}
