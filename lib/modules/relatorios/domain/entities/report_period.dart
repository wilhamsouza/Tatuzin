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
    final base = DateTime(reference.year, reference.month, reference.day);

    switch (this) {
      case ReportPeriod.daily:
        return ReportDateRange(
          start: base,
          endExclusive: base.add(const Duration(days: 1)),
        );
      case ReportPeriod.weekly:
        final weekdayOffset = base.weekday - DateTime.monday;
        final start = base.subtract(Duration(days: weekdayOffset));
        return ReportDateRange(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
        );
      case ReportPeriod.monthly:
        final start = DateTime(reference.year, reference.month);
        final end = reference.month == DateTime.december
            ? DateTime(reference.year + 1)
            : DateTime(reference.year, reference.month + 1);
        return ReportDateRange(start: start, endExclusive: end);
      case ReportPeriod.yearly:
        return ReportDateRange(
          start: DateTime(reference.year),
          endExclusive: DateTime(reference.year + 1),
        );
    }
  }
}
