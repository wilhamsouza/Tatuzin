import 'package:flutter_test/flutter_test.dart';

import 'package:erp_pdv_app/modules/relatorios/data/support/report_date_range_support.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_period.dart';

void main() {
  group('ReportDateRangeSupport', () {
    test('resolve diario e periodo anterior com borda exclusiva', () {
      final current = ReportDateRangeSupport.daily(
        DateTime(2026, 4, 17, 15, 30),
      );
      final previous = ReportDateRangeSupport.previousPeriod(current);

      expect(current.start, DateTime(2026, 4, 17));
      expect(current.endExclusive, DateTime(2026, 4, 18));
      expect(previous.start, DateTime(2026, 4, 16));
      expect(previous.endExclusive, DateTime(2026, 4, 17));
    });

    test('reconhece periodos padrao', () {
      expect(
        ReportDateRangeSupport.matchPeriod(
          ReportDateRange(
            start: DateTime(2026, 4, 17),
            endExclusive: DateTime(2026, 4, 18),
          ),
        ),
        ReportPeriod.daily,
      );

      expect(
        ReportDateRangeSupport.matchPeriod(
          ReportDateRange(
            start: DateTime(2026, 4, 13),
            endExclusive: DateTime(2026, 4, 20),
          ),
        ),
        ReportPeriod.weekly,
      );
    });
  });
}
