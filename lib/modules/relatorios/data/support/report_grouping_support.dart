import '../../domain/entities/report_filter.dart';

class ReportGroupingSql {
  const ReportGroupingSql({
    required this.keyExpression,
    required this.orderExpression,
  });

  final String keyExpression;
  final String orderExpression;
}

abstract final class ReportGroupingSupport {
  static ReportGrouping normalizeTimeSeries(ReportGrouping grouping) {
    if (grouping.isTimeSeries) {
      return grouping;
    }
    return ReportGrouping.day;
  }

  static ReportGroupingSql timeBucketSql(
    ReportGrouping grouping, {
    required String column,
  }) {
    switch (normalizeTimeSeries(grouping)) {
      case ReportGrouping.day:
        return ReportGroupingSql(
          keyExpression: "date($column)",
          orderExpression: "date($column)",
        );
      case ReportGrouping.week:
        final weekStartExpression =
            "date($column, '-' || ((CAST(strftime('%w', $column) AS INTEGER) + 6) % 7) || ' days')";
        return ReportGroupingSql(
          keyExpression: weekStartExpression,
          orderExpression: weekStartExpression,
        );
      case ReportGrouping.month:
        return ReportGroupingSql(
          keyExpression: "date($column, 'start of month')",
          orderExpression: "date($column, 'start of month')",
        );
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return ReportGroupingSql(
          keyExpression: "date($column)",
          orderExpression: "date($column)",
        );
    }
  }
}
