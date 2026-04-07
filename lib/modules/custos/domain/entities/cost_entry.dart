import '../../../vendas/domain/entities/sale_enums.dart';
import 'cost_status.dart';
import 'cost_type.dart';

class CostEntry {
  const CostEntry({
    required this.id,
    required this.uuid,
    required this.remoteId,
    required this.description,
    required this.type,
    required this.category,
    required this.amountCents,
    required this.referenceDate,
    required this.paidAt,
    required this.paymentMethod,
    required this.notes,
    required this.isRecurring,
    required this.status,
    required this.cashMovementId,
    required this.createdAt,
    required this.updatedAt,
    required this.canceledAt,
  });

  final int id;
  final String uuid;
  final String? remoteId;
  final String description;
  final CostType type;
  final String? category;
  final int amountCents;
  final DateTime referenceDate;
  final DateTime? paidAt;
  final PaymentMethod? paymentMethod;
  final String? notes;
  final bool isRecurring;
  final CostStatus status;
  final int? cashMovementId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? canceledAt;

  bool get isPending => status == CostStatus.pending;

  bool get isPaid => status == CostStatus.paid;

  bool get isCanceled => status == CostStatus.canceled;

  int get openAmountCents => isPending ? amountCents : 0;

  bool isOverdueAt(DateTime moment) {
    if (!isPending) {
      return false;
    }

    final reference = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final current = DateTime(moment.year, moment.month, moment.day);
    return reference.isBefore(current);
  }
}
