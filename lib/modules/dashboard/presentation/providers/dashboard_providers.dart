import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../data/sqlite_operational_dashboard_repository.dart';
import '../../domain/entities/managerial_dashboard_readiness.dart';
import '../../domain/entities/operational_dashboard_snapshot.dart';
import '../../domain/repositories/operational_dashboard_repository.dart';

final operationalDashboardRepositoryProvider =
    Provider<OperationalDashboardRepository>((ref) {
      return SqliteOperationalDashboardRepository(
        ref.watch(appDatabaseProvider),
      );
    });

final operationalDashboardSnapshotProvider =
    FutureProvider<OperationalDashboardSnapshot>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
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
