import 'sync_feature_summary.dart';

abstract interface class SyncReadinessRepository {
  Future<List<SyncFeatureSummary>> listFeatureSummaries();
}
