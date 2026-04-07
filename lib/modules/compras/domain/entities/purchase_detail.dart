import 'purchase.dart';
import 'purchase_item.dart';
import 'purchase_payment.dart';

class PurchaseDetail {
  const PurchaseDetail({
    required this.purchase,
    required this.items,
    required this.payments,
  });

  final Purchase purchase;
  final List<PurchaseItem> items;
  final List<PurchasePayment> payments;
}
