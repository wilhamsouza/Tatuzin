import '../domain/entities/inventory_count_item.dart';
import '../domain/entities/inventory_count_item_input.dart';
import '../domain/entities/inventory_count_session.dart';
import '../domain/entities/inventory_count_session_detail.dart';
import '../domain/repositories/inventory_count_repository.dart';
import 'sqlite_inventory_count_repository.dart';

class InventoryCountRepositoryImpl implements InventoryCountRepository {
  const InventoryCountRepositoryImpl({
    required SqliteInventoryCountRepository localRepository,
  }) : _localRepository = localRepository;

  final SqliteInventoryCountRepository _localRepository;

  @override
  Future<InventoryCountSession> createSession({required String name}) {
    return _localRepository.createSession(name: name);
  }

  @override
  Future<InventoryCountSessionDetail?> getSessionDetail(int sessionId) {
    return _localRepository.getSessionDetail(sessionId);
  }

  @override
  Future<List<InventoryCountSession>> listSessions() {
    return _localRepository.listSessions();
  }

  @override
  Future<void> applySession(int sessionId) {
    return _localRepository.applySession(sessionId);
  }

  @override
  Future<InventoryCountItem> keepRecordedDifference(int countItemId) {
    return _localRepository.keepRecordedDifference(countItemId);
  }

  @override
  Future<void> markSessionReviewed(int sessionId) {
    return _localRepository.markSessionReviewed(sessionId);
  }

  @override
  Future<InventoryCountItem> recalculateItemFromCurrentStock(int countItemId) {
    return _localRepository.recalculateItemFromCurrentStock(countItemId);
  }

  @override
  Future<InventoryCountItem> upsertItem(InventoryCountItemInput input) {
    return _localRepository.upsertItem(input);
  }
}
