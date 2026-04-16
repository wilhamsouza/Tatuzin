import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/sync/sync_action_result.dart';
import '../../data/datasources/supplies_remote_datasource.dart';
import '../../data/real/real_supplies_remote_datasource.dart';
import '../../data/sqlite_supply_repository.dart';
import '../../data/supplies_repository_impl.dart';
import '../../domain/entities/supply.dart';
import '../../domain/entities/supply_cost_history_entry.dart';
import '../../domain/entities/supply_inventory.dart';
import '../../domain/repositories/supply_repository.dart';

final localSupplyRepositoryProvider = Provider<SqliteSupplyRepository>((ref) {
  return SqliteSupplyRepository(ref.read(appDatabaseProvider));
});

final suppliesRemoteDatasourceProvider = Provider<SuppliesRemoteDatasource>((
  ref,
) {
  return RealSuppliesRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final supplyHybridRepositoryProvider = Provider<SuppliesRepositoryImpl>((ref) {
  return SuppliesRepositoryImpl(
    localRepository: ref.read(localSupplyRepositoryProvider),
    remoteDatasource: ref.read(suppliesRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final supplyRepositoryProvider = Provider<SupplyRepository>((ref) {
  return ref.watch(supplyHybridRepositoryProvider);
});

final supplySearchQueryProvider = StateProvider<String>((ref) => '');

final supplyListProvider = FutureProvider<List<Supply>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(supplySearchQueryProvider);
  return ref.watch(supplyRepositoryProvider).search(query: query);
});

final activeSupplyOptionsProvider = FutureProvider<List<Supply>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(supplyRepositoryProvider).search(activeOnly: true);
});

final supplyDetailProvider = FutureProvider.family<Supply?, int>((
  ref,
  supplyId,
) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(supplyRepositoryProvider).findById(supplyId);
});

final supplyInventoryOverviewProvider =
    FutureProvider<List<SupplyInventoryOverview>>((ref) async {
      ref.watch(appDataRefreshProvider);
      final query = ref.watch(supplySearchQueryProvider);
      return ref
          .watch(supplyRepositoryProvider)
          .listInventoryOverview(query: query);
    });

final reorderSuggestionsSearchQueryProvider = StateProvider<String>(
  (ref) => '',
);

final reorderSuggestionsFilterProvider = StateProvider<SupplyReorderFilter>(
  (ref) => SupplyReorderFilter.all,
);

final supplyReorderSuggestionsProvider =
    FutureProvider<List<SupplyReorderSuggestion>>((ref) async {
      ref.watch(appDataRefreshProvider);
      final query = ref.watch(reorderSuggestionsSearchQueryProvider);
      final filter = ref.watch(reorderSuggestionsFilterProvider);
      return ref
          .watch(supplyRepositoryProvider)
          .listReorderSuggestions(query: query, filter: filter);
    });

final supplyInventoryMovementsProvider =
    FutureProvider.family<
      List<SupplyInventoryMovement>,
      SupplyInventoryMovementQuery
    >((ref, query) async {
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(supplyRepositoryProvider)
          .listInventoryMovements(
            supplyId: query.supplyId,
            sourceType: query.sourceType,
            occurredFrom: query.occurredFrom,
            occurredTo: query.occurredTo,
            limit: query.limit,
          );
    });

final supplyCostHistoryProvider =
    FutureProvider.family<List<SupplyCostHistoryEntry>, int>((
      ref,
      supplyId,
    ) async {
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(supplyRepositoryProvider)
          .listCostHistory(supplyId: supplyId);
    });

final supplyActionControllerProvider =
    AsyncNotifierProvider<SupplyActionController, void>(
      SupplyActionController.new,
    );

class SupplyActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<int> createSupply(SupplyInput input) async {
    state = const AsyncLoading();
    try {
      final id = await ref.read(supplyRepositoryProvider).create(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> updateSupply({
    required int supplyId,
    required SupplyInput input,
  }) async {
    state = const AsyncLoading();
    try {
      await ref.read(supplyRepositoryProvider).update(supplyId, input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> deactivateSupply(int supplyId) async {
    state = const AsyncLoading();
    try {
      await ref.read(supplyRepositoryProvider).deactivate(supplyId);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class SupplyInventoryMovementQuery {
  const SupplyInventoryMovementQuery({
    this.supplyId,
    this.sourceType,
    this.occurredFrom,
    this.occurredTo,
    this.limit = 200,
  });

  final int? supplyId;
  final SupplyInventorySourceType? sourceType;
  final DateTime? occurredFrom;
  final DateTime? occurredTo;
  final int limit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SupplyInventoryMovementQuery &&
        other.supplyId == supplyId &&
        other.sourceType == sourceType &&
        other.occurredFrom == occurredFrom &&
        other.occurredTo == occurredTo &&
        other.limit == limit;
  }

  @override
  int get hashCode =>
      Object.hash(supplyId, sourceType, occurredFrom, occurredTo, limit);
}

final supplySyncControllerProvider =
    AsyncNotifierProvider<SupplySyncController, void>(SupplySyncController.new);

class SupplySyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<SyncActionResult> syncNow() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(supplyHybridRepositoryProvider).syncNow();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
