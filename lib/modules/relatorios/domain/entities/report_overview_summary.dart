import 'report_customer_credit_summary.dart';
import 'report_filter.dart';
import 'report_payment_summary.dart';

class ReportOverviewSummary {
  const ReportOverviewSummary({
    required this.filter,
    required this.grossSalesCents,
    required this.netSalesCents,
    required this.totalReceivedCents,
    required this.costOfGoodsSoldCents,
    required this.realizedProfitCents,
    required this.salesCount,
    required this.totalDiscountCents,
    required this.totalSurchargeCents,
    required this.pendingFiadoCents,
    required this.pendingFiadoCount,
    required this.cancelledSalesCount,
    required this.cancelledSalesCents,
    required this.totalPurchasedCents,
    required this.totalPurchasePaymentsCents,
    required this.totalPurchasePendingCents,
    required this.cashSalesReceivedCents,
    required this.fiadoReceiptsCents,
    required this.totalCreditGeneratedCents,
    required this.totalCreditUsedCents,
    required this.totalOutstandingCreditCents,
    required this.topCreditCustomers,
    required this.paymentSummaries,
  });

  final ReportFilter filter;
  final int grossSalesCents;
  final int netSalesCents;
  final int totalReceivedCents;
  final int costOfGoodsSoldCents;
  final int realizedProfitCents;
  final int salesCount;
  final int totalDiscountCents;
  final int totalSurchargeCents;
  final int pendingFiadoCents;
  final int pendingFiadoCount;
  final int cancelledSalesCount;
  final int cancelledSalesCents;
  final int totalPurchasedCents;
  final int totalPurchasePaymentsCents;
  final int totalPurchasePendingCents;
  final int cashSalesReceivedCents;
  final int fiadoReceiptsCents;
  final int totalCreditGeneratedCents;
  final int totalCreditUsedCents;
  final int totalOutstandingCreditCents;
  final List<ReportCustomerCreditSummary> topCreditCustomers;
  final List<ReportPaymentSummary> paymentSummaries;

  int get averageTicketCents {
    if (salesCount <= 0) {
      return 0;
    }
    return (netSalesCents / salesCount).round();
  }
}
