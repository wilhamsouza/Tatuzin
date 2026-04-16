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
import '../../data/datasources/product_recipes_remote_datasource.dart';
import '../../data/product_media_storage.dart';
import '../../data/product_recipe_sync_processor.dart';
import '../../data/products_repository_impl.dart';
import '../../data/real/real_product_recipes_remote_datasource.dart';
import '../../data/real/real_products_remote_datasource.dart';
import '../../data/sqlite_local_catalog_repository.dart';
import '../../data/sqlite_product_repository.dart';
import '../../domain/entities/base_product.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_profitability_row.dart';
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

final productRecipesRemoteDatasourceProvider =
    Provider<ProductRecipesRemoteDatasource>((ref) {
      return RealProductRecipesRemoteDatasource(
        apiClient: ref.read(realApiClientProvider),
        tokenStorage: ref.read(authTokenStorageProvider),
        environment: ref.watch(appEnvironmentProvider),
        operationalContext: ref.watch(appOperationalContextProvider),
      );
    });

final localCatalogRepositoryProvider = Provider<LocalCatalogRepository>((ref) {
  return SqliteLocalCatalogRepository(ref.read(appDatabaseProvider));
});

final productMediaStorageProvider = Provider<ProductMediaStorage>((ref) {
  return ProductMediaStorage();
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

final productRecipeSyncProcessorProvider =
    Provider<ProductRecipeSyncProcessor>((ref) {
      return ProductRecipeSyncProcessor(
        localRepository: ref.read(localProductRepositoryProvider),
        remoteDatasource: ref.read(productRecipesRemoteDatasourceProvider),
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

final productProfitabilitySearchQueryProvider = StateProvider<String>(
  (ref) => '',
);
final productProfitabilityFilterProvider =
    StateProvider<ProductProfitabilityFilter>(
      (ref) => ProductProfitabilityFilter.all,
    );
final productProfitabilitySortProvider =
    StateProvider<ProductProfitabilitySort>(
      (ref) => ProductProfitabilitySort.marginAsc,
    );

final productProfitabilityRowsProvider =
    FutureProvider<List<ProductProfitabilityRow>>((ref) async {
      ref.watch(appDataRefreshProvider);
      final query = ref.watch(productProfitabilitySearchQueryProvider);
      final filter = ref.watch(productProfitabilityFilterProvider);
      final sort = ref.watch(productProfitabilitySortProvider);
      final products = await ref
          .read(localProductRepositoryProvider)
          .search(query: query);

      final rows = products
          .map(ProductProfitabilityRow.fromProduct)
          .where((row) => _matchesProfitabilityFilter(row, filter))
          .toList(growable: false);
      rows.sort((a, b) => _compareProfitabilityRows(a, b, sort));
      return rows;
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

bool _matchesProfitabilityFilter(
  ProductProfitabilityRow row,
  ProductProfitabilityFilter filter,
) {
  return switch (filter) {
    ProductProfitabilityFilter.all => true,
    ProductProfitabilityFilter.derived => row.hasDerivedCalculation,
    ProductProfitabilityFilter.manual => !row.hasDerivedCalculation,
    ProductProfitabilityFilter.healthy =>
      row.marginStatus == ProductProfitabilityMarginStatus.healthy,
    ProductProfitabilityFilter.attention =>
      row.marginStatus == ProductProfitabilityMarginStatus.attention,
    ProductProfitabilityFilter.low =>
      row.marginStatus == ProductProfitabilityMarginStatus.low,
  };
}

int _compareProfitabilityRows(
  ProductProfitabilityRow a,
  ProductProfitabilityRow b,
  ProductProfitabilitySort sort,
) {
  final rankedA = a.hasDerivedCalculation ? 0 : 1;
  final rankedB = b.hasDerivedCalculation ? 0 : 1;
  if (rankedA != rankedB) {
    return rankedA.compareTo(rankedB);
  }

  final bySort = switch (sort) {
    ProductProfitabilitySort.marginDesc =>
      (b.grossMarginPercentBasisPoints ?? -1).compareTo(
        a.grossMarginPercentBasisPoints ?? -1,
      ),
    ProductProfitabilitySort.marginAsc =>
      (a.grossMarginPercentBasisPoints ?? 999999).compareTo(
        b.grossMarginPercentBasisPoints ?? 999999,
      ),
    ProductProfitabilitySort.costDesc => b.activeCostCents.compareTo(
      a.activeCostCents,
    ),
    ProductProfitabilitySort.updatedDesc => _compareNullableDateDesc(
      a.lastCostUpdatedAt,
      b.lastCostUpdatedAt,
    ),
    ProductProfitabilitySort.nameAsc => a.productName.toLowerCase().compareTo(
      b.productName.toLowerCase(),
    ),
  };
  if (bySort != 0) {
    return bySort;
  }
  return a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
}

int _compareNullableDateDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return b.compareTo(a);
}
