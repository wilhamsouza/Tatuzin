import '../entities/order_ticket_document.dart';
import '../entities/operational_order_detail.dart';

abstract interface class OrderTicketBuilder {
  OrderTicketDocument build({
    required OperationalOrderDetail detail,
    required OrderTicketProfile profile,
  });
}
