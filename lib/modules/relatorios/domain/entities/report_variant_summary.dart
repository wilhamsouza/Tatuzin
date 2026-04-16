class ReportVariantSummary {
  const ReportVariantSummary({
    required this.productId,
    required this.variantId,
    required this.modelName,
    required this.variantSku,
    required this.colorLabel,
    required this.sizeLabel,
    required this.currentStockMil,
    required this.soldQuantityMil,
    required this.purchasedQuantityMil,
    required this.grossRevenueCents,
  });

  final int productId;
  final int variantId;
  final String modelName;
  final String? variantSku;
  final String? colorLabel;
  final String? sizeLabel;
  final int currentStockMil;
  final int soldQuantityMil;
  final int purchasedQuantityMil;
  final int grossRevenueCents;

  String get variantSummary {
    final labels = <String>[
      if ((colorLabel ?? '').trim().isNotEmpty) colorLabel!.trim(),
      if ((sizeLabel ?? '').trim().isNotEmpty) sizeLabel!.trim(),
    ];
    return labels.isEmpty ? 'Variante sem identificacao' : labels.join(' / ');
  }

  bool get hasSales => soldQuantityMil > 0;
}
