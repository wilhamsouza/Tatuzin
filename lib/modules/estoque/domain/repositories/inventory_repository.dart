import '../entities/inventory_adjustment_input.dart';
import '../entities/inventory_item.dart';
import '../entities/inventory_movement.dart';

abstract interface class InventoryRepository {
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  });

  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  });

  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  });

  Future<void> adjustStock(InventoryAdjustmentInput input);
}
