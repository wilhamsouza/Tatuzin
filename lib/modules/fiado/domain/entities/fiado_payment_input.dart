import '../../../vendas/domain/entities/sale_enums.dart';

class FiadoPaymentInput {
  const FiadoPaymentInput({
    required this.fiadoId,
    required this.amountCents,
    required this.paymentMethod,
    this.notes,
    this.convertOverpaymentToCredit = false,
  });

  final int fiadoId;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final String? notes;
  final bool convertOverpaymentToCredit;
}
