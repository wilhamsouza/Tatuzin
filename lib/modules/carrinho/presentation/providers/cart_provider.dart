import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final index = state.items.indexWhere(
      (item) => item.productId == product.id && item.isSimpleLine,
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

    return increaseQuantity(state.items[index].id);
  }

  bool addCustomizedProduct(
    Product product, {
    List<CartItemModifier> modifiers = const <CartItemModifier>[],
    String? notes,
  }) {
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
      return increaseQuantity(state.items[index].id);
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
      productName: current.productName,
      primaryPhotoPath: current.primaryPhotoPath,
      baseProductId: current.baseProductId,
      baseProductName: current.baseProductName,
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
