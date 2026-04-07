import '../../../vendas/domain/entities/sale_enums.dart';
import 'cash_enums.dart';

class CashMovement {
  const CashMovement({
    required this.id,
    required this.uuid,
    required this.sessionId,
    required this.type,
    required this.referenceType,
    required this.referenceId,
    required this.amountCents,
    required this.description,
    required this.createdAt,
    this.paymentMethod,
  });

  final int id;
  final String uuid;
  final int sessionId;
  final CashMovementType type;
  final String? referenceType;
  final int? referenceId;
  final int amountCents;
  final String? description;
  final DateTime createdAt;
  final PaymentMethod? paymentMethod;
}
