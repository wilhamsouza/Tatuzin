class SaleItemDetail {
  const SaleItemDetail({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.costUnitCents,
    required this.costTotalCents,
    required this.unitMeasure,
    required this.productType,
  });

  final int id;
  final int productId;
  final String productName;
  final int quantityMil;
  final int unitPriceCents;
  final int subtotalCents;
  final int costUnitCents;
  final int costTotalCents;
  final String unitMeasure;
  final String productType;

  int get quantityUnits => quantityMil ~/ 1000;
}
