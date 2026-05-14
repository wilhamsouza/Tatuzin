import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/utils/app_logger.dart';
import '../../../estoque/domain/entities/stock_availability.dart';
import '../../../estoque/domain/entities/stock_reservation.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../../funcionarios/domain/employee_models.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../domain/entities/cart_enums.dart';
import '../../domain/entities/cart_item.dart';

final cartProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

class CartController extends Notifier<CartState> {
  static const String discountAdjustedNotice =
      'Desconto ajustado ao subtotal atual.';

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
      _replaceState(
        state.copyWith(items: [...state.items, CartItem.fromProduct(product)]),
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
    _replaceState(state.copyWith(items: items));
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
      _replaceState(state.copyWith(items: items));
      return true;
    }

    _replaceState(state.copyWith(items: [...state.items, newItem]));
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
    _replaceState(state.copyWith(items: items));
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
      _replaceState(state.copyWith(items: items));
      return false;
    }

    items[index] = latest.copyWith(
      quantityMil: latest.quantityMil + 1000,
      availableStockMil: availableStockMil,
    );
    _replaceState(state.copyWith(items: items));
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
    _replaceState(state.copyWith(items: items));
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

    _replaceState(state.copyWith(items: items));
  }

  void removeItem(String itemId) {
    _replaceState(
      state.copyWith(
        items: state.items.where((item) => item.id != itemId).toList(),
      ),
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
    _replaceState(state.copyWith(items: items));
  }

  void setTipoEntrega(TipoEntrega tipo) {
    _replaceState(
      state.copyWith(
        tipoEntrega: tipo,
        numeroMesa: tipo == TipoEntrega.mesa ? state.numeroMesa : null,
        cep: tipo == TipoEntrega.delivery ? state.cep : null,
        freteCents: tipo == TipoEntrega.delivery ? state.freteCents : 0,
      ),
    );
  }

  void setNumeroMesa(String numero) {
    _replaceState(state.copyWith(numeroMesa: _cleanNullable(numero)));
  }

  Future<void> setCep(String cep) async {
    final cleanedCep = _cleanDigits(cep);
    _replaceState(
      state.copyWith(
        cep: _cleanNullable(cleanedCep),
        freteCents: cleanedCep.length == 8 ? 500 : 0,
      ),
    );
  }

  void aplicarCupom(String codigo) {
    final normalizedCode = _cleanNullable(codigo)?.toUpperCase();
    if (normalizedCode == 'DESCONTO10') {
      _replaceState(
        state.copyWith(cupomCodigo: normalizedCode, cupomDescontoCents: 1000),
      );
      return;
    }

    throw Exception('Cupom invalido ou expirado.');
  }

  void removerCupom() {
    _replaceState(state.copyWith(cupomCodigo: null, cupomDescontoCents: 0));
  }

  void applySaleDiscount(CartSaleDiscount discount) {
    _ensureCanManageSaleDiscount();
    if (state.items.isEmpty) {
      throw const ValidationException('Carrinho vazio nao permite desconto.');
    }

    if (discount.isAmount) {
      if (discount.amountCents < 0) {
        throw const ValidationException('O desconto nao pode ser negativo.');
      }
      if (discount.amountCents > state.subtotalCents) {
        throw const ValidationException(
          'O desconto nao pode ser maior que o subtotal.',
        );
      }
    } else {
      if (discount.percentBasisPoints < 0 ||
          discount.percentBasisPoints > 10000) {
        throw const ValidationException(
          'O percentual de desconto deve ficar entre 0 e 100.',
        );
      }
    }

    _replaceState(
      state.copyWith(saleDiscount: discount, saleDiscountNotice: null),
    );
  }

  void removeSaleDiscount() {
    _ensureCanManageSaleDiscount();
    _replaceState(state.copyWith(saleDiscount: null, saleDiscountNotice: null));
  }

  void clearSaleDiscountNotice() {
    if (state.saleDiscountNotice == null) {
      return;
    }
    _replaceState(state.copyWith(saleDiscountNotice: null));
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

  void _replaceState(CartState nextState) {
    state = _normalizeState(nextState);
  }

  void _ensureCanManageSaleDiscount() {
    final session = ref.read(appSessionProvider);
    if (!session.canAccessPermission(EmployeePermission.salesDiscount.key)) {
      throw const ValidationException(
        'Voce nao tem permissao para aplicar desconto.',
      );
    }
  }

  CartState _normalizeState(CartState nextState) {
    if (nextState.items.isEmpty) {
      return const CartState(items: []);
    }

    final discount = nextState.saleDiscount;
    if (discount == null) {
      return nextState.copyWith(saleDiscountNotice: null);
    }

    final subtotalCents = nextState.items.fold<int>(
      0,
      (total, item) => total + item.subtotalCents,
    );
    if (subtotalCents <= 0) {
      return nextState.copyWith(saleDiscount: null, saleDiscountNotice: null);
    }

    if (discount.isAmount && discount.amountCents > subtotalCents) {
      return nextState.copyWith(
        saleDiscount: CartSaleDiscount.amount(amountCents: subtotalCents),
        saleDiscountNotice: discountAdjustedNotice,
      );
    }

    return nextState.copyWith(saleDiscountNotice: null);
  }
}
