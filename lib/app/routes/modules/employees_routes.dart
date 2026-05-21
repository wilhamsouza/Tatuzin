import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/funcionarios/presentation/pages/employee_activity_page.dart';
import '../../../modules/funcionarios/presentation/pages/employee_commissions_page.dart';
import '../../../modules/funcionarios/presentation/pages/employees_page.dart';
import '../route_names.dart';

List<RouteBase> buildEmployeesRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.employeeCommissions,
      name: AppRouteNames.employeeCommissions,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.employees,
        title: 'Comissões',
        child: EmployeeCommissionsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.employeeCommissionDetail,
      name: AppRouteNames.employeeCommissionDetail,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.employees,
        title: 'Comissão do funcionário',
        child: EmployeeCommissionDetailPage(
          employeeId: state.pathParameters['employeeId'] ?? '',
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.employeeActivity,
      name: AppRouteNames.employeeActivity,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.employees,
        title: 'Atividade dos funcionarios',
        child: EmployeeActivityPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.employeeActivityDetail,
      name: AppRouteNames.employeeActivityDetail,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.employees,
        title: 'Atividade do funcionario',
        child: EmployeeActivityDetailPage(
          employeeId: state.pathParameters['employeeId'] ?? '',
        ),
      ),
    ),
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
