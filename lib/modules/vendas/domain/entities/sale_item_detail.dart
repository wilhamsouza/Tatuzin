class SaleItemDetail {
  const SaleItemDetail({
    required this.id,
    required this.productId,
    this.productVariantId,
    required this.productName,
    this.variantSkuSnapshot,
    this.variantColorSnapshot,
    this.variantSizeSnapshot,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.costUnitCents,
    required this.costTotalCents,
    required this.unitMeasure,
    required this.productType,
    this.itemNotes,
    this.modifiers = const <SaleItemModifierSnapshot>[],
  });

  final int id;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int subtotalCents;
  final int costUnitCents;
  final int costTotalCents;
  final String unitMeasure;
  final String productType;
  final String? itemNotes;
  final List<SaleItemModifierSnapshot> modifiers;

  int get quantityUnits => quantityMil ~/ 1000;

  String? get variantSummary {
    final labels = <String>[
      if ((variantColorSnapshot ?? '').trim().isNotEmpty)
        variantColorSnapshot!.trim(),
      if ((variantSizeSnapshot ?? '').trim().isNotEmpty)
        variantSizeSnapshot!.trim(),
    ];
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' / ');
  }

  int get modifiersUnitDeltaCents => modifiers.fold<int>(
    0,
    (sum, modifier) => sum + (modifier.priceDeltaCents * modifier.quantity),
  );
}

class SaleItemModifierSnapshot {
  const SaleItemModifierSnapshot({
    this.modifierGroupId,
    this.modifierOptionId,
    this.groupNameSnapshot,
    required this.optionNameSnapshot,
    required this.adjustmentTypeSnapshot,
    this.priceDeltaCents = 0,
    this.quantity = 1,
  });

  final int? modifierGroupId;
  final int? modifierOptionId;
  final String? groupNameSnapshot;
  final String optionNameSnapshot;
  final String adjustmentTypeSnapshot;
  final int priceDeltaCents;
  final int quantity;
}
