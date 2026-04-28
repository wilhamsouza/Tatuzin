import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_context_logger.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../data/cost_repository_impl.dart';
import '../../data/datasources/costs_remote_datasource.dart';
import '../../data/real/real_costs_remote_datasource.dart';
import '../../data/sqlite_cost_repository.dart';
import '../../domain/entities/cost_entry.dart';
import '../../domain/entities/cost_overview.dart';
import '../../domain/entities/cost_status.dart';
import '../../domain/entities/cost_type.dart';
import '../../domain/repositories/cost_repository.dart';

final localCostRepositoryProvider = Provider<SqliteCostRepository>((ref) {
  return SqliteCostRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
  );
});

final costsRemoteDatasourceProvider = Provider<CostsRemoteDatasource>((ref) {
  return RealCostsRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
  );
});

final costRepositoryProvider = Provider<CostRepository>((ref) {
  return CostRepositoryImpl(
    localRepository: ref.watch(localCostRepositoryProvider),
    remoteDatasource: ref.read(costsRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final costOverviewProvider = FutureProvider<CostOverview>((ref) async {
  await requireTenantBootstrapReady(ref, 'costOverviewProvider');
  ref.watch(appDataRefreshProvider);
  logProviderContext(ref, 'costOverviewProvider');
  return runProviderGuarded(
    'costOverviewProvider',
    () => ref.watch(costRepositoryProvider).fetchOverview(),
    timeout: localProviderTimeout,
  );
});

final costSearchQueryProvider = StateProvider.family<String, CostType>(
  (ref, type) => '',
);

final costStatusFilterProvider = StateProvider.family<CostStatus?, CostType>(
  (ref, type) => null,
);

final costDateFromFilterProvider = StateProvider.family<DateTime?, CostType>(
  (ref, type) => null,
);

final costDateToFilterProvider = StateProvider.family<DateTime?, CostType>(
  (ref, type) => null,
);

final costOverdueOnlyFilterProvider = StateProvider.family<bool, CostType>(
  (ref, type) => false,
);

final costsProvider = FutureProvider.family<List<CostEntry>, CostType>((
  ref,
  type,
) async {
  await requireTenantBootstrapReady(ref, 'costsProvider');
  ref.watch(appDataRefreshProvider);
  logProviderContext(ref, 'costsProvider');
  final query = ref.watch(costSearchQueryProvider(type));
  final status = ref.watch(costStatusFilterProvider(type));
  final from = ref.watch(costDateFromFilterProvider(type));
  final to = ref.watch(costDateToFilterProvider(type));
  final overdueOnly = ref.watch(costOverdueOnlyFilterProvider(type));
  return runProviderGuarded(
    'costsProvider',
    () => ref
        .watch(costRepositoryProvider)
        .searchCosts(
          type: type,
          query: query,
          status: status,
          from: from,
          to: to,
          overdueOnly: overdueOnly,
        ),
    timeout: localProviderTimeout,
  );
});

final costDetailProvider = FutureProvider.family<CostEntry, int>((
  ref,
  costId,
) async {
  await requireTenantBootstrapReady(ref, 'costDetailProvider');
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'costDetailProvider',
    () => ref.watch(costRepositoryProvider).fetchCost(costId),
    timeout: localProviderTimeout,
  );
});

final costActionControllerProvider =
    AsyncNotifierProvider<CostActionController, void>(CostActionController.new);

class CostActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<int> createCost(CreateCostInput input) async {
    state = const AsyncLoading();
    try {
      final id = await ref.read(costRepositoryProvider).createCost(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CostEntry> updateCost({
    required int costId,
    required UpdateCostInput input,
  }) async {
    state = const AsyncLoading();
    try {
      final cost = await ref
          .read(costRepositoryProvider)
          .updateCost(costId: costId, input: input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return cost;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CostEntry> markPaid(MarkCostPaidInput input) async {
    state = const AsyncLoading();
    try {
      final cost = await ref.read(costRepositoryProvider).markCostPaid(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return cost;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CostEntry> cancelCost({required int costId, String? notes}) async {
    state = const AsyncLoading();
    try {
      final cost = await ref
          .read(costRepositoryProvider)
          .cancelCost(costId: costId, notes: notes);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return cost;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
