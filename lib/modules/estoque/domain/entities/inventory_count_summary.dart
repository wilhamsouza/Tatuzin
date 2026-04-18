import 'inventory_count_item.dart';

class InventoryCountSummary {
  const InventoryCountSummary({
    required this.totalItems,
    required this.itemsWithDifference,
    required this.staleItems,
    required this.readyItems,
    required this.surplusMil,
    required this.shortageMil,
  });

  final int totalItems;
  final int itemsWithDifference;
  final int staleItems;
  final int readyItems;
  final int surplusMil;
  final int shortageMil;

  factory InventoryCountSummary.fromItems(List<InventoryCountItem> items) {
    var itemsWithDifference = 0;
    var staleItems = 0;
    var readyItems = 0;
    var surplusMil = 0;
    var shortageMil = 0;

    for (final item in items) {
      if (item.isStale) {
        staleItems++;
      }
      if (item.readyToApply) {
        readyItems++;
      }
      if (!item.hasDifference) {
        continue;
      }
      itemsWithDifference++;
      if (item.differenceMil > 0) {
        surplusMil += item.differenceMil;
      } else {
        shortageMil += item.differenceMil.abs();
      }
    }

    return InventoryCountSummary(
      totalItems: items.length,
      itemsWithDifference: itemsWithDifference,
      staleItems: staleItems,
      readyItems: readyItems,
      surplusMil: surplusMil,
      shortageMil: shortageMil,
    );
  }
}
