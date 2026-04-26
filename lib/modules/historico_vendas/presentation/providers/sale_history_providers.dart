import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/session/session_provider.dart';
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
  return SqliteSaleHistoryRepository(ref.watch(appDatabaseProvider));
});

final saleHistorySearchQueryProvider = StateProvider<String>((ref) => '');
final saleHistoryStatusFilterProvider = StateProvider<SaleStatus?>(
  (ref) => null,
);
final saleHistoryTypeFilterProvider = StateProvider<SaleType?>((ref) => null);
final saleHistoryFromProvider = StateProvider<DateTime?>((ref) => null);
final saleHistoryToProvider = StateProvider<DateTime?>((ref) => null);

final saleHistoryListProvider = FutureProvider<List<SaleRecord>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(saleHistorySearchQueryProvider);
  final status = ref.watch(saleHistoryStatusFilterProvider);
  final type = ref.watch(saleHistoryTypeFilterProvider);
  final from = ref.watch(saleHistoryFromProvider);
  final to = ref.watch(saleHistoryToProvider);
  return runProviderGuarded(
    'saleHistoryListProvider',
    () => ref
        .watch(saleHistoryRepositoryProvider)
        .search(query: query, status: status, type: type, from: from, to: to),
    timeout: localProviderTimeout,
  );
});

final saleDetailProvider = FutureProvider.family<SaleDetail, int>((
  ref,
  saleId,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'saleDetailProvider',
    () => ref.watch(saleHistoryRepositoryProvider).fetchDetail(saleId),
    timeout: localProviderTimeout,
  );
});

final saleReturnRepositoryProvider = Provider<SqliteSaleReturnRepository>((
  ref,
) {
  return SqliteSaleReturnRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
    ref.read(localSaleRepositoryProvider),
  );
});

final saleReturnsProvider = FutureProvider.family<List<SaleReturnRecord>, int>((
  ref,
  saleId,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'saleReturnsProvider',
    () => ref.watch(saleReturnRepositoryProvider).listForSale(saleId),
    timeout: localProviderTimeout,
  );
});

final saleExchangeProductLookupProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return runProviderGuarded('saleExchangeProductLookupProvider', () async {
        final products = await ref
            .read(localProductRepositoryProvider)
            .searchAvailable(query: query);
        return products
            .where((product) => product.sellableVariantId != null)
            .toList(growable: false);
      }, timeout: defaultProviderTimeout);
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
