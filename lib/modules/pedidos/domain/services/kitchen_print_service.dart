import '../entities/kitchen_printer_config.dart';
import '../entities/order_ticket_document.dart';

abstract interface class KitchenPrintService {
  Future<void> print({
    required KitchenPrinterConfig printer,
    required OrderTicketDocument ticket,
  });

  Future<void> printTest({required KitchenPrinterConfig printer});
}
