import '../../domain/entities/report_filter.dart';

class ReportSqlFilterClause {
  const ReportSqlFilterClause({required this.sql, required this.arguments});

  final String sql;
  final List<Object?> arguments;
}

abstract final class ReportSqlFiltersSupport {
  static ReportSqlFilterClause dateRangeClause({
    required String column,
    required ReportFilter filter,
  }) {
    return ReportSqlFilterClause(
      sql: ' AND $column >= ? AND $column < ?',
      arguments: [
        filter.start.toIso8601String(),
        filter.endExclusive.toIso8601String(),
      ],
    );
  }

  static void appendDateRange(
    StringBuffer buffer,
    List<Object?> arguments, {
    required String column,
    required ReportFilter filter,
  }) {
    final clause = dateRangeClause(column: column, filter: filter);
    buffer.write(clause.sql);
    arguments.addAll(clause.arguments);
  }

  static void appendOptionalEquality(
    StringBuffer buffer,
    List<Object?> arguments, {
    required String column,
    required Object? value,
  }) {
    if (value == null) {
      return;
    }
    buffer.write(' AND $column = ?');
    arguments.add(value);
  }
}
