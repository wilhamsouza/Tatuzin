import '../../../produtos/domain/entities/product.dart';

class CartItem {
  const CartItem({
    required this.productId,
    required this.productName,
    required this.quantityMil,
    required this.availableStockMil,
    required this.unitPriceCents,
    required this.unitMeasure,
    required this.productType,
  });

  final int productId;
  final String productName;
  final int quantityMil;
  final int availableStockMil;
  final int unitPriceCents;
  final String unitMeasure;
  final String productType;

  factory CartItem.fromProduct(Product product) {
    return CartItem(
      productId: product.id,
      productName: product.displayName,
      quantityMil: 1000,
      availableStockMil: product.stockMil,
      unitPriceCents: product.salePriceCents,
      unitMeasure: product.unitMeasure,
      productType: product.productType,
    );
  }

  int get quantityUnits => quantityMil ~/ 1000;
  int get availableStockUnits => availableStockMil ~/ 1000;
  int get subtotalCents => unitPriceCents * quantityUnits;

  CartItem copyWith({int? quantityMil, int? availableStockMil}) {
    return CartItem(
      productId: productId,
      productName: productName,
      quantityMil: quantityMil ?? this.quantityMil,
      availableStockMil: availableStockMil ?? this.availableStockMil,
      unitPriceCents: unitPriceCents,
      unitMeasure: unitMeasure,
      productType: productType,
    );
  }
}

class CartState {
  const CartState({required this.items});

  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;
  int get totalItems =>
      items.fold(0, (total, item) => total + item.quantityUnits);
  int get totalCents =>
      items.fold(0, (total, item) => total + item.subtotalCents);
}
