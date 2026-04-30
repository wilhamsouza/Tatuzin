import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_context_logger.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../estoque/domain/entities/stock_availability.dart';
import '../../../estoque/domain/entities/stock_reservation.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
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
import '../support/order_ui_support.dart';

final operationalOrderRepositoryProvider = Provider<OperationalOrderRepository>(
  (ref) {
    return SqliteOperationalOrderRepository(ref.watch(appDatabaseProvider));
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
    await requireTenantBootstrapReady(ref, 'operationalOrderBoardProvider');
    logProviderContext(ref, 'operationalOrderBoardProvider');
    final query = ref.watch(operationalOrderSearchQueryProvider);
    final orders = await runProviderGuarded(
      'operationalOrderBoardProvider',
      () => ref
          .read(operationalOrderRepositoryProvider)
          .listSummaries(query: query),
      timeout: localProviderTimeout,
    );
    return OperationalOrderBoardData(orders: orders);
  },
);

final operationalOrderDetailProvider =
    FutureProvider.family<OperationalOrderDetail?, int>((ref, orderId) async {
      await requireTenantBootstrapReady(ref, 'operationalOrderDetailProvider');
      final repository = ref.read(operationalOrderRepositoryProvider);
      return runProviderGuarded('operationalOrderDetailProvider', () async {
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
      }, timeout: localProviderTimeout);
    });

final orderCatalogProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) async {
  await requireTenantBootstrapReady(ref, 'orderCatalogProvider');
  return runProviderGuarded(
    'orderCatalogProvider',
    () =>
        ref.read(localProductRepositoryProvider).searchAvailable(query: query),
    timeout: defaultProviderTimeout,
  );
});

class OrderSellableProductKey {
  const OrderSellableProductKey({
    required this.productId,
    required this.productVariantId,
  });

  final int productId;
  final int? productVariantId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OrderSellableProductKey &&
        other.productId == productId &&
        other.productVariantId == productVariantId;
  }

  @override
  int get hashCode => Object.hash(productId, productVariantId);
}

class OrderSellableProductOption {
  const OrderSellableProductOption({
    required this.product,
    required this.availability,
  });

  final Product product;
  final StockAvailability availability;

  int get physicalQuantityMil => availability.physicalQuantityMil;
  int get reservedQuantityMil => availability.reservedQuantityMil;
  int get availableQuantityMil => availability.availableQuantityMil;
  bool get hasAvailability => availableQuantityMil > 0;
}

final orderSellableProductAvailabilityProvider =
    FutureProvider.family<StockAvailability, OrderSellableProductKey>((
      ref,
      key,
    ) async {
      await requireTenantBootstrapReady(
        ref,
        'orderSellableProductAvailabilityProvider',
      );
      ref.watch(appDataRefreshProvider);
      return ref
          .read(stockAvailabilityRepositoryProvider)
          .getAvailability(
            productId: key.productId,
            productVariantId: key.productVariantId,
          );
    });

final orderCatalogOptionsProvider =
    FutureProvider.family<List<OrderSellableProductOption>, String>((
      ref,
      query,
    ) async {
      await requireTenantBootstrapReady(ref, 'orderCatalogOptionsProvider');
      ref.watch(appDataRefreshProvider);
      return runProviderGuarded('orderCatalogOptionsProvider', () async {
        final products = await ref.watch(orderCatalogProvider(query).future);
        final keys = products
            .map(
              (product) => StockReservationProductKey(
                productId: product.id,
                productVariantId: product.sellableVariantId,
              ),
            )
            .toSet();
        final availabilityByKey = await ref
            .read(stockAvailabilityRepositoryProvider)
            .getAvailabilityByProductKeys(keys);

        return products
            .map((product) {
              final key = StockReservationProductKey(
                productId: product.id,
                productVariantId: product.sellableVariantId,
              );
              return OrderSellableProductOption(
                product: product,
                availability: availabilityByKey[key]!,
              );
            })
            .where((option) => option.hasAvailability)
            .toList(growable: false);
      }, timeout: defaultProviderTimeout);
    });

class OrderCatalogGroup {
  const OrderCatalogGroup({required this.label, required this.products});

  final String label;
  final List<Product> products;
}

class OrderCatalogOptionGroup {
  const OrderCatalogOptionGroup({required this.label, required this.options});

  final String label;
  final List<OrderSellableProductOption> options;
}

final orderCatalogGroupsProvider =
    FutureProvider.family<List<OrderCatalogGroup>, String>((ref, query) async {
      return runProviderGuarded('orderCatalogGroupsProvider', () async {
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
      }, timeout: defaultProviderTimeout);
    });

final orderCatalogOptionGroupsProvider =
    FutureProvider.family<List<OrderCatalogOptionGroup>, String>((
      ref,
      query,
    ) async {
      return runProviderGuarded('orderCatalogOptionGroupsProvider', () async {
        final options = await ref.watch(
          orderCatalogOptionsProvider(query).future,
        );
        final grouped = <String, List<OrderSellableProductOption>>{};
        for (final option in options) {
          final label =
              (option.product.categoryName?.trim().isNotEmpty ?? false)
              ? option.product.categoryName!.trim()
              : 'Sem categoria';
          grouped
              .putIfAbsent(label, () => <OrderSellableProductOption>[])
              .add(option);
        }

        final categories = grouped.keys.toList(growable: false)..sort();
        return categories
            .map(
              (category) => OrderCatalogOptionGroup(
                label: category,
                options:
                    (grouped[category]!..sort(
                          (left, right) => left.product.displayName.compareTo(
                            right.product.displayName,
                          ),
                        ))
                        .toList(growable: false),
              ),
            )
            .toList(growable: false);
      }, timeout: defaultProviderTimeout);
    });

