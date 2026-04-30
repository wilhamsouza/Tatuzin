class StockAvailability {
  factory StockAvailability({
    required int productId,
    required int? productVariantId,
    required int physicalQuantityMil,
    required int reservedQuantityMil,
  }) {
    final rawAvailableQuantityMil = physicalQuantityMil - reservedQuantityMil;
    return StockAvailability._(
      productId: productId,
      productVariantId: productVariantId,
      physicalQuantityMil: physicalQuantityMil,
      reservedQuantityMil: reservedQuantityMil,
      availableQuantityMil: rawAvailableQuantityMil < 0
          ? 0
          : rawAvailableQuantityMil,
    );
  }

  const StockAvailability._({
    required this.productId,
    required this.productVariantId,
    required this.physicalQuantityMil,
    required this.reservedQuantityMil,
    required this.availableQuantityMil,
  });

  final int productId;
  final int? productVariantId;
  final int physicalQuantityMil;
  final int reservedQuantityMil;
  final int availableQuantityMil;

  int get rawAvailableQuantityMil => physicalQuantityMil - reservedQuantityMil;
}
