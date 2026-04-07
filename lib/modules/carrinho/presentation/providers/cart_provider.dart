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
      (item) => item.productId == product.id,
    );
    if (index == -1) {
      if (product.stockMil < 1000) {
        return false;
      }
      state = CartState(items: [...state.items, CartItem.fromProduct(product)]);
      return true;
    }

    return increaseQuantity(product.id);
  }

  bool increaseQuantity(int productId) {
    final items = [...state.items];
    final index = items.indexWhere((item) => item.productId == productId);
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

  void decreaseQuantity(int productId) {
    final items = [...state.items];
    final index = items.indexWhere((item) => item.productId == productId);
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

  void removeItem(int productId) {
    state = CartState(
      items: state.items.where((item) => item.productId != productId).toList(),
    );
  }

  void clear() {
    state = const CartState(items: []);
  }
}
