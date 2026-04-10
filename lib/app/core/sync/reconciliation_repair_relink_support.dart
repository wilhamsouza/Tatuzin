import 'package:sqflite/sqflite.dart';

import '../app_context/record_identity.dart';
import '../database/table_names.dart';
import 'sqlite_sync_metadata_repository.dart';
import 'sync_queue_status.dart';
import 'sync_reconciliation_issue.dart';
import 'sync_status.dart';

class ReconciliationRepairRelinkSupport {
  const ReconciliationRepairRelinkSupport._();

  static Future<void> applyRemoteRelink(
    DatabaseExecutor txn, {
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required String metadataFeatureKey,
    required SyncReconciliationIssue issue,
    required int localId,
    required String localUuid,
    required String remoteId,
    required SyncStatus nextStatus,
    required SyncQueueStatus queueStatus,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? syncedAt,
    required DateTime touchedAt,
  }) async {
    await syncMetadataRepository.saveExplicit(
      txn,
      featureKey: metadataFeatureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: nextStatus,
      origin: RecordOrigin.merged,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: syncedAt,
      lastError: null,
      lastErrorType: null,
      lastErrorAt: null,
    );

    await txn.update(
      TableNames.syncQueue,
      <String, Object?>{
        'remote_id': remoteId,
        'status': queueStatus.storageValue,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'locked_at': null,
        'updated_at': touchedAt.toIso8601String(),
        'last_processed_at': queueStatus == SyncQueueStatus.synced
            ? touchedAt.toIso8601String()
            : null,
        'remote_updated_at': queueStatus == SyncQueueStatus.synced
            ? touchedAt.toIso8601String()
            : null,
        'conflict_reason': null,
      },
      where: 'feature_key = ? AND entity_type = ? AND local_entity_id = ?',
      whereArgs: [issue.featureKey, issue.entityType, issue.localEntityId],
    );
  }
}
