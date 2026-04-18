import 'report_breakdown_row.dart';
import 'report_cashflow_point.dart';
import 'report_filter.dart';

class ReportCashflowSummary {
  const ReportCashflowSummary({
    required this.filter,
    required this.totalReceivedCents,
    required this.fiadoReceiptsCents,
    required this.manualEntriesCents,
    required this.outflowsCents,
    required this.withdrawalsCents,
    required this.netFlowCents,
    required this.movementRows,
    required this.timeline,
  });

  final ReportFilter filter;
  final int totalReceivedCents;
  final int fiadoReceiptsCents;
  final int manualEntriesCents;
  final int outflowsCents;
  final int withdrawalsCents;
  final int netFlowCents;
  final List<ReportBreakdownRow> movementRows;
  final List<ReportCashflowPoint> timeline;
}
