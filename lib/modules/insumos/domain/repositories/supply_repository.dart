import '../entities/supply.dart';
import '../entities/supply_cost_history_entry.dart';
import '../entities/supply_inventory.dart';

abstract interface class SupplyRepository {
  Future<List<Supply>> search({String query = '', bool activeOnly = false});
  Future<Supply?> findById(int id);
  Future<List<SupplyInventoryOverview>> listInventoryOverview({
    String query = '',
  });
  Future<List<SupplyInventoryMovement>> listInventoryMovements({
    int? supplyId,
    SupplyInventorySourceType? sourceType,
    DateTime? occurredFrom,
    DateTime? occurredTo,
    int limit = 200,
  });
  Future<List<SupplyReorderSuggestion>> listReorderSuggestions({
    String query = '',
    SupplyReorderFilter filter = SupplyReorderFilter.all,
  });
  Future<SupplyInventoryConsistencyReport> verifyInventoryConsistency({
    Iterable<int>? supplyIds,
    bool repair = true,
  });
  Future<List<SupplyCostHistoryEntry>> listCostHistory({
    required int supplyId,
    int limit = 20,
  });
  Future<int> create(SupplyInput input);
  Future<void> update(int id, SupplyInput input);
  Future<void> deactivate(int id);
}
