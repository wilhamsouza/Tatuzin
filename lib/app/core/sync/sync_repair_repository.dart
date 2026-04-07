import 'sync_reconciliation_result.dart';
import 'sync_repair_action.dart';
import 'sync_repair_decision.dart';
import 'sync_repair_result.dart';
import 'sync_repair_summary.dart';

abstract interface class SyncRepairRepository {
  List<SyncRepairDecision> buildDecisions(
    List<SyncReconciliationResult> reconciliationResults,
  );

  SyncRepairSummary buildSummary(List<SyncRepairDecision> decisions);

  Future<SyncRepairResult> applyAction(SyncRepairAction action);

  Future<SyncRepairResult> applySafeRepairs({Iterable<String>? featureKeys});
}
