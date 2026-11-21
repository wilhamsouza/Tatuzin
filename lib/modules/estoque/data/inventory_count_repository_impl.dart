import '../../../app/core/errors/app_exceptions.dart';
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
    throw const ValidationException(
      'Use Estoque → Contagens. Sessões antigas são somente leitura.',
    );
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
    throw const ValidationException(
      'Uma contagem antiga não pode ser reaplicada. Use Estoque → Contagens.',
    );
  }

  @override
  Future<InventoryCountItem> keepRecordedDifference(int countItemId) {
    throw const ValidationException(
      'O histórico de contagens antigas é somente leitura.',
    );
  }

  @override
  Future<void> markSessionReviewed(int sessionId) {
    throw const ValidationException(
      'O histórico de contagens antigas é somente leitura.',
    );
  }

  @override
  Future<InventoryCountItem> recalculateItemFromCurrentStock(int countItemId) {
    throw const ValidationException(
      'O histórico de contagens antigas é somente leitura.',
    );
  }

  @override
  Future<InventoryCountItem> upsertItem(InventoryCountItemInput input) {
    throw const ValidationException(
      'O histórico de contagens antigas é somente leitura.',
    );
  }
}
