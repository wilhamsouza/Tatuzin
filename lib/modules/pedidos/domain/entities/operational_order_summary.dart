import 'operational_order.dart';

class OperationalOrderSummary {
  const OperationalOrderSummary({
    required this.order,
    required this.lineItemsCount,
    required this.totalUnits,
    required this.totalCents,
  });

  final OperationalOrder order;
  final int lineItemsCount;
  final int totalUnits;
  final int totalCents;
}
