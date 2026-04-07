import '../../../vendas/domain/entities/sale_enums.dart';

class FiadoPaymentEntry {
  const FiadoPaymentEntry({
    required this.id,
    required this.uuid,
    required this.fiadoId,
    required this.clientId,
    required this.entryType,
    required this.amountCents,
    required this.registeredAt,
    required this.notes,
    required this.cashMovementId,
    required this.paymentMethod,
  });

  final int id;
  final String uuid;
  final int fiadoId;
  final int clientId;
  final String entryType;
  final int amountCents;
  final DateTime registeredAt;
  final String? notes;
  final int? cashMovementId;
  final PaymentMethod? paymentMethod;
}
