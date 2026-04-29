class OperationalOrderItem {
  const OperationalOrderItem({
    required this.id,
    required this.uuid,
    required this.orderId,
    required this.productId,
    required this.baseProductId,
    this.productVariantId,
    this.variantSkuSnapshot,
    this.variantColorSnapshot,
    this.variantSizeSnapshot,
    required this.productNameSnapshot,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String uuid;
  final int orderId;
  final int productId;
  final int? baseProductId;
  final int? productVariantId;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final String productNameSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int subtotalCents;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class OperationalOrderItemInput {
  const OperationalOrderItemInput({
    required this.productId,
    this.baseProductId,
    this.productVariantId,
    this.variantSkuSnapshot,
    this.variantColorSnapshot,
    this.variantSizeSnapshot,
    required this.productNameSnapshot,
    required this.quantityMil,
    this.unitPriceCents = 0,
    this.subtotalCents = 0,
    this.notes,
  });

  final int productId;
  final int? baseProductId;
  final int? productVariantId;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final String productNameSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int subtotalCents;
  final String? notes;
}
