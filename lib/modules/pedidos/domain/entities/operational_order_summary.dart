import 'operational_order.dart';

class OperationalOrderSummary {
  const OperationalOrderSummary({
    required this.order,
    required this.lineItemsCount,
    required this.totalUnits,
    required this.totalCents,
    required this.linkedSaleId,
  });

  final OperationalOrder order;
  final int lineItemsCount;
  final int totalUnits;
  final int totalCents;
  final int? linkedSaleId;

  bool get hasLinkedSale => linkedSaleId != null;
}
