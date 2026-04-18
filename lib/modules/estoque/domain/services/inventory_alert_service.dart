import '../entities/inventory_item.dart';
import '../entities/inventory_summary.dart';

abstract final class InventoryAlertService {
  static List<InventoryItem> applyFilter(
    Iterable<InventoryItem> items, {
    required InventoryListFilter filter,
  }) {
    final filtered = items
        .where((item) => _matchesFilter(item, filter))
        .toList(growable: false);
    filtered.sort(_compareItems);
    return filtered;
  }

  static InventorySummary summarize(Iterable<InventoryItem> items) {
    final normalized = items.toList(growable: false);
    return InventorySummary(
      totalSkus: normalized.length,
      zeroedItems: normalized.where((item) => item.isZeroed).length,
      belowMinimumItems: normalized.where((item) => item.isBelowMinimum).length,
      estimatedCostCents: normalized.fold<int>(
        0,
        (total, item) => total + item.estimatedCostCents,
      ),
    );
  }

  static bool _matchesFilter(InventoryItem item, InventoryListFilter filter) {
    return switch (filter) {
      InventoryListFilter.all => true,
      InventoryListFilter.belowMinimum => item.isActive && item.isBelowMinimum,
      InventoryListFilter.zeroed => item.isZeroed,
      InventoryListFilter.active => item.isActive,
    };
  }

  static int _compareItems(InventoryItem left, InventoryItem right) {
    final statusDiff = _statusRank(
      left.status,
    ).compareTo(_statusRank(right.status));
    if (statusDiff != 0) {
      return statusDiff;
    }

    final byName = left.productName.toLowerCase().compareTo(
      right.productName.toLowerCase(),
    );
    if (byName != 0) {
      return byName;
    }

    final leftVariant = (left.variantSummary ?? '').toLowerCase();
    final rightVariant = (right.variantSummary ?? '').toLowerCase();
    if (leftVariant != rightVariant) {
      return leftVariant.compareTo(rightVariant);
    }

    return (left.sku ?? '').toLowerCase().compareTo(
      (right.sku ?? '').toLowerCase(),
    );
  }

  static int _statusRank(InventoryItemStatus status) {
    return switch (status) {
      InventoryItemStatus.zeroed => 0,
      InventoryItemStatus.belowMinimum => 1,
      InventoryItemStatus.available => 2,
      InventoryItemStatus.inactive => 3,
    };
  }
}
