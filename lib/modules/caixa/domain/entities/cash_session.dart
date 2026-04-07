import 'cash_enums.dart';

class CashSession {
  const CashSession({
    required this.id,
    required this.uuid,
    required this.userId,
    required this.openedAt,
    required this.closedAt,
    required this.initialFloatCents,
    required this.totalSuppliesCents,
    required this.totalWithdrawalsCents,
    required this.totalSalesCents,
    required this.totalFiadoReceiptsCents,
    required this.finalBalanceCents,
    required this.status,
    required this.notes,
  });

  final int id;
  final String uuid;
  final int? userId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int initialFloatCents;
  final int totalSuppliesCents;
  final int totalWithdrawalsCents;
  final int totalSalesCents;
  final int totalFiadoReceiptsCents;
  final int finalBalanceCents;
  final CashSessionStatus status;
  final String? notes;

  bool get isOpen => status == CashSessionStatus.open;
}
