enum PurchaseItemType { product, supply }

extension PurchaseItemTypeX on PurchaseItemType {
  String get storageValue {
    return switch (this) {
      PurchaseItemType.product => 'product',
      PurchaseItemType.supply => 'supply',
    };
  }

  String get label {
    return switch (this) {
      PurchaseItemType.product => 'Produto',
      PurchaseItemType.supply => 'Insumo',
    };
  }
}

PurchaseItemType purchaseItemTypeFromStorage(String? value) {
  return switch (value) {
    'supply' => PurchaseItemType.supply,
    _ => PurchaseItemType.product,
  };
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.uuid,
    required this.purchaseId,
    required this.itemType,
    required this.productId,
    required this.productVariantId,
    required this.supplyId,
    required this.itemNameSnapshot,
    required this.variantSkuSnapshot,
    required this.variantColorLabelSnapshot,
    required this.variantSizeLabelSnapshot,
    required this.unitMeasureSnapshot,
    required this.quantityMil,
    required this.unitCostCents,
    required this.subtotalCents,
  });

  final int id;
  final String uuid;
  final int purchaseId;
  final PurchaseItemType itemType;
  final int? productId;
  final int? productVariantId;
  final int? supplyId;
  final String itemNameSnapshot;
  final String? variantSkuSnapshot;
  final String? variantColorLabelSnapshot;
  final String? variantSizeLabelSnapshot;
  final String unitMeasureSnapshot;
  final int quantityMil;
  final int unitCostCents;
  final int subtotalCents;

  bool get isProduct => itemType == PurchaseItemType.product;

  bool get isSupply => itemType == PurchaseItemType.supply;

  bool get hasVariant => productVariantId != null;

  String? get variantSummary {
    final labels = <String>[
      if ((variantSizeLabelSnapshot ?? '').trim().isNotEmpty)
        variantSizeLabelSnapshot!.trim(),
      if ((variantColorLabelSnapshot ?? '').trim().isNotEmpty)
        variantColorLabelSnapshot!.trim(),
    ];
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' / ');
  }
}

class PurchaseItemInput {
  const PurchaseItemInput({
    required this.itemType,
    required this.productId,
    required this.productVariantId,
    required this.supplyId,
    this.variantSkuSnapshot,
    this.variantColorLabelSnapshot,
    this.variantSizeLabelSnapshot,
    required this.quantityMil,
    required this.unitCostCents,
  });

  final PurchaseItemType itemType;
  final int? productId;
  final int? productVariantId;
  final int? supplyId;
  final String? variantSkuSnapshot;
  final String? variantColorLabelSnapshot;
  final String? variantSizeLabelSnapshot;
  final int quantityMil;
  final int unitCostCents;
}
