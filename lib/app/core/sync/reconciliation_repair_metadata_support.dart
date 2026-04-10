import 'package:sqflite/sqflite.dart';

import '../app_context/record_identity.dart';
import '../database/table_names.dart';
import 'sqlite_sync_metadata_repository.dart';
import 'sync_error_type.dart';
import 'sync_queue_status.dart';
import 'sync_reconciliation_issue.dart';
import 'sync_status.dart';

class ReconciliationRepairMetadataSupport {
  const ReconciliationRepairMetadataSupport._();

  static Future<void> clearBrokenRemoteLink(
    DatabaseExecutor txn, {
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required String metadataFeatureKey,
    required SyncReconciliationIssue issue,
    required int localId,
    required String localUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    await syncMetadataRepository.saveExplicit(
      txn,
      featureKey: metadataFeatureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: null,
      status: SyncStatus.localOnly,
      origin: RecordOrigin.local,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: null,
      lastError: issue.message,
      lastErrorType: SyncErrorType.dependency.storageValue,
      lastErrorAt: DateTime.now(),
    );

    final nextStatus = issue.queueStatus == SyncQueueStatus.conflict
        ? SyncQueueStatus.conflict
        : SyncQueueStatus.pendingUpload;
    final touchedAt = DateTime.now();
    await txn.update(
      TableNames.syncQueue,
      <String, Object?>{
        'remote_id': null,
        'status': nextStatus.storageValue,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'locked_at': null,
        'updated_at': touchedAt.toIso8601String(),
        'last_processed_at': null,
        'remote_updated_at': null,
        'conflict_reason': null,
      },
      where: 'feature_key = ? AND entity_type = ? AND local_entity_id = ?',
      whereArgs: [issue.featureKey, issue.entityType, issue.localEntityId],
    );
  }
}
