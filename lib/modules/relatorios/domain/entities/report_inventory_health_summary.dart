import '../../../estoque/domain/entities/inventory_item.dart';
import '../../../estoque/domain/entities/inventory_movement.dart';
import 'report_breakdown_row.dart';
import 'report_filter.dart';

class ReportInventoryHealthSummary {
  const ReportInventoryHealthSummary({
    required this.filter,
    required this.totalItemsCount,
    required this.zeroedItemsCount,
    required this.belowMinimumItemsCount,
    required this.belowMinimumOnlyItemsCount,
    required this.divergenceItemsCount,
    required this.inventoryCostValueCents,
    required this.inventorySaleValueCents,
    required this.criticalItems,
    required this.mostMovedItems,
    required this.recentMovements,
  });

  final ReportFilter filter;
  final int totalItemsCount;
  final int zeroedItemsCount;
  final int belowMinimumItemsCount;
  final int belowMinimumOnlyItemsCount;
  final int divergenceItemsCount;
  final int inventoryCostValueCents;
  final int inventorySaleValueCents;
  final List<InventoryItem> criticalItems;
  final List<ReportBreakdownRow> mostMovedItems;
  final List<InventoryMovement> recentMovements;

  int get healthyItemsCount {
    final totalAlerts = zeroedItemsCount + belowMinimumOnlyItemsCount;
    final healthy = totalItemsCount - totalAlerts;
    if (healthy < 0) {
      return 0;
    }
    return healthy;
  }

  int get alertItemsCount => zeroedItemsCount + belowMinimumOnlyItemsCount;
}
