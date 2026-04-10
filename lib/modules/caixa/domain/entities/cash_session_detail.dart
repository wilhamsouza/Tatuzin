import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_record.dart';
import 'cash_movement.dart';
import 'cash_session.dart';

class CashSessionDetail {
  const CashSessionDetail({
    required this.session,
    required this.periodEnd,
    required this.movements,
    required this.sales,
    required this.totalSoldCents,
    required this.totalEntriesCents,
    required this.totalOutflowsCents,
    required this.totalCashSalesReceivedCents,
    required this.totalFiadoReceiptsCashCents,
    required this.totalFiadoReceiptsPixCents,
    required this.totalFiadoReceiptsCardCents,
    required this.totalManualEntriesCents,
    required this.totalManualWithdrawalsCents,
    required this.countedAmountCents,
    required this.reportedBalanceCents,
    required this.differenceCents,
  });

  final CashSession session;
  final DateTime periodEnd;
  final List<CashSessionMovementDetail> movements;
  final List<CashSessionSaleSummary> sales;
  final int totalSoldCents;
  final int totalEntriesCents;
  final int totalOutflowsCents;
  final int totalCashSalesReceivedCents;
  final int totalFiadoReceiptsCashCents;
  final int totalFiadoReceiptsPixCents;
  final int totalFiadoReceiptsCardCents;
  final int totalManualEntriesCents;
  final int totalManualWithdrawalsCents;
  final int? countedAmountCents;
  final int? reportedBalanceCents;
  final int? differenceCents;

  int get totalFiadoReceiptsCents =>
      totalFiadoReceiptsCashCents +
      totalFiadoReceiptsPixCents +
      totalFiadoReceiptsCardCents;

  int get amountToZeroCents => session.finalBalanceCents.abs();

  bool get isAboveZero => session.finalBalanceCents > 0;

  bool get isBelowZero => session.finalBalanceCents < 0;

  bool get isZeroed => session.finalBalanceCents == 0;
}

class CashSessionMovementDetail {
  const CashSessionMovementDetail({
    required this.movement,
    required this.originLabel,
    required this.referenceLabel,
    required this.clientName,
    required this.receiptNumber,
    required this.saleType,
    required this.salePaymentMethod,
    required this.saleStatus,
  });

  final CashMovement movement;
  final String originLabel;
  final String? referenceLabel;
  final String? clientName;
  final String? receiptNumber;
  final SaleType? saleType;
  final PaymentMethod? salePaymentMethod;
  final SaleStatus? saleStatus;
}

class CashSessionSaleSummary {
  const CashSessionSaleSummary({
    required this.sale,
    required this.itemLinesCount,
    required this.itemPreview,
  });

  final SaleRecord sale;
  final int itemLinesCount;
  final List<CashSessionSaleItemPreview> itemPreview;
}

class CashSessionSaleItemPreview {
  const CashSessionSaleItemPreview({
    required this.productName,
    required this.quantityMil,
    required this.unitMeasure,
  });

  final String productName;
  final int quantityMil;
  final String unitMeasure;
}
