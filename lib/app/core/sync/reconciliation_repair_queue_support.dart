import 'package:sqflite/sqflite.dart';

import '../database/table_names.dart';
import 'sync_queue_status.dart';
import 'sync_reconciliation_issue.dart';

class ReconciliationRepairQueueSupport {
  const ReconciliationRepairQueueSupport._();

  static Future<void> clearStaleBlock(
    DatabaseExecutor txn, {
    required SyncReconciliationIssue issue,
    required DateTime touchedAt,
  }) async {
    final nextStatus = issue.remoteId == null || issue.remoteId!.isEmpty
        ? SyncQueueStatus.pendingUpload
        : SyncQueueStatus.pendingUpdate;
    await txn.update(
      TableNames.syncQueue,
      <String, Object?>{
        'status': nextStatus.storageValue,
        'last_error': null,
        'last_error_type': null,
        'next_retry_at': null,
        'locked_at': null,
        'updated_at': touchedAt.toIso8601String(),
        'conflict_reason': null,
      },
      where: 'feature_key = ? AND entity_type = ? AND local_entity_id = ?',
      whereArgs: [issue.featureKey, issue.entityType, issue.localEntityId],
    );
  }
}
