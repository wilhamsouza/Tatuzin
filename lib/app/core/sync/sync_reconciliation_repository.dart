import 'sync_reconciliation_result.dart';

abstract interface class SyncReconciliationRepository {
  Future<List<SyncReconciliationResult>> reconcileAll();

  Future<SyncReconciliationResult> reconcileFeature(String featureKey);

  Future<int> markFeatureForResync(String featureKey);
}
