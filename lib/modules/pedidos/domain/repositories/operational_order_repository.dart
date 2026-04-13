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

  Future<void> updateDraft(int orderId, OperationalOrderDraftInput input);

  Future<void> sendToKitchen(int orderId);

  Future<void> updateStatus(int orderId, OperationalOrderStatus status);

  Future<void> updateTicketDispatchState({
    required int orderId,
    required OrderTicketDispatchStatus status,
    String? failureMessage,
  });

  Future<int> addItem(int orderId, OperationalOrderItemInput input);

  Future<void> updateItem(int orderItemId, OperationalOrderItemInput input);

  Future<void> removeItem(int orderItemId);

  Future<int> addItemModifier(
    int orderItemId,
    OperationalOrderItemModifierInput input,
  );

  Future<void> replaceItemModifiers(
    int orderItemId,
    List<OperationalOrderItemModifierInput> modifiers,
  );
}
