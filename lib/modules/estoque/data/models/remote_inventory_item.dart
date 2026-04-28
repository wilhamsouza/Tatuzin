import '../../domain/entities/inventory_item.dart';

class RemoteInventoryItem {
  const RemoteInventoryItem({
    required this.productId,
    required this.productVariantId,
    required this.name,
    required this.variantName,
    required this.sku,
    required this.unitMeasure,
    required this.currentStockMil,
    required this.minimumStockMil,
    required this.costPriceCents,
    required this.salePriceCents,
    required this.status,
  });

  final String productId;
  final String? productVariantId;
  final String name;
  final String? variantName;
  final String? sku;
  final String unitMeasure;
  final int currentStockMil;
  final int minimumStockMil;
  final int costPriceCents;
  final int salePriceCents;
  final String status;

  factory RemoteInventoryItem.fromJson(Map<String, dynamic> json) {
    return RemoteInventoryItem(
      productId: json['productId'] as String? ?? '',
      productVariantId: json['productVariantId'] as String?,
      name: json['name'] as String? ?? 'Produto',
      variantName: json['variantName'] as String?,
      sku: json['sku'] as String?,
      unitMeasure: json['unitMeasure'] as String? ?? 'un',
      currentStockMil: _readInt(json['currentStockMil']),
      minimumStockMil: _readInt(json['minimumStockMil']),
      costPriceCents: _readInt(json['costPriceCents']),
      salePriceCents: _readInt(json['salePriceCents']),
      status: json['status'] as String? ?? 'active',
    );
  }

  InventoryItem toInventoryItem() {
    final parts = (variantName ?? '').split(' / ');
    return InventoryItem(
      productId: _stableNegativeId(productId),
      productVariantId: productVariantId == null
          ? null
          : _stableNegativeId(productVariantId!),
      productName: name,
      sku: sku,
      variantColorLabel: parts.isNotEmpty ? parts.first : null,
      variantSizeLabel: parts.length > 1 ? parts.sublist(1).join(' / ') : null,
      unitMeasure: unitMeasure,
      currentStockMil: currentStockMil,
      minimumStockMil: minimumStockMil,
      reorderPointMil: null,
      allowNegativeStock: false,
      costCents: costPriceCents,
      salePriceCents: salePriceCents,
      isActive: status != 'inactive',
      updatedAt: DateTime.now(),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static int _stableNegativeId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash == 0 ? -1 : -hash.abs();
  }
}

class RemoteInventorySummary {
  const RemoteInventorySummary({
    required this.totalItemsCount,
    required this.activeItemsCount,
    required this.zeroedItemsCount,
    required this.belowMinimumItemsCount,
    required this.inventoryCostValueCents,
    required this.inventorySaleValueCents,
    required this.divergenceItemsCount,
  });

  final int totalItemsCount;
  final int activeItemsCount;
  final int zeroedItemsCount;
  final int belowMinimumItemsCount;
  final int inventoryCostValueCents;
  final int inventorySaleValueCents;
  final int divergenceItemsCount;

  factory RemoteInventorySummary.fromJson(Map<String, dynamic> json) {
    return RemoteInventorySummary(
      totalItemsCount: RemoteInventoryItem._readInt(json['totalItemsCount']),
      activeItemsCount: RemoteInventoryItem._readInt(json['activeItemsCount']),
      zeroedItemsCount: RemoteInventoryItem._readInt(json['zeroedItemsCount']),
      belowMinimumItemsCount: RemoteInventoryItem._readInt(
        json['belowMinimumItemsCount'],
      ),
      inventoryCostValueCents: RemoteInventoryItem._readInt(
        json['inventoryCostValueCents'],
      ),
      inventorySaleValueCents: RemoteInventoryItem._readInt(
        json['inventorySaleValueCents'],
      ),
      divergenceItemsCount: RemoteInventoryItem._readInt(
        json['divergenceItemsCount'],
      ),
    );
  }
}
