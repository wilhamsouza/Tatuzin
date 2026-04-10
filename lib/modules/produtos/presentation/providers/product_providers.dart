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
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../data/datasources/products_remote_datasource.dart';
import '../../data/products_repository_impl.dart';
import '../../data/real/real_products_remote_datasource.dart';
import '../../data/sqlite_local_catalog_repository.dart';
import '../../data/sqlite_product_repository.dart';
import '../../domain/entities/base_product.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/local_catalog_repository.dart';
import '../../domain/repositories/product_repository.dart';

final localProductRepositoryProvider = Provider<SqliteProductRepository>((ref) {
  return SqliteProductRepository(
    ref.read(appDatabaseProvider),
    categoryRepository: ref.read(localCategoryRepositoryProvider),
  );
});

final productsRemoteDatasourceProvider = Provider<ProductsRemoteDatasource>((
  ref,
) {
  return RealProductsRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final localCatalogRepositoryProvider = Provider<LocalCatalogRepository>((ref) {
  return SqliteLocalCatalogRepository(ref.read(appDatabaseProvider));
});

final baseProductOptionsProvider = FutureProvider<List<BaseProduct>>((
  ref,
) async {
  return ref.read(localCatalogRepositoryProvider).listBaseProducts();
});

final productHybridRepositoryProvider = Provider<ProductsRepositoryImpl>((ref) {
  return ProductsRepositoryImpl(
    localRepository: ref.read(localProductRepositoryProvider),
    localCategoryRepository: ref.read(localCategoryRepositoryProvider),
    remoteDatasource: ref.read(productsRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ref.watch(productHybridRepositoryProvider);
});

final productSearchQueryProvider = StateProvider<String>((ref) => '');

final productListProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(productSearchQueryProvider);
  return ref.watch(productRepositoryProvider).search(query: query);
});

final productCatalogProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(productRepositoryProvider).search();
});

final productSyncControllerProvider =
    AsyncNotifierProvider<ProductSyncController, void>(
      ProductSyncController.new,
    );

class ProductSyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<SyncActionResult> syncNow() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(productHybridRepositoryProvider).syncNow();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
