import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/funcionarios/presentation/pages/employees_page.dart';
import '../route_names.dart';

List<RouteBase> buildEmployeesRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.employees,
      name: AppRouteNames.employees,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.employees,
        title: 'Funcionários',
        child: EmployeesPage(),
      ),
    ),
  ];
}
