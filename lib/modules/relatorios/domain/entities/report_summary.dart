import 'report_payment_summary.dart';
import 'report_period.dart';
import 'report_sold_product_summary.dart';

class ReportSummary {
  const ReportSummary({
    required this.period,
    required this.range,
    required this.totalSalesCents,
    required this.totalReceivedCents,
    required this.costOfGoodsSoldCents,
    required this.realizedProfitCents,
    required this.salesCount,
    required this.pendingFiadoCents,
    required this.pendingFiadoCount,
    required this.cancelledSalesCount,
    required this.cancelledSalesCents,
    required this.totalPurchasedCents,
    required this.totalPurchasePaymentsCents,
    required this.totalPurchasePendingCents,
    required this.cashSalesReceivedCents,
    required this.fiadoReceiptsCents,
    required this.paymentSummaries,
    required this.soldProducts,
  });

  final ReportPeriod period;
  final ReportDateRange range;
  final int totalSalesCents;
  final int totalReceivedCents;
  final int costOfGoodsSoldCents;
  final int realizedProfitCents;
  final int salesCount;
  final int pendingFiadoCents;
  final int pendingFiadoCount;
  final int cancelledSalesCount;
  final int cancelledSalesCents;
  final int totalPurchasedCents;
  final int totalPurchasePaymentsCents;
  final int totalPurchasePendingCents;
  final int cashSalesReceivedCents;
  final int fiadoReceiptsCents;
  final List<ReportPaymentSummary> paymentSummaries;
  final List<ReportSoldProductSummary> soldProducts;
}
