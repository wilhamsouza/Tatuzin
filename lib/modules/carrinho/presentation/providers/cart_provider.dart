import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/utils/app_logger.dart';
import '../../../estoque/domain/entities/stock_availability.dart';
import '../../../estoque/domain/entities/stock_reservation.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../domain/entities/cart_enums.dart';
import '../../domain/entities/cart_item.dart';
import '../../../produtos/domain/entities/product.dart';

final cartProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

class CartController extends Notifier<CartState> {
  @override
  CartState build() {
    return const CartState(items: []);
  }

  bool addProduct(Product product) {
    if (!product.hasOperationalRemoteIdentity) {
      AppLogger.warn(
        '[Carrinho] blocked product without remote identity | '
        'productLocalId=${product.id} '
        'productVariantLocalId=${product.sellableVariantId} '
        'missingProductRemote=${product.remoteId?.trim().isEmpty ?? true} '
        'missingVariantRemote=${product.sellableVariantId != null && (product.sellableVariantRemoteId?.trim().isEmpty ?? true)}',
      );
      return false;
    }

    if (product.hasVariants && product.sellableVariantId == null) {
      return false;
    }

    final index = state.items.indexWhere(
      (item) =>
          item.productId == product.id &&
          item.productVariantId == product.sellableVariantId &&
          item.isSimpleLine,
    );
    if (index == -1) {
      if (product.stockMil < 1000) {
        return false;
      }
      state = state.copyWith(
        items: [...state.items, CartItem.fromProduct(product)],
      );
      return true;
    }

    final items = [...state.items];
    final current = items[index];
    if (current.quantityMil + 1000 > product.stockMil) {
      return false;
    }
    items[index] = current.copyWith(
      quantityMil: current.quantityMil + 1000,
      availableStockMil: product.stockMil,
    );
    state = state.copyWith(items: items);
    return true;
  }

  bool addCustomizedProduct(
    Product product, {
    List<CartItemModifier> modifiers = const <CartItemModifier>[],
    String? notes,
  }) {
    if (!product.hasOperationalRemoteIdentity) {
      AppLogger.warn(
        '[Carrinho] blocked customized product without remote identity | '
        'productLocalId=${product.id} '
        'productVariantLocalId=${product.sellableVariantId} '
        'missingProductRemote=${product.remoteId?.trim().isEmpty ?? true} '
        'missingVariantRemote=${product.sellableVariantId != null && (product.sellableVariantRemoteId?.trim().isEmpty ?? true)}',
      );
      return false;
    }

    if (product.hasVariants && product.sellableVariantId == null) {
      return false;
    }

    if (product.stockMil < 1000) {
      return false;
    }

    final normalizedModifiers = [...modifiers]
      ..sort((a, b) => a.signature.compareTo(b.signature));

    final newItem = CartItem.fromProduct(
      product,
      id: CartItem.buildCustomId(product.id),
      modifiers: normalizedModifiers,
      notes: notes,
    );

    final index = state.items.indexWhere(
      (item) => item.signature == newItem.signature,
    );
    if (index != -1) {
      final items = [...state.items];
      final current = items[index];
      if (current.quantityMil + 1000 > product.stockMil) {
        return false;
      }
      items[index] = current.copyWith(
        quantityMil: current.quantityMil + 1000,
        availableStockMil: product.stockMil,
      );
      state = state.copyWith(items: items);
      return true;
    }

    state = state.copyWith(items: [...state.items, newItem]);
    return true;
  }

  bool increaseQuantity(String itemId) {
    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      return false;
    }

    final current = items[index];
    if (current.quantityMil + 1000 > current.availableStockMil) {
      return false;
    }

