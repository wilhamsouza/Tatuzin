import '../../data/support/report_date_range_support.dart';

class ReportDateRange {
  const ReportDateRange({required this.start, required this.endExclusive});

  final DateTime start;
  final DateTime endExclusive;
}

enum ReportPeriod { daily, weekly, monthly, yearly }

extension ReportPeriodX on ReportPeriod {
  String get label {
    switch (this) {
      case ReportPeriod.daily:
        return 'Diario';
      case ReportPeriod.weekly:
        return 'Semanal';
      case ReportPeriod.monthly:
        return 'Mensal';
      case ReportPeriod.yearly:
        return 'Anual';
    }
  }

  ReportDateRange resolveRange(DateTime reference) {
    switch (this) {
      case ReportPeriod.daily:
        return ReportDateRangeSupport.daily(reference);
      case ReportPeriod.weekly:
        return ReportDateRangeSupport.weekly(reference);
      case ReportPeriod.monthly:
        return ReportDateRangeSupport.monthly(reference);
      case ReportPeriod.yearly:
        return ReportDateRangeSupport.yearly(reference);
    }
  }
}
