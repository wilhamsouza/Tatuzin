import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../data/sqlite_operational_order_repository.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_item.dart';
import '../../domain/entities/operational_order_item_modifier.dart';
import '../../domain/repositories/operational_order_repository.dart';

class OperationalOrderItemDetail {
  const OperationalOrderItemDetail({
    required this.item,
    required this.modifiers,
  });

  final OperationalOrderItem item;
  final List<OperationalOrderItemModifier> modifiers;

  int get modifierDeltaCents => modifiers.fold<int>(
    0,
    (sum, modifier) => sum + (modifier.priceDeltaCents * modifier.quantity),
  );

  int get totalCents =>
      item.subtotalCents + (modifierDeltaCents * (item.quantityMil ~/ 1000));
}

class OperationalOrderDetail {
  const OperationalOrderDetail({required this.order, required this.items});

  final OperationalOrder order;
  final List<OperationalOrderItemDetail> items;

  int get itemsCount => items.length;
  int get totalCents =>
      items.fold<int>(0, (sum, item) => sum + item.totalCents);
}

final operationalOrderRepositoryProvider = Provider<OperationalOrderRepository>(
  (ref) {
    return SqliteOperationalOrderRepository(ref.read(appDatabaseProvider));
  },
);

final operationalOrderSearchQueryProvider = StateProvider<String>((ref) => '');

final operationalOrdersProvider = FutureProvider<List<OperationalOrder>>((
  ref,
) async {
  final query = ref.watch(operationalOrderSearchQueryProvider);
  return ref.read(operationalOrderRepositoryProvider).list(query: query);
});

final operationalOrderDetailProvider =
    FutureProvider.family<OperationalOrderDetail?, int>((ref, orderId) async {
      final repository = ref.read(operationalOrderRepositoryProvider);
      final order = await repository.findById(orderId);
      if (order == null) {
        return null;
      }

      final items = await repository.listItems(orderId);
      final details = <OperationalOrderItemDetail>[];
      for (final item in items) {
        final modifiers = await repository.listItemModifiers(item.id);
        details.add(
          OperationalOrderItemDetail(item: item, modifiers: modifiers),
        );
      }

      return OperationalOrderDetail(order: order, items: details);
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

class CreateOperationalOrderController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<int> create({String? notes}) async {
    state = const AsyncLoading();
    try {
      final id = await ref
          .read(operationalOrderRepositoryProvider)
          .create(OperationalOrderInput(notes: notes));
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
