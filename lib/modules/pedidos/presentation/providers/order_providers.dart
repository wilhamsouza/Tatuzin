import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/checkout_input.dart';
import '../../../vendas/domain/entities/completed_sale.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';
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
    StateProvider<OperationalOrderStatus>((ref) => OperationalOrderStatus.open);

class OperationalOrderBoardData {
  const OperationalOrderBoardData({required this.orders});

  final List<OperationalOrderSummary> orders;

  int countFor(OperationalOrderStatus status) {
    return orders.where((summary) => summary.order.status == status).length;
  }

  List<OperationalOrderSummary> filterBy(OperationalOrderStatus status) {
    return orders
        .where((summary) => summary.order.status == status)
        .toList(growable: false);
  }

  int get activeCount =>
      orders.where((summary) => !summary.order.isTerminal).length;
}

final operationalOrderBoardProvider = FutureProvider<OperationalOrderBoardData>(
  (ref) async {
    final query = ref.watch(operationalOrderSearchQueryProvider);
    final orders = await ref
        .read(operationalOrderRepositoryProvider)
        .listSummaries(query: query);
    return OperationalOrderBoardData(orders: orders);
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

class OrderCatalogGroup {
  const OrderCatalogGroup({required this.label, required this.products});

  final String label;
  final List<Product> products;
}

final orderCatalogGroupsProvider =
    FutureProvider.family<List<OrderCatalogGroup>, String>((ref, query) async {
      final products = await ref.watch(orderCatalogProvider(query).future);
      final grouped = <String, List<Product>>{};
      for (final product in products) {
        final label = (product.categoryName?.trim().isNotEmpty ?? false)
            ? product.categoryName!.trim()
            : 'Sem categoria';
        grouped.putIfAbsent(label, () => <Product>[]).add(product);
      }

      final categories = grouped.keys.toList(growable: false)..sort();
      return categories
          .map(
            (category) => OrderCatalogGroup(
              label: category,
              products:
                  (grouped[category]!..sort(
                        (left, right) =>
                            left.displayName.compareTo(right.displayName),
                      ))
                      .toList(growable: false),
            ),
          )
          .toList(growable: false);
    });

final createOperationalOrderControllerProvider =
    AsyncNotifierProvider<CreateOperationalOrderController, void>(
      CreateOperationalOrderController.new,
    );

final operationalOrderDraftControllerProvider =
    AsyncNotifierProvider<OperationalOrderDraftController, void>(
      OperationalOrderDraftController.new,
    );

final operationalOrderItemControllerProvider =
    AsyncNotifierProvider<OperationalOrderItemController, void>(
      OperationalOrderItemController.new,
    );

final operationalOrderStatusControllerProvider =
    AsyncNotifierProvider<OperationalOrderStatusController, void>(
      OperationalOrderStatusController.new,
    );

final operationalOrderBillingControllerProvider =
    AsyncNotifierProvider<OperationalOrderBillingController, void>(
      OperationalOrderBillingController.new,
    );

class CreateOperationalOrderController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<int> createDraft({
    OperationalOrderServiceType serviceType =
        OperationalOrderServiceType.counter,
    String? customerIdentifier,
    String? customerPhone,
    String? notes,
  }) async {
    state = const AsyncLoading();
    try {
      final id = await ref
          .read(operationalOrderRepositoryProvider)
          .create(
            OperationalOrderInput(
              serviceType: serviceType,
              customerIdentifier: customerIdentifier,
              customerPhone: customerPhone,
              notes: notes,
            ),
          );
      ref.invalidate(operationalOrderBoardProvider);
      state = const AsyncData(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class OperationalOrderDraftController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> save({
    required int orderId,
    required OperationalOrderServiceType serviceType,
    String? customerIdentifier,
    String? customerPhone,
    String? notes,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(operationalOrderRepositoryProvider)
          .updateDraft(
            orderId,
            OperationalOrderDraftInput(
              serviceType: serviceType,
              customerIdentifier: customerIdentifier,
              customerPhone: customerPhone,
              notes: notes,
            ),
          );
      _invalidateOrder(orderId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void _invalidateOrder(int orderId) {
    ref.invalidate(operationalOrderBoardProvider);
    ref.invalidate(operationalOrderDetailProvider(orderId));
  }
}

class OperationalOrderItemController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> addItemWithModifiers({
    required int orderId,
    required int productId,
    required int? baseProductId,
    required String productName,
    required int unitPriceCents,
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
              productId: productId,
              baseProductId: baseProductId,
              productNameSnapshot: productName,
              quantityMil: quantityMil,
              unitPriceCents: unitPriceCents,
              subtotalCents: unitPriceCents * quantityUnits,
              notes: notes,
            ),
          );

      if (modifiers.isNotEmpty) {
        await ref
            .read(operationalOrderRepositoryProvider)
            .replaceItemModifiers(itemId, modifiers);
      }

      _invalidateOrder(orderId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> updateItemWithModifiers({
    required int orderId,
    required int orderItemId,
    required int productId,
    required int? baseProductId,
    required String productName,
    required int quantityUnits,
    required int unitPriceCents,
    String? notes,
    List<OperationalOrderItemModifierInput> modifiers =
        const <OperationalOrderItemModifierInput>[],
  }) async {
    state = const AsyncLoading();
    try {
      final quantityMil = quantityUnits * 1000;
      await ref
          .read(operationalOrderRepositoryProvider)
          .updateItem(
            orderItemId,
            OperationalOrderItemInput(
              productId: productId,
              baseProductId: baseProductId,
              productNameSnapshot: productName,
              quantityMil: quantityMil,
              unitPriceCents: unitPriceCents,
              subtotalCents: unitPriceCents * quantityUnits,
              notes: notes,
            ),
          );
      await ref
          .read(operationalOrderRepositoryProvider)
          .replaceItemModifiers(orderItemId, modifiers);
      _invalidateOrder(orderId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> removeItem({
    required int orderId,
    required int orderItemId,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(operationalOrderRepositoryProvider)
          .removeItem(orderItemId);
      _invalidateOrder(orderId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void _invalidateOrder(int orderId) {
    ref.invalidate(operationalOrderBoardProvider);
    ref.invalidate(operationalOrderDetailProvider(orderId));
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
      ref.invalidate(operationalOrderBoardProvider);
      ref.invalidate(operationalOrderDetailProvider(orderId));
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class OperationalOrderBillingController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<CompletedSale> invoice({
    required OperationalOrderDetail detail,
    required PaymentMethod paymentMethod,
  }) async {
    state = const AsyncLoading();
    try {
      if (!detail.order.canBeInvoiced) {
        throw StateError('Faturamento liberado apenas para pedidos entregues.');
      }
      if (!detail.hasItems) {
        throw StateError('Nao ha itens para faturar neste pedido.');
      }
      if (detail.linkedSaleId != null) {
        throw StateError(
          'Pedido #${detail.order.id} ja foi faturado na venda #${detail.linkedSaleId}.',
        );
      }

      final cartItems = detail.items
          .map<CartItem>((entry) {
            final item = entry.item;
            final modifiers = entry.modifiers
                .map(
                  (modifier) => CartItemModifier(
                    modifierGroupId: modifier.modifierGroupId,
                    modifierOptionId: modifier.modifierOptionId,
                    groupName: modifier.groupNameSnapshot ?? 'Modificador',
                    optionName: modifier.optionNameSnapshot,
                    adjustmentType: modifier.adjustmentTypeSnapshot,
                    priceDeltaCents: modifier.priceDeltaCents,
                    quantity: modifier.quantity,
                  ),
                )
                .toList(growable: false);
            return CartItem(
              id: 'order_item_${item.id}',
              productId: item.productId,
              productName: item.productNameSnapshot,
              primaryPhotoPath: null,
              baseProductId: item.baseProductId,
              baseProductName: null,
              quantityMil: item.quantityMil,
              availableStockMil: item.quantityMil,
              unitPriceCents: item.unitPriceCents,
              unitMeasure: 'un',
              productType: 'unidade',
              modifiers: modifiers,
              notes: item.notes,
            );
          })
          .toList(growable: false);

      final checkoutInput = CheckoutInput(
        items: cartItems,
        saleType: SaleType.cash,
        paymentMethod: paymentMethod,
        operationalOrderId: detail.order.id,
        notes: 'Venda originada do pedido operacional #${detail.order.id}.',
      );

      final sale = await ref
          .read(saleRepositoryProvider)
          .completeCashSale(input: checkoutInput);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(operationalOrderBoardProvider);
      ref.invalidate(operationalOrderDetailProvider(detail.order.id));
      state = const AsyncData(null);
      return sale;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
