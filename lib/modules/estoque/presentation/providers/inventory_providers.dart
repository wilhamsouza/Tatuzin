import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../data/inventory_count_repository_impl.dart';
import '../../data/inventory_repository_impl.dart';
import '../../data/sqlite_inventory_count_repository.dart';
import '../../data/sqlite_inventory_repository.dart';
import '../../domain/entities/inventory_adjustment_input.dart';
import '../../domain/entities/inventory_count_item.dart';
import '../../domain/entities/inventory_count_item_input.dart';
import '../../domain/entities/inventory_count_session.dart';
import '../../domain/entities/inventory_count_session_detail.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/inventory_movement.dart';
import '../../domain/repositories/inventory_count_repository.dart';
import '../../domain/repositories/inventory_repository.dart';

final localInventoryRepositoryProvider = Provider<SqliteInventoryRepository>((
  ref,
) {
  return SqliteInventoryRepository(ref.watch(appDatabaseProvider));
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepositoryImpl(
    localRepository: ref.read(localInventoryRepositoryProvider),
  );
});

final localInventoryCountRepositoryProvider =
    Provider<SqliteInventoryCountRepository>((ref) {
      return SqliteInventoryCountRepository(ref.watch(appDatabaseProvider));
    });

final inventoryCountRepositoryProvider = Provider<InventoryCountRepository>((
  ref,
) {
  return InventoryCountRepositoryImpl(
    localRepository: ref.read(localInventoryCountRepositoryProvider),
  );
});

final inventorySearchQueryProvider = StateProvider<String>((ref) => '');

final inventoryFilterProvider = StateProvider<InventoryListFilter>(
  (ref) => InventoryListFilter.all,
);

final inventoryItemsProvider = FutureProvider<List<InventoryItem>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(inventorySearchQueryProvider);
  final filter = ref.watch(inventoryFilterProvider);
  return ref
      .watch(inventoryRepositoryProvider)
      .listItems(query: query, filter: filter);
});

final inventoryItemOptionsProvider = FutureProvider<List<InventoryItem>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(inventoryRepositoryProvider).listItems();
});

final inventoryActiveItemOptionsProvider = FutureProvider<List<InventoryItem>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(inventoryRepositoryProvider)
      .listItems(filter: InventoryListFilter.active);
});

final inventoryMovementsProvider =
    FutureProvider.family<List<InventoryMovement>, InventoryMovementQuery>((
      ref,
      query,
    ) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(inventoryRepositoryProvider)
          .listMovements(
            productId: query.productId,
            productVariantId: query.productVariantId,
            includeVariantsForProduct: query.includeVariantsForProduct,
            movementType: query.movementType,
            createdFrom: query.createdFrom,
            createdTo: query.createdTo,
            limit: query.limit,
          );
    });

final inventoryCountSessionsProvider =
    FutureProvider<List<InventoryCountSession>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref.watch(inventoryCountRepositoryProvider).listSessions();
    });

final inventoryCountSessionDetailProvider =
    FutureProvider.family<InventoryCountSessionDetail?, int>((
      ref,
      sessionId,
    ) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(inventoryCountRepositoryProvider)
          .getSessionDetail(sessionId);
    });

final inventoryActionControllerProvider =
    AsyncNotifierProvider<InventoryActionController, void>(
      InventoryActionController.new,
    );

final inventoryCountActionControllerProvider =
    AsyncNotifierProvider<InventoryCountActionController, void>(
      InventoryCountActionController.new,
    );

class InventoryActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> adjustStock(InventoryAdjustmentInput input) async {
    state = const AsyncLoading();
    try {
      await ref.read(inventoryRepositoryProvider).adjustStock(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class InventoryCountActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<InventoryCountSession> createSession(String name) async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .read(inventoryCountRepositoryProvider)
          .createSession(name: name);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<InventoryCountItem> upsertItem(InventoryCountItemInput input) async {
    state = const AsyncLoading();
    try {
      final item = await ref
          .read(inventoryCountRepositoryProvider)
          .upsertItem(input);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return item;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> markSessionReviewed(int sessionId) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(inventoryCountRepositoryProvider)
          .markSessionReviewed(sessionId);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<InventoryCountItem> recalculateItemFromCurrentStock(
    int countItemId,
  ) async {
    state = const AsyncLoading();
    try {
      final item = await ref
          .read(inventoryCountRepositoryProvider)
          .recalculateItemFromCurrentStock(countItemId);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return item;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<InventoryCountItem> keepRecordedDifference(int countItemId) async {
    state = const AsyncLoading();
    try {
      final item = await ref
          .read(inventoryCountRepositoryProvider)
          .keepRecordedDifference(countItemId);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return item;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> applySession(int sessionId) async {
    state = const AsyncLoading();
    try {
      await ref.read(inventoryCountRepositoryProvider).applySession(sessionId);
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class InventoryMovementQuery {
  const InventoryMovementQuery({
    this.productId,
    this.productVariantId,
    this.includeVariantsForProduct = false,
    this.movementType,
    this.createdFrom,
    this.createdTo,
    this.limit = 300,
  });

  final int? productId;
  final int? productVariantId;
  final bool includeVariantsForProduct;
  final InventoryMovementType? movementType;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final int limit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is InventoryMovementQuery &&
        other.productId == productId &&
        other.productVariantId == productVariantId &&
        other.includeVariantsForProduct == includeVariantsForProduct &&
        other.movementType == movementType &&
        other.createdFrom == createdFrom &&
        other.createdTo == createdTo &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(
    productId,
    productVariantId,
    includeVariantsForProduct,
    movementType,
    createdFrom,
    createdTo,
    limit,
  );
}
