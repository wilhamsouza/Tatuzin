import '../domain/entities/inventory_adjustment_input.dart';
import '../domain/entities/inventory_item.dart';
import '../domain/entities/inventory_movement.dart';
import '../domain/repositories/inventory_repository.dart';
import 'sqlite_inventory_repository.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  const InventoryRepositoryImpl({
    required SqliteInventoryRepository localRepository,
  }) : _localRepository = localRepository;

  final SqliteInventoryRepository _localRepository;

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) {
    return _localRepository.adjustStock(input);
  }

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) {
    return _localRepository.findItem(
      productId: productId,
      productVariantId: productVariantId,
    );
  }

  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) {
    return _localRepository.listItems(query: query, filter: filter);
  }

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) {
    return _localRepository.listMovements(
      productId: productId,
      productVariantId: productVariantId,
      includeVariantsForProduct: includeVariantsForProduct,
      movementType: movementType,
      createdFrom: createdFrom,
      createdTo: createdTo,
      limit: limit,
    );
  }
}
