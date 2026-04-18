import '../entities/inventory_count_item.dart';
import '../entities/inventory_count_item_input.dart';
import '../entities/inventory_count_session.dart';
import '../entities/inventory_count_session_detail.dart';

abstract interface class InventoryCountRepository {
  Future<List<InventoryCountSession>> listSessions();

  Future<InventoryCountSession> createSession({required String name});

  Future<InventoryCountSessionDetail?> getSessionDetail(int sessionId);

  Future<InventoryCountItem> upsertItem(InventoryCountItemInput input);

  Future<InventoryCountItem> recalculateItemFromCurrentStock(int countItemId);

  Future<InventoryCountItem> keepRecordedDifference(int countItemId);

  Future<void> markSessionReviewed(int sessionId);

  Future<void> applySession(int sessionId);
}
