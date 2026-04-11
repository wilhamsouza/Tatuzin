import '../../../carrinho/domain/entities/cart_item.dart';
import 'sale_enums.dart';

class CheckoutInput {
  const CheckoutInput({
    required this.items,
    required this.saleType,
    required this.paymentMethod,
    this.operationalOrderId,
    this.clientId,
    this.dueDate,
    this.notes,
    this.discountCents = 0,
    this.surchargeCents = 0,
    this.customerCreditUsedCents = 0,
    this.changeLeftAsCreditCents = 0,
  });

  final List<CartItem> items;
  final SaleType saleType;
  final PaymentMethod paymentMethod;
  final int? operationalOrderId;
  final int? clientId;
  final DateTime? dueDate;
  final String? notes;
  final int discountCents;
  final int surchargeCents;
  final int customerCreditUsedCents;
  final int changeLeftAsCreditCents;

  int get itemsTotalCents =>
      items.fold<int>(0, (sum, item) => sum + item.subtotalCents);

  int get finalTotalCents => itemsTotalCents - discountCents + surchargeCents;

  int get immediateAmountDueCents {
    final due = finalTotalCents - customerCreditUsedCents;
    return due < 0 ? 0 : due;
  }

  int get immediateReceivedCents =>
      immediateAmountDueCents + changeLeftAsCreditCents;
}
