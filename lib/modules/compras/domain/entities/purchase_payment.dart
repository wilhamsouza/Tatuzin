import '../../../vendas/domain/entities/sale_enums.dart';

class PurchasePayment {
  const PurchasePayment({
    required this.id,
    required this.uuid,
    required this.purchaseId,
    required this.amountCents,
    required this.paymentMethod,
    required this.createdAt,
    required this.notes,
    required this.cashMovementId,
  });

  final int id;
  final String uuid;
  final int purchaseId;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final DateTime createdAt;
  final String? notes;
  final int? cashMovementId;
}

class PurchasePaymentInput {
  const PurchasePaymentInput({
    required this.purchaseId,
    required this.amountCents,
    required this.paymentMethod,
    this.paymentUuid,
    this.notes,
  });

  final int purchaseId;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final String? paymentUuid;
  final String? notes;
}