    items[index] = current.copyWith(quantityMil: current.quantityMil + 1000);
    state = state.copyWith(items: items);
    return true;
  }

  Future<bool> increaseQuantityRevalidated(String itemId) async {
    final currentIndex = state.items.indexWhere((item) => item.id == itemId);
    if (currentIndex == -1) {
      return false;
    }
    final current = state.items[currentIndex];

    final StockAvailability availability;
    try {
      availability = await ref
          .read(stockAvailabilityRepositoryProvider)
          .getAvailability(
            productId: current.productId,
            productVariantId: current.productVariantId,
          );
    } catch (error, stackTrace) {
      AppLogger.error(
        '[Carrinho] failed to revalidate item before increment',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }

    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      return false;
    }

    final latest = items[index];
    final availableStockMil = availability.availableQuantityMil;
    if (latest.quantityMil + 1000 > availableStockMil) {
      items[index] = latest.copyWith(availableStockMil: availableStockMil);
      state = state.copyWith(items: items);
      return false;
    }

    items[index] = latest.copyWith(
      quantityMil: latest.quantityMil + 1000,
      availableStockMil: availableStockMil,
    );
    state = state.copyWith(items: items);
    return true;
  }

  Future<void> revalidateAvailability() async {
    if (state.items.isEmpty) {
      return;
    }

    final keys = state.items
        .map(
          (item) => StockReservationProductKey(
            productId: item.productId,
            productVariantId: item.productVariantId,
          ),
        )
        .toSet();
    final Map<StockReservationProductKey, StockAvailability> availabilityByKey;
    try {
      availabilityByKey = await ref
          .read(stockAvailabilityRepositoryProvider)
          .getAvailabilityByProductKeys(keys);
    } catch (error, stackTrace) {
      AppLogger.error(
        '[Carrinho] failed to revalidate item availability',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    final items = state.items
        .map((item) {
          final key = StockReservationProductKey(
            productId: item.productId,
            productVariantId: item.productVariantId,
          );
          final availability = availabilityByKey[key];
          if (availability == null) {
            return item;
          }
          return item.copyWith(
            availableStockMil: availability.availableQuantityMil,
          );
        })
        .toList(growable: false);
    state = state.copyWith(items: items);
  }

  void decreaseQuantity(String itemId) {
    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      return;
    }

    final current = items[index];
    if (current.quantityMil <= 1000) {
      items.removeAt(index);
    } else {
      items[index] = current.copyWith(quantityMil: current.quantityMil - 1000);
    }

    state = state.copyWith(items: items);
  }

  void removeItem(String itemId) {
    state = state.copyWith(
      items: state.items.where((item) => item.id != itemId).toList(),
    );
  }

  void updateItemNotes(String itemId, String? notes) {
    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      return;
    }

    final current = items[index];
    items[index] = CartItem(
      id: current.id,
      productId: current.productId,
      productVariantId: current.productVariantId,
      productRemoteId: current.productRemoteId,
      productVariantRemoteId: current.productVariantRemoteId,
      productName: current.productName,
      primaryPhotoPath: current.primaryPhotoPath,
      baseProductId: current.baseProductId,
      baseProductName: current.baseProductName,
      variantSku: current.variantSku,
      variantColorLabel: current.variantColorLabel,
      variantSizeLabel: current.variantSizeLabel,
      quantityMil: current.quantityMil,
      availableStockMil: current.availableStockMil,
      unitPriceCents: current.unitPriceCents,
      unitMeasure: current.unitMeasure,
      productType: current.productType,
      modifiers: current.modifiers,
      notes: _cleanNullable(notes),
    );
    state = state.copyWith(items: items);
  }

  void setTipoEntrega(TipoEntrega tipo) {
    state = state.copyWith(
      tipoEntrega: tipo,
      numeroMesa: tipo == TipoEntrega.mesa ? state.numeroMesa : null,
      cep: tipo == TipoEntrega.delivery ? state.cep : null,
      freteCents: tipo == TipoEntrega.delivery ? state.freteCents : 0,
    );
  }

  void setNumeroMesa(String numero) {
    state = state.copyWith(numeroMesa: _cleanNullable(numero));
  }

  Future<void> setCep(String cep) async {
    final cleanedCep = _cleanDigits(cep);
    state = state.copyWith(
      cep: _cleanNullable(cleanedCep),
      freteCents: cleanedCep.length == 8 ? 500 : 0,
    );
  }

  void aplicarCupom(String codigo) {
    final normalizedCode = _cleanNullable(codigo)?.toUpperCase();
    if (normalizedCode == 'DESCONTO10') {
      state = state.copyWith(
        cupomCodigo: normalizedCode,
        cupomDescontoCents: 1000,
      );
      return;
    }

    throw Exception('Cupom inválido ou expirado.');
  }

  void removerCupom() {
    state = state.copyWith(cupomCodigo: null, cupomDescontoCents: 0);
  }

  void clear() {
    state = const CartState(items: []);
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _cleanDigits(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
