class InventorySummary {
  const InventorySummary({
    required this.totalSkus,
    required this.zeroedItems,
    required this.belowMinimumItems,
    required this.estimatedCostCents,
  });

  final int totalSkus;
  final int zeroedItems;
  final int belowMinimumItems;
  final int estimatedCostCents;
}
