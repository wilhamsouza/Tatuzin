import '../models/remote_inventory_item.dart';

abstract interface class InventoryRemoteDatasource {
  Future<List<RemoteInventoryItem>> listItems({
    String query = '',
    String filter = 'all',
  });

  Future<RemoteInventorySummary> fetchSummary();
}