String operationalOrderAvailabilityErrorMessage({
  required String productName,
  required int availableQuantityMil,
  String? sku,
  String? color,
  String? size,
}) {
  final details = <String>[
    if ((sku ?? '').trim().isNotEmpty) sku!.trim(),
    if ((color ?? '').trim().isNotEmpty) color!.trim(),
    if ((size ?? '').trim().isNotEmpty) size!.trim(),
  ];
  if (details.isEmpty) {
    return 'Estoque disponivel insuficiente. Disponivel: ${operationalOrderFormatQuantityMil(availableQuantityMil)}.';
  }
  return 'Estoque insuficiente para ${details.join(' / ')}. Disponivel: ${operationalOrderFormatQuantityMil(availableQuantityMil)}.';
}

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
    int? productVariantId,
    String? variantSkuSnapshot,
    String? variantColorSnapshot,
    String? variantSizeSnapshot,
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
      await _ensureStockAvailableForItem(
        productId: productId,
        productVariantId: productVariantId,
        variantSkuSnapshot: variantSkuSnapshot,
        variantColorSnapshot: variantColorSnapshot,
        variantSizeSnapshot: variantSizeSnapshot,
        productName: productName,
        quantityMil: quantityMil,
        orderItemId: null,
      );
      final itemId = await ref
          .read(operationalOrderRepositoryProvider)
          .addItem(
            orderId,
            OperationalOrderItemInput(
              productId: productId,
              baseProductId: baseProductId,
              productVariantId: productVariantId,
              variantSkuSnapshot: variantSkuSnapshot,
              variantColorSnapshot: variantColorSnapshot,
              variantSizeSnapshot: variantSizeSnapshot,
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
    int? productVariantId,
    String? variantSkuSnapshot,
    String? variantColorSnapshot,
    String? variantSizeSnapshot,
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
      await _ensureStockAvailableForItem(
        productId: productId,
        productVariantId: productVariantId,
        variantSkuSnapshot: variantSkuSnapshot,
        variantColorSnapshot: variantColorSnapshot,
        variantSizeSnapshot: variantSizeSnapshot,
        productName: productName,
        quantityMil: quantityMil,
        orderItemId: orderItemId,
      );
      await ref
          .read(operationalOrderRepositoryProvider)
          .updateItem(
            orderItemId,
            OperationalOrderItemInput(
              productId: productId,
              baseProductId: baseProductId,
              productVariantId: productVariantId,
              variantSkuSnapshot: variantSkuSnapshot,
              variantColorSnapshot: variantColorSnapshot,
              variantSizeSnapshot: variantSizeSnapshot,
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
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(operationalOrderBoardProvider);
    ref.invalidate(operationalOrderDetailProvider(orderId));
  }

  Future<void> _ensureStockAvailableForItem({
    required int productId,
    required int? productVariantId,
    required String? variantSkuSnapshot,
    required String? variantColorSnapshot,
    required String? variantSizeSnapshot,
    required String productName,
    required int quantityMil,
    required int? orderItemId,
  }) async {
    if (quantityMil <= 0) {
      throw const ValidationException(
        'A quantidade do item precisa ser maior que zero.',
      );
    }

    final availability = await ref
        .read(stockAvailabilityRepositoryProvider)
        .getAvailability(
          productId: productId,
          productVariantId: productVariantId,
        );
    var allowedQuantityMil = availability.availableQuantityMil;

    if (orderItemId != null) {
      final activeReservation = await ref
          .read(stockReservationRepositoryProvider)
          .findActiveByOrderItemId(orderItemId);
      if (activeReservation != null &&
          activeReservation.productId == productId &&
          activeReservation.productVariantId == productVariantId) {
        allowedQuantityMil += activeReservation.quantityMil;
      }
    }

    if (quantityMil > allowedQuantityMil) {
      throw ValidationException(
        operationalOrderAvailabilityErrorMessage(
          productName: productName,
          availableQuantityMil: allowedQuantityMil,
          sku: variantSkuSnapshot,
          color: variantColorSnapshot,
          size: variantSizeSnapshot,
        ),
      );
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
      ref.read(appDataRefreshProvider.notifier).state++;
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
      if (detail.linkedSaleId != null) {
        throw ValidationException(
          'Pedido #${detail.order.id} ja foi faturado na venda #${detail.linkedSaleId}.',
        );
      }
      if (detail.order.status == OperationalOrderStatus.canceled) {
        throw const ValidationException(
          'Pedido cancelado nao pode ser faturado.',
        );
      }
      if (!detail.order.canBeInvoiced) {
        throw const ValidationException(
          'Faturamento liberado apenas para pedidos entregues.',
        );
      }
      if (!detail.hasItems) {
        throw const ValidationException(
          'Nao ha itens para faturar neste pedido.',
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
              productVariantId: item.productVariantId,
              productName: item.productNameSnapshot,
              primaryPhotoPath: null,
              baseProductId: item.baseProductId,
              baseProductName: null,
              variantSku: item.variantSkuSnapshot,
              variantColorLabel: item.variantColorSnapshot,
              variantSizeLabel: item.variantSizeSnapshot,
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
        notes: 'Venda originada do pedido de venda #${detail.order.id}.',
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
