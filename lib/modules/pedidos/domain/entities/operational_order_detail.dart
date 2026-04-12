import 'operational_order.dart';
import 'operational_order_item.dart';
import 'operational_order_item_modifier.dart';

class OperationalOrderItemDetail {
  const OperationalOrderItemDetail({
    required this.item,
    required this.modifiers,
  });

  final OperationalOrderItem item;
  final List<OperationalOrderItemModifier> modifiers;

  int get modifierDeltaCents => modifiers.fold<int>(
    0,
    (sum, modifier) => sum + (modifier.priceDeltaCents * modifier.quantity),
  );

  int get totalCents =>
      item.subtotalCents + (modifierDeltaCents * (item.quantityMil ~/ 1000));

  int get quantityUnits => item.quantityMil ~/ 1000;
}

class OperationalOrderDetail {
  const OperationalOrderDetail({
    required this.order,
    required this.items,
    required this.linkedSaleId,
  });

  final OperationalOrder order;
  final List<OperationalOrderItemDetail> items;
  final int? linkedSaleId;

  int get lineItemsCount => items.length;

  int get totalUnits =>
      items.fold<int>(0, (sum, item) => sum + item.quantityUnits);

  int get totalCents =>
      items.fold<int>(0, (sum, item) => sum + item.totalCents);
}
