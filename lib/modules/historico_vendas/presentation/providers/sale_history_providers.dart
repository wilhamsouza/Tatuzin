import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/sale_detail.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_record.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';
import '../../data/sqlite_sale_history_repository.dart';
import '../../data/sqlite_sale_return_repository.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sale_history_repository.dart';

final saleHistoryRepositoryProvider = Provider<SaleHistoryRepository>((ref) {
  return SqliteSaleHistoryRepository(ref.read(appDatabaseProvider));
});

final saleHistorySearchQueryProvider = StateProvider<String>((ref) => '');
final saleHistoryStatusFilterProvider = StateProvider<SaleStatus?>(
  (ref) => null,
);
final saleHistoryTypeFilterProvider = StateProvider<SaleType?>((ref) => null);
final saleHistoryFromProvider = StateProvider<DateTime?>((ref) => null);
final saleHistoryToProvider = StateProvider<DateTime?>((ref) => null);

final saleHistoryListProvider = FutureProvider<List<SaleRecord>>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(saleHistoryRepositoryProvider)
      .search(
        query: ref.watch(saleHistorySearchQueryProvider),
        status: ref.watch(saleHistoryStatusFilterProvider),
        type: ref.watch(saleHistoryTypeFilterProvider),
        from: ref.watch(saleHistoryFromProvider),
        to: ref.watch(saleHistoryToProvider),
      );
});

final saleDetailProvider = FutureProvider.family<SaleDetail, int>((
  ref,
  saleId,
) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(saleHistoryRepositoryProvider).fetchDetail(saleId);
});

final saleReturnRepositoryProvider = Provider<SqliteSaleReturnRepository>((ref) {
  return SqliteSaleReturnRepository(
    ref.read(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
    ref.read(localSaleRepositoryProvider),
  );
});

final saleReturnsProvider =
    FutureProvider.family<List<SaleReturnRecord>, int>((ref, saleId) async {
      ref.watch(appDataRefreshProvider);
      return ref.watch(saleReturnRepositoryProvider).listForSale(saleId);
    });

final saleExchangeProductLookupProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
      ref.watch(appDataRefreshProvider);
      final products = await ref
          .read(productRepositoryProvider)
          .searchAvailable(query: query);
      return products
          .where((product) => product.sellableVariantId != null)
          .toList(growable: false);
    });

final saleExchangeControllerProvider =
    AsyncNotifierProvider<SaleExchangeController, void>(
      SaleExchangeController.new,
    );

class SaleExchangeController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<SaleReturnResult> registerReturn(SaleReturnInput input) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(saleReturnRepositoryProvider)
          .registerReturn(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
