import 'sale_enums.dart';

class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.uuid,
    required this.receiptNumber,
    required this.saleType,
    required this.paymentMethod,
    required this.status,
    required this.totalCents,
    required this.finalCents,
    required this.discountCents,
    required this.surchargeCents,
    required this.soldAt,
    required this.clientId,
    required this.clientName,
    required this.notes,
    required this.cancelledAt,
    required this.fiadoId,
    required this.fiadoStatus,
    required this.fiadoOpenCents,
    required this.fiadoDueDate,
  });

  final int id;
  final String uuid;
  final String receiptNumber;
  final SaleType saleType;
  final PaymentMethod paymentMethod;
  final SaleStatus status;
  final int totalCents;
  final int finalCents;
  final int discountCents;
  final int surchargeCents;
  final DateTime soldAt;
  final int? clientId;
  final String? clientName;
  final String? notes;
  final DateTime? cancelledAt;
  final int? fiadoId;
  final String? fiadoStatus;
  final int? fiadoOpenCents;
  final DateTime? fiadoDueDate;
}
