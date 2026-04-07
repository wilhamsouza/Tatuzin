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
import '../../data/categories_repository_impl.dart';
import '../../data/datasources/categories_remote_datasource.dart';
import '../../data/real/real_categories_remote_datasource.dart';
import '../../data/sqlite_category_repository.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';

final localCategoryRepositoryProvider = Provider<SqliteCategoryRepository>((
  ref,
) {
  return SqliteCategoryRepository(ref.read(appDatabaseProvider));
});

final categoriesRemoteDatasourceProvider = Provider<CategoriesRemoteDatasource>(
  (ref) {
    return RealCategoriesRemoteDatasource(
      apiClient: ref.read(realApiClientProvider),
      tokenStorage: ref.read(authTokenStorageProvider),
      environment: ref.watch(appEnvironmentProvider),
      operationalContext: ref.watch(appOperationalContextProvider),
    );
  },
);

final categoryHybridRepositoryProvider = Provider<CategoriesRepositoryImpl>((
  ref,
) {
  return CategoriesRepositoryImpl(
    localRepository: ref.read(localCategoryRepositoryProvider),
    remoteDatasource: ref.read(categoriesRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return ref.watch(categoryHybridRepositoryProvider);
});

final categorySearchQueryProvider = StateProvider<String>((ref) => '');

final categoryListProvider = FutureProvider<List<Category>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(categorySearchQueryProvider);
  return ref.watch(categoryRepositoryProvider).search(query: query);
});

final categoryOptionsProvider = FutureProvider<List<Category>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(categoryRepositoryProvider).search();
});

final categorySyncControllerProvider =
    AsyncNotifierProvider<CategorySyncController, void>(
      CategorySyncController.new,
    );

class CategorySyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<SyncActionResult> syncNow() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(categoryHybridRepositoryProvider).syncNow();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
