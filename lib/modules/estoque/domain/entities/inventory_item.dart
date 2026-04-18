enum InventoryListFilter { all, belowMinimum, zeroed, active }

extension InventoryListFilterX on InventoryListFilter {
  String get label {
    return switch (this) {
      InventoryListFilter.all => 'Todos',
      InventoryListFilter.belowMinimum => 'Abaixo do minimo',
      InventoryListFilter.zeroed => 'Zerados',
      InventoryListFilter.active => 'Ativos',
    };
  }
}

enum InventoryItemStatus { available, belowMinimum, zeroed, inactive }

extension InventoryItemStatusX on InventoryItemStatus {
  String get label {
    return switch (this) {
      InventoryItemStatus.available => 'Disponivel',
      InventoryItemStatus.belowMinimum => 'Abaixo do minimo',
      InventoryItemStatus.zeroed => 'Zerado',
      InventoryItemStatus.inactive => 'Inativo',
    };
  }
}

class InventoryItem {
  const InventoryItem({
    required this.productId,
    required this.productVariantId,
    required this.productName,
    required this.sku,
    required this.variantColorLabel,
    required this.variantSizeLabel,
    required this.unitMeasure,
    required this.currentStockMil,
    required this.minimumStockMil,
    required this.reorderPointMil,
    required this.allowNegativeStock,
    required this.costCents,
    required this.salePriceCents,
    required this.isActive,
    required this.updatedAt,
  });

  final int productId;
  final int? productVariantId;
  final String productName;
  final String? sku;
  final String? variantColorLabel;
  final String? variantSizeLabel;
  final String unitMeasure;
  final int currentStockMil;
  final int minimumStockMil;
  final int? reorderPointMil;
  final bool allowNegativeStock;
  final int costCents;
  final int salePriceCents;
  final bool isActive;
  final DateTime updatedAt;

  bool get hasVariant => productVariantId != null;

  bool get hasConfiguredMinimum => minimumStockMil > 0;

  bool get isZeroed => currentStockMil <= 0;

  bool get isBelowMinimum =>
      hasConfiguredMinimum && currentStockMil < minimumStockMil;

  InventoryItemStatus get status {
    if (!isActive) {
      return InventoryItemStatus.inactive;
    }
    if (isZeroed) {
      return InventoryItemStatus.zeroed;
    }
    if (isBelowMinimum) {
      return InventoryItemStatus.belowMinimum;
    }
    return InventoryItemStatus.available;
  }

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

  String get selectorLabel {
    final summary = variantSummary;
    final skuPart = (sku ?? '').trim().isEmpty ? '' : ' | SKU ${sku!.trim()}';
    if (summary == null) {
      return '$productName$skuPart';
    }
    return '$productName - $summary$skuPart';
  }

  int get estimatedCostCents => ((currentStockMil * costCents) / 1000).round();
}
