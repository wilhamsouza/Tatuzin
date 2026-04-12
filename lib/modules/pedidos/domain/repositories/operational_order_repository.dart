import '../entities/operational_order.dart';
import '../entities/operational_order_item.dart';
import '../entities/operational_order_item_modifier.dart';
import '../entities/operational_order_summary.dart';

abstract interface class OperationalOrderRepository {
  Future<int> create(OperationalOrderInput input);

  Future<List<OperationalOrder>> list({String query = ''});

  Future<List<OperationalOrderSummary>> listSummaries({
    String query = '',
    OperationalOrderStatus? status,
  });

  Future<OperationalOrder?> findById(int orderId);

  Future<List<OperationalOrderItem>> listItems(int orderId);

  Future<List<OperationalOrderItemModifier>> listItemModifiers(int orderItemId);

  Future<int?> findLinkedSaleId(int orderId);

  Future<void> linkToSale({required int orderId, required int saleId});

  Future<void> updateStatus(int orderId, OperationalOrderStatus status);

  Future<int> addItem(int orderId, OperationalOrderItemInput input);

  Future<int> addItemModifier(
    int orderItemId,
    OperationalOrderItemModifierInput input,
  );
}
