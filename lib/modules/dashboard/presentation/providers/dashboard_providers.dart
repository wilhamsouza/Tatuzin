import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../data/sqlite_dashboard_repository.dart';
import '../../domain/entities/dashboard_metrics.dart';
import '../../domain/repositories/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return SqliteDashboardRepository(ref.read(appDatabaseProvider));
});

final dashboardMetricsProvider = FutureProvider<DashboardMetrics>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(dashboardRepositoryProvider).fetchMetrics();
});
