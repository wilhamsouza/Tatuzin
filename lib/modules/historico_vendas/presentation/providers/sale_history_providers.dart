import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../vendas/domain/entities/sale_detail.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_record.dart';
import '../../data/sqlite_sale_history_repository.dart';
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
