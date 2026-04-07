import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../data/sqlite_report_repository.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/report_summary.dart';
import '../../domain/repositories/report_repository.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return SqliteReportRepository(ref.read(appDatabaseProvider));
});

final reportPeriodProvider = StateProvider<ReportPeriod>(
  (ref) => ReportPeriod.daily,
);

final reportSummaryProvider = FutureProvider<ReportSummary>((ref) async {
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchSummary(period: ref.watch(reportPeriodProvider));
});
