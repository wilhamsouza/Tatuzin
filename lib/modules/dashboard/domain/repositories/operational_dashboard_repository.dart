import '../entities/operational_dashboard_snapshot.dart';

abstract interface class OperationalDashboardRepository {
  Future<OperationalDashboardSnapshot> fetchSnapshot();
}
