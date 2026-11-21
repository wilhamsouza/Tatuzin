import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../relatorios/domain/entities/report_filter.dart';
import '../../../relatorios/domain/entities/report_overview_summary.dart';
import '../../../relatorios/domain/entities/report_sales_trend_point.dart';
import '../../../relatorios/presentation/providers/report_providers.dart';
import '../../data/sqlite_operational_dashboard_repository.dart';
import '../../domain/entities/managerial_dashboard_readiness.dart';
import '../../domain/entities/operational_dashboard_snapshot.dart';
import '../../domain/repositories/operational_dashboard_repository.dart';

final dashboardDayProvider = Provider<DateTime>((ref) {
  ref.watch(appDataRefreshProvider);
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

// Independent filters: opening the home must not reset a report in another tab.
// Reuse the report repository's realized-profit rules, including fiado payments
// and its explicit unavailable state when product costs are unknown.
final dashboardDailyOverviewProvider =
    FutureProvider.autoDispose<ReportOverviewSummary?>((ref) async {
      ref.watch(appDataRefreshProvider);
      final day = ref.watch(dashboardDayProvider);
      final session = ref.watch(appSessionProvider);
      if (!session.canAccessPermission('reports.advanced')) return null;
      await requireTenantBootstrapReady(ref, 'dashboardDailyOverviewProvider');
      return runProviderGuarded(
        'dashboardDailyOverviewProvider',
        () => ref
            .read(pdvOperationalReportRepositoryProvider)
            .fetchOverview(
              filter: ReportFilter(
                start: day,
                endExclusive: DateTime(day.year, day.month, day.day + 1),
              ),
            ),
        timeout: localProviderTimeout,
      );
    });

final dashboardSalesTrendProvider =
    FutureProvider.autoDispose<List<ReportSalesTrendPoint>>((ref) async {
      ref.watch(appDataRefreshProvider);
      final day = ref.watch(dashboardDayProvider);
      final session = ref.watch(appSessionProvider);
      if (!session.canAccessPermission('reports.advanced')) return const [];
      await requireTenantBootstrapReady(ref, 'dashboardSalesTrendProvider');
      final points = await runProviderGuarded(
        'dashboardSalesTrendProvider',
        () => ref
            .read(pdvOperationalReportRepositoryProvider)
            .fetchSalesTrend(
              filter: ReportFilter(
                start: DateTime(day.year, day.month, day.day - 6),
                endExclusive: DateTime(day.year, day.month, day.day + 1),
              ),
            ),
        timeout: localProviderTimeout,
      );
      // A missing bucket in a successful local query means no registered sales.
      // Include those days with zero so spacing always represents one day.
      return List.generate(7, (index) {
        final date = DateTime(day.year, day.month, day.day - 6 + index);
        for (final point in points) {
          if (point.bucketStart == date) return point;
        }
        return ReportSalesTrendPoint(
          bucketStart: date,
          bucketEndExclusive: DateTime(date.year, date.month, date.day + 1),
          label:
              '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}',
          salesCount: 0,
          grossSalesCents: 0,
          netSalesCents: 0,
        );
      });
    });

final operationalDashboardRepositoryProvider =
    Provider<OperationalDashboardRepository>((ref) {
      return SqliteOperationalDashboardRepository(
        ref.watch(appDatabaseProvider),
      );
    });

final operationalDashboardSnapshotProvider =
    FutureProvider<OperationalDashboardSnapshot>((ref) async {
      ref.watch(dashboardDayProvider);
      await requireTenantBootstrapReady(
        ref,
        'operationalDashboardSnapshotProvider',
      );
      ref.watch(appDataRefreshProvider);
      return runProviderGuarded(
        'operationalDashboardSnapshotProvider',
        () => ref.watch(operationalDashboardRepositoryProvider).fetchSnapshot(),
        timeout: localProviderTimeout,
      );
    });

final managerialDashboardReadinessProvider = Provider<ManagerialDashboardReadiness>((
  ref,
) {
  return const ManagerialDashboardReadiness(
    title: 'Dashboard gerencial cloud-first',
    message:
        'Lucro consolidado, comparativos multiusuario e leituras oficiais da empresa ficaram reservados para uma camada gerencial futura, desacoplada da home operacional local.',
    sourceLabel: 'Leitura futura via cloud',
    plannedIndicators: [
      ManagerialDashboardPlannedIndicator(
        title: 'Lucro consolidado da empresa',
        reason:
            'Depende de consolidacao remota multiusuario e nao deve sair da base local operacional como numero oficial.',
      ),
      ManagerialDashboardPlannedIndicator(
        title: 'Receita e margem por periodo consolidado',
        reason:
            'Precisa separar o acompanhamento gerencial do fechamento operacional do dispositivo atual.',
      ),
      ManagerialDashboardPlannedIndicator(
        title: 'Comparativos por operador, unidade ou janela historica',
        reason:
            'Pertence a uma leitura gerencial cloud-first, nao a consultas locais da home do caixa.',
      ),
    ],
  );
});
