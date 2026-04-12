import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../data/sqlite_operational_order_repository.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_detail.dart';
import '../../domain/entities/operational_order_item.dart';
import '../../domain/entities/operational_order_item_modifier.dart';
import '../../domain/entities/operational_order_summary.dart';
import '../../domain/repositories/operational_order_repository.dart';

final operationalOrderRepositoryProvider = Provider<OperationalOrderRepository>(
  (ref) {
    return SqliteOperationalOrderRepository(ref.read(appDatabaseProvider));
  },
);

final operationalOrderSearchQueryProvider = StateProvider<String>((ref) => '');

final operationalOrderStatusFilterProvider =
    StateProvider<OperationalOrderStatus?>((ref) => null);

final operationalOrdersProvider = FutureProvider<List<OperationalOrderSummary>>(
  (ref) async {
    final query = ref.watch(operationalOrderSearchQueryProvider);
    final status = ref.watch(operationalOrderStatusFilterProvider);
    return ref
        .read(operationalOrderRepositoryProvider)
        .listSummaries(query: query, status: status);
  },
);

final operationalOrderDetailProvider =
    FutureProvider.family<OperationalOrderDetail?, int>((ref, orderId) async {
      final repository = ref.read(operationalOrderRepositoryProvider);
      final order = await repository.findById(orderId);
      if (order == null) {
        return null;
      }

      final itemsFuture = repository.listItems(orderId);
      final linkedSaleFuture = repository.findLinkedSaleId(orderId);
      final items = await itemsFuture;
      final linkedSaleId = await linkedSaleFuture;

      final modifiersFutures = items.map(
        (item) => repository.listItemModifiers(item.id),
      );
      final modifiersList = await Future.wait(modifiersFutures);

      final details = <OperationalOrderItemDetail>[];
      for (var index = 0; index < items.length; index++) {
        details.add(
          OperationalOrderItemDetail(
            item: items[index],
            modifiers: modifiersList[index],
          ),
        );
      }

      return OperationalOrderDetail(
        order: order,
        items: details,
        linkedSaleId: linkedSaleId,
      );
    });

final orderCatalogProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) {
  return ref.read(productRepositoryProvider).searchAvailable(query: query);
});

final createOperationalOrderControllerProvider =
    AsyncNotifierProvider<CreateOperationalOrderController, void>(
      CreateOperationalOrderController.new,
    );

final addOperationalOrderItemControllerProvider =
    AsyncNotifierProvider<AddOperationalOrderItemController, void>(
      AddOperationalOrderItemController.new,
    );

final operationalOrderStatusControllerProvider =
    AsyncNotifierProvider<OperationalOrderStatusController, void>(
      OperationalOrderStatusController.new,
    );

class CreateOperationalOrderController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<int> create({
    String? notes,
    OperationalOrderStatus status = OperationalOrderStatus.draft,
  }) async {
    state = const AsyncLoading();
    try {
      final id = await ref
          .read(operationalOrderRepositoryProvider)
          .create(OperationalOrderInput(notes: notes, status: status));
      ref.invalidate(operationalOrdersProvider);
      state = const AsyncData(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class AddOperationalOrderItemController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> addItemWithModifiers({
    required int orderId,
    required Product product,
    required int quantityUnits,
    String? notes,
    List<OperationalOrderItemModifierInput> modifiers =
        const <OperationalOrderItemModifierInput>[],
  }) async {
    state = const AsyncLoading();
    try {
      final quantityMil = quantityUnits * 1000;
      final itemId = await ref
          .read(operationalOrderRepositoryProvider)
          .addItem(
            orderId,
            OperationalOrderItemInput(
              productId: product.id,
              baseProductId: product.baseProductId,
              productNameSnapshot: product.displayName,
              quantityMil: quantityMil,
              unitPriceCents: product.salePriceCents,
              subtotalCents: product.salePriceCents * quantityUnits,
              notes: notes,
            ),
          );

      for (final modifier in modifiers) {
        await ref
            .read(operationalOrderRepositoryProvider)
            .addItemModifier(itemId, modifier);
      }

      ref.invalidate(operationalOrdersProvider);
      ref.invalidate(operationalOrderDetailProvider(orderId));
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class OperationalOrderStatusController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> updateStatus({
    required int orderId,
    required OperationalOrderStatus status,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(operationalOrderRepositoryProvider)
          .updateStatus(orderId, status);
      ref.invalidate(operationalOrdersProvider);
      ref.invalidate(operationalOrderDetailProvider(orderId));
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
