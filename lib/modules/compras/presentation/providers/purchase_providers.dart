import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/sync_action_result.dart';
import '../../data/datasources/purchases_remote_datasource.dart';
import '../../data/purchases_repository_impl.dart';
import '../../data/real/real_purchases_remote_datasource.dart';
import '../../data/sqlite_purchase_repository.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_detail.dart';
import '../../domain/entities/purchase_status.dart';
import '../../domain/repositories/purchase_repository.dart';

final localPurchaseRepositoryProvider = Provider<SqlitePurchaseRepository>((
  ref,
) {
  return SqlitePurchaseRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
  );
});

final purchasesRemoteDatasourceProvider = Provider<PurchasesRemoteDatasource>((
  ref,
) {
  return RealPurchasesRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final purchaseHybridRepositoryProvider = Provider<PurchasesRepositoryImpl>((
  ref,
) {
  return PurchasesRepositoryImpl(
    localRepository: ref.read(localPurchaseRepositoryProvider),
    remoteDatasource: ref.read(purchasesRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return ref.watch(purchaseHybridRepositoryProvider);
});

final purchaseSearchQueryProvider = StateProvider<String>((ref) => '');
final purchaseStatusFilterProvider = StateProvider<PurchaseStatus?>(
  (ref) => null,
);
final purchaseSupplierFilterProvider = StateProvider<int?>((ref) => null);

final purchaseListProvider = FutureProvider<List<Purchase>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(purchaseSearchQueryProvider);
  final status = ref.watch(purchaseStatusFilterProvider);
  final supplierId = ref.watch(purchaseSupplierFilterProvider);
  return ref
      .watch(purchaseRepositoryProvider)
      .search(query: query, status: status, supplierId: supplierId);
});

final purchaseDetailProvider = FutureProvider.family<PurchaseDetail, int>((
  ref,
  purchaseId,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(purchaseRepositoryProvider).fetchDetail(purchaseId);
});

final purchasesBySupplierProvider = FutureProvider.family<List<Purchase>, int>((
  ref,
  supplierId,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(purchaseRepositoryProvider).search(supplierId: supplierId);
});

final purchaseSyncControllerProvider =
    AsyncNotifierProvider<PurchaseSyncController, void>(
      PurchaseSyncController.new,
    );

class PurchaseSyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<SyncActionResult> syncNow() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(purchaseHybridRepositoryProvider).syncNow();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
