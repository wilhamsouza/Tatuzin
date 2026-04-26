import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/sync_action_result.dart';
import '../../data/datasources/suppliers_remote_datasource.dart';
import '../../data/real/real_suppliers_remote_datasource.dart';
import '../../data/sqlite_supplier_repository.dart';
import '../../data/suppliers_repository_impl.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';

final localSupplierRepositoryProvider = Provider<SqliteSupplierRepository>((
  ref,
) {
  return SqliteSupplierRepository(ref.watch(appDatabaseProvider));
});

final suppliersRemoteDatasourceProvider = Provider<SuppliersRemoteDatasource>((
  ref,
) {
  return RealSuppliersRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final supplierHybridRepositoryProvider = Provider<SuppliersRepositoryImpl>((
  ref,
) {
  return SuppliersRepositoryImpl(
    localRepository: ref.read(localSupplierRepositoryProvider),
    remoteDatasource: ref.read(suppliersRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  return ref.watch(supplierHybridRepositoryProvider);
});

final supplierSearchQueryProvider = StateProvider<String>((ref) => '');

final supplierListProvider = FutureProvider<List<Supplier>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(supplierSearchQueryProvider);
  return runProviderGuarded(
    'supplierListProvider',
    () => ref.watch(supplierRepositoryProvider).search(query: query),
    timeout: localProviderTimeout,
  );
});

final supplierOptionsProvider = FutureProvider<List<Supplier>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'supplierOptionsProvider',
    () => ref.watch(supplierRepositoryProvider).search(),
    timeout: localProviderTimeout,
  );
});

final supplierLookupProvider = FutureProvider.family<List<Supplier>, String>((
  ref,
  query,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'supplierLookupProvider',
    () => ref.watch(supplierRepositoryProvider).search(query: query),
    timeout: localProviderTimeout,
  );
});

final supplierDetailProvider = FutureProvider.family<Supplier?, int>((
  ref,
  supplierId,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'supplierDetailProvider',
    () => ref.watch(supplierRepositoryProvider).findById(supplierId),
    timeout: localProviderTimeout,
  );
});

final supplierSyncControllerProvider =
    AsyncNotifierProvider<SupplierSyncController, void>(
      SupplierSyncController.new,
    );

class SupplierSyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<SyncActionResult> syncNow() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(supplierHybridRepositoryProvider).syncNow();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
