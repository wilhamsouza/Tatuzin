import '../../../produtos/domain/entities/product.dart';
import 'cart_enums.dart';

class CartItemModifier {
  const CartItemModifier({
    this.modifierGroupId,
    this.modifierOptionId,
    required this.groupName,
    required this.optionName,
    required this.adjustmentType,
    this.priceDeltaCents = 0,
    this.quantity = 1,
  });

  final int? modifierGroupId;
  final int? modifierOptionId;
  final String groupName;
  final String optionName;
  final String adjustmentType;
  final int priceDeltaCents;
  final int quantity;

  int get totalDeltaCents => priceDeltaCents * quantity;

  String get signature {
    final group = modifierGroupId ?? -1;
    final option = modifierOptionId ?? -1;
    return '$group:$option:$adjustmentType:$priceDeltaCents:$quantity';
  }
}

class CartItem {
  const CartItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.primaryPhotoPath,
    required this.baseProductId,
    required this.baseProductName,
    required this.quantityMil,
    required this.availableStockMil,
    required this.unitPriceCents,
    required this.unitMeasure,
    required this.productType,
    this.modifiers = const <CartItemModifier>[],
    this.notes,
  });

  final String id;
  final int productId;
  final String productName;
  final String? primaryPhotoPath;
  final int? baseProductId;
  final String? baseProductName;
  final int quantityMil;
  final int availableStockMil;
  final int unitPriceCents;
  final String unitMeasure;
  final String productType;
  final List<CartItemModifier> modifiers;
  final String? notes;

  factory CartItem.fromProduct(
    Product product, {
    String? id,
    List<CartItemModifier> modifiers = const <CartItemModifier>[],
    String? notes,
  }) {
    final resolvedId = id ?? _buildId(product.id);
    return CartItem(
      id: resolvedId,
      productId: product.id,
      productName: product.displayName,
      primaryPhotoPath: product.primaryPhotoPath,
      baseProductId: product.baseProductId,
      baseProductName: product.baseProductName,
      quantityMil: 1000,
      availableStockMil: product.stockMil,
      unitPriceCents: product.salePriceCents,
      unitMeasure: product.unitMeasure,
      productType: product.productType,
      modifiers: modifiers,
      notes: _cleanNullable(notes),
    );
  }

  int get quantityUnits => quantityMil ~/ 1000;
  int get availableStockUnits => availableStockMil ~/ 1000;
  int get modifierUnitDeltaCents =>
      modifiers.fold<int>(0, (sum, modifier) => sum + modifier.totalDeltaCents);
  int get effectiveUnitPriceCents => unitPriceCents + modifierUnitDeltaCents;
  int get subtotalCents => effectiveUnitPriceCents * quantityUnits;
  bool get hasCustomization =>
      modifiers.isNotEmpty || (notes?.isNotEmpty ?? false);
  bool get isSimpleLine => !hasCustomization;

  String get signature {
    final modifiersSignature = modifiers
        .map((item) => item.signature)
        .join('|');
    return '$productId::$modifiersSignature::${notes ?? ''}';
  }

  CartItem copyWith({
    int? quantityMil,
    int? availableStockMil,
    List<CartItemModifier>? modifiers,
    String? notes,
  }) {
    return CartItem(
      id: id,
      productId: productId,
      productName: productName,
      primaryPhotoPath: primaryPhotoPath,
      baseProductId: baseProductId,
      baseProductName: baseProductName,
      quantityMil: quantityMil ?? this.quantityMil,
      availableStockMil: availableStockMil ?? this.availableStockMil,
      unitPriceCents: unitPriceCents,
      unitMeasure: unitMeasure,
      productType: productType,
      modifiers: modifiers ?? this.modifiers,
      notes: notes ?? this.notes,
    );
  }

  static String buildCustomId(int productId) => _buildId(productId);

  static String _buildId(int productId) {
    return '${productId}_${DateTime.now().microsecondsSinceEpoch}';
  }

  static String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class CartState {
  const CartState({
    required this.items,
    this.tipoEntrega = TipoEntrega.retirada,
    this.numeroMesa,
    this.cep,
    this.freteCents = 0,
    this.cupomCodigo,
    this.cupomDescontoCents = 0,
  });

  final List<CartItem> items;
  final TipoEntrega tipoEntrega;
  final String? numeroMesa;
  final String? cep;
  final int freteCents;
  final String? cupomCodigo;
  final int cupomDescontoCents;

  bool get isEmpty => items.isEmpty;
  int get totalItems =>
      items.fold(0, (total, item) => total + item.quantityUnits);
  int get subtotalCents =>
      items.fold(0, (total, item) => total + item.subtotalCents);
  int get totalCents => subtotalCents;
  int get finalTotalCents {
    final adjustedTotal = subtotalCents + freteCents - cupomDescontoCents;
    return adjustedTotal < 0 ? 0 : adjustedTotal;
  }

  CartState copyWith({
    List<CartItem>? items,
    TipoEntrega? tipoEntrega,
    Object? numeroMesa = _cartStateUnset,
    Object? cep = _cartStateUnset,
    int? freteCents,
    Object? cupomCodigo = _cartStateUnset,
    int? cupomDescontoCents,
  }) {
    return CartState(
      items: items ?? this.items,
      tipoEntrega: tipoEntrega ?? this.tipoEntrega,
      numeroMesa: identical(numeroMesa, _cartStateUnset)
          ? this.numeroMesa
          : numeroMesa as String?,
      cep: identical(cep, _cartStateUnset) ? this.cep : cep as String?,
      freteCents: freteCents ?? this.freteCents,
      cupomCodigo: identical(cupomCodigo, _cartStateUnset)
          ? this.cupomCodigo
          : cupomCodigo as String?,
      cupomDescontoCents: cupomDescontoCents ?? this.cupomDescontoCents,
    );
  }
}

const Object _cartStateUnset = Object();
