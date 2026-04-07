class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.uuid,
    required this.purchaseId,
    required this.productId,
    required this.productNameSnapshot,
    required this.unitMeasureSnapshot,
    required this.quantityMil,
    required this.unitCostCents,
    required this.subtotalCents,
  });

  final int id;
  final String uuid;
  final int purchaseId;
  final int productId;
  final String productNameSnapshot;
  final String unitMeasureSnapshot;
  final int quantityMil;
  final int unitCostCents;
  final int subtotalCents;
}

class PurchaseItemInput {
  const PurchaseItemInput({
    required this.productId,
    required this.quantityMil,
    required this.unitCostCents,
  });

  final int productId;
  final int quantityMil;
  final int unitCostCents;
}
