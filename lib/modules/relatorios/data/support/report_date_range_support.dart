import '../../domain/entities/report_period.dart';

abstract final class ReportDateRangeSupport {
  static ReportDateRange daily(DateTime reference) {
    final base = DateTime(reference.year, reference.month, reference.day);
    return ReportDateRange(
      start: base,
      endExclusive: base.add(const Duration(days: 1)),
    );
  }

  static ReportDateRange weekly(DateTime reference) {
    final base = DateTime(reference.year, reference.month, reference.day);
    final weekdayOffset = base.weekday - DateTime.monday;
    final start = base.subtract(Duration(days: weekdayOffset));
    return ReportDateRange(
      start: start,
      endExclusive: start.add(const Duration(days: 7)),
    );
  }

  static ReportDateRange monthly(DateTime reference) {
    final start = DateTime(reference.year, reference.month);
    final end = reference.month == DateTime.december
        ? DateTime(reference.year + 1)
        : DateTime(reference.year, reference.month + 1);
    return ReportDateRange(start: start, endExclusive: end);
  }

  static ReportDateRange yearly(DateTime reference) {
    return ReportDateRange(
      start: DateTime(reference.year),
      endExclusive: DateTime(reference.year + 1),
    );
  }

  static ReportDateRange custom({
    required DateTime start,
    required DateTime endExclusive,
  }) {
    return ReportDateRange(start: start, endExclusive: endExclusive);
  }

  static ReportDateRange previousPeriod(ReportDateRange current) {
    final span = current.endExclusive.difference(current.start);
    return ReportDateRange(
      start: current.start.subtract(span),
      endExclusive: current.start,
    );
  }

  static ReportPeriod? matchPeriod(ReportDateRange range) {
    if (range.endExclusive == range.start.add(const Duration(days: 1))) {
      return ReportPeriod.daily;
    }
    if (range.start.weekday == DateTime.monday &&
        range.endExclusive == range.start.add(const Duration(days: 7))) {
      return ReportPeriod.weekly;
    }
    if (range.start.day == 1 &&
        range.endExclusive.day == 1 &&
        range.endExclusive.year == range.start.year &&
        range.endExclusive.month == range.start.month + 1) {
      return ReportPeriod.monthly;
    }
    if (range.start.month == 1 &&
        range.start.day == 1 &&
        range.endExclusive.month == 1 &&
        range.endExclusive.day == 1 &&
        range.endExclusive.year == range.start.year + 1) {
      return ReportPeriod.yearly;
    }
    if (range.start.month == 12 &&
        range.start.day == 1 &&
        range.endExclusive.year == range.start.year + 1 &&
        range.endExclusive.month == 1 &&
        range.endExclusive.day == 1) {
      return ReportPeriod.monthly;
    }
    return null;
  }
}
