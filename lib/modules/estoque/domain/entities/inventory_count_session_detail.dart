import 'inventory_count_item.dart';
import 'inventory_count_session.dart';
import 'inventory_count_summary.dart';

class InventoryCountSessionDetail {
  const InventoryCountSessionDetail({
    required this.session,
    required this.items,
    required this.summary,
  });

  final InventoryCountSession session;
  final List<InventoryCountItem> items;
  final InventoryCountSummary summary;
}
