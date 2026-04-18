import 'report_breakdown_row.dart';
import 'report_filter.dart';

class ReportPurchaseSummary {
  const ReportPurchaseSummary({
    required this.filter,
    required this.purchasesCount,
    required this.totalPurchasedCents,
    required this.totalPendingCents,
    required this.totalPaidCents,
    required this.supplierRows,
    required this.topItems,
    required this.replenishmentRows,
  });

  final ReportFilter filter;
  final int purchasesCount;
  final int totalPurchasedCents;
  final int totalPendingCents;
  final int totalPaidCents;
  final List<ReportBreakdownRow> supplierRows;
  final List<ReportBreakdownRow> topItems;
  final List<ReportBreakdownRow> replenishmentRows;
}
