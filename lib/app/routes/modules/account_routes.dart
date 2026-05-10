import 'package:go_router/go_router.dart';

import '../../../modules/account/presentation/pages/account_cloud_page.dart';
import '../../../modules/account/presentation/pages/company_page.dart';
import '../../../modules/account/presentation/pages/settings_page.dart';
import '../../../modules/backup/presentation/pages/backup_restore_page.dart';
import '../../../modules/billing/presentation/pages/subscription_page.dart';
import '../route_names.dart';

List<RouteBase> buildAccountRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.accountCloud,
      name: AppRouteNames.accountCloud,
      builder: (context, state) => const AccountCloudPage(),
    ),
    GoRoute(
      path: AppRoutePaths.company,
      name: AppRouteNames.company,
      builder: (context, state) => const CompanyPage(),
    ),
    GoRoute(
      path: AppRoutePaths.settings,
      name: AppRouteNames.settings,
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.subscription,
      name: AppRouteNames.subscription,
      builder: (context, state) => const SubscriptionPage(),
    ),
    GoRoute(
      path: AppRoutePaths.backup,
      name: AppRouteNames.backup,
      builder: (context, state) => const BackupRestorePage(),
    ),
  ];
}
