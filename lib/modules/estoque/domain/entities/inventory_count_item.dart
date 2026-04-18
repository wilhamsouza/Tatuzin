class InventoryCountItem {
  const InventoryCountItem({
    required this.id,
    required this.countSessionId,
    required this.productId,
    required this.productVariantId,
    required this.productName,
    required this.sku,
    required this.variantColorLabel,
    required this.variantSizeLabel,
    required this.unitMeasure,
    required this.systemStockMil,
    required this.currentStockMil,
    required this.countedStockMil,
    required this.differenceMil,
    required this.staleOverride,
    required this.appliedFromSystemStockMil,
    required this.staleAtApply,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int countSessionId;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? sku;
  final String? variantColorLabel;
  final String? variantSizeLabel;
  final String unitMeasure;
  final int systemStockMil;
  final int currentStockMil;
  final int countedStockMil;
  final int differenceMil;
  final bool staleOverride;
  final int? appliedFromSystemStockMil;
  final bool staleAtApply;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasVariant => productVariantId != null;
  bool get hasDifference => differenceMil != 0;
  bool get isZeroed => countedStockMil == 0;
  bool get isStale => currentStockMil != systemStockMil;
  bool get needsReview => isStale && !staleOverride;
  bool get readyToApply => !needsReview;
  bool get usesFrozenDifference => isStale && staleOverride;

  String? get variantSummary {
    final parts = <String>[
      if ((variantColorLabel ?? '').trim().isNotEmpty)
        variantColorLabel!.trim(),
      if ((variantSizeLabel ?? '').trim().isNotEmpty) variantSizeLabel!.trim(),
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' / ');
  }

  String get displayName {
    final summary = variantSummary;
    if (summary == null) {
      return productName;
    }
    return '$productName - $summary';
  }
}
