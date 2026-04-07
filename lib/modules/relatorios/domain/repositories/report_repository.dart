import '../entities/report_period.dart';
import '../entities/report_summary.dart';

abstract class ReportRepository {
  Future<ReportSummary> fetchSummary({required ReportPeriod period});
}
