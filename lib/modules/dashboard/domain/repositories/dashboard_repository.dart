import '../entities/dashboard_metrics.dart';

abstract interface class DashboardRepository {
  Future<DashboardMetrics> fetchMetrics();
}
