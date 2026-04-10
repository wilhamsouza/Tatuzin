import 'cash_enums.dart';

class CashSession {
  const CashSession({
    required this.id,
    required this.uuid,
    required this.userId,
    required this.operatorName,
    required this.openedAt,
    required this.closedAt,
    required this.initialFloatCents,
    required this.awaitingInitialFloatConfirmation,
    required this.cashEntriesCents,
    required this.withdrawalsCents,
    required this.suppliesCents,
    required this.fiadoReceiptsCashCents,
    required this.fiadoReceiptsPixCents,
    required this.fiadoReceiptsCardCents,
    required this.expectedBalanceCents,
    required this.countedBalanceCents,
    required this.differenceCents,
    required this.status,
    required this.notes,
  });

  final int id;
  final String uuid;
  final int? userId;
  final String operatorName;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int initialFloatCents;
  final bool awaitingInitialFloatConfirmation;
  final int cashEntriesCents;
  final int withdrawalsCents;
  final int suppliesCents;
  final int fiadoReceiptsCashCents;
  final int fiadoReceiptsPixCents;
  final int fiadoReceiptsCardCents;
  final int expectedBalanceCents;
  final int? countedBalanceCents;
  final int? differenceCents;
  final CashSessionStatus status;
  final String? notes;

  bool get isOpen => status == CashSessionStatus.open;

  int get totalSuppliesCents => suppliesCents;

  int get totalWithdrawalsCents => withdrawalsCents;

  int get totalSalesCents => cashEntriesCents;

  int get totalFiadoReceiptsCents =>
      fiadoReceiptsCashCents + fiadoReceiptsPixCents + fiadoReceiptsCardCents;

  int get finalBalanceCents => expectedBalanceCents;

  int get physicalBalanceCents => expectedBalanceCents;

  bool get hasBalanceDifference => (differenceCents ?? 0) != 0;
}
