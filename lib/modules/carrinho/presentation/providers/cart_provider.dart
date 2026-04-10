import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      state = CartState(items: [...state.items, CartItem.fromProduct(product)]);
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

    state = CartState(items: [...state.items, newItem]);
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
    state = CartState(items: items);
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

    state = CartState(items: items);
  }

  void removeItem(String itemId) {
    state = CartState(
      items: state.items.where((item) => item.id != itemId).toList(),
    );
  }

  void clear() {
    state = const CartState(items: []);
  }
}
