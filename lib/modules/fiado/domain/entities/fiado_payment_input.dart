import '../../../vendas/domain/entities/sale_enums.dart';

class FiadoPaymentInput {
  const FiadoPaymentInput({
    required this.fiadoId,
    required this.amountCents,
    required this.paymentMethod,
    this.notes,
  });

  final int fiadoId;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final String? notes;
}
