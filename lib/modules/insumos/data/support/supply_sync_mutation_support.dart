import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../../../app/core/sync/sync_queue_operation.dart';

abstract final class SupplySyncMutationSupport {
  static Future<void> markSuppliesForSync(
    DatabaseExecutor txn, {
    required Iterable<int> supplyIds,
    required DateTime changedAt,
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required SqliteSyncQueueRepository syncQueueRepository,
  }) async {
    final normalizedIds = supplyIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final placeholders = List.filled(normalizedIds.length, '?').join(',');
    final rows = await txn.query(
      TableNames.supplies,
      columns: const ['id', 'uuid', 'created_at'],
      where: 'id IN ($placeholders)',
      whereArgs: normalizedIds,
    );

    for (final row in rows) {
      final localId = row['id'] as int;
      final localUuid = row['uuid'] as String;
      final createdAt = DateTime.parse(row['created_at'] as String);
      final metadata = await syncMetadataRepository.findByLocalId(
        txn,
        featureKey: SyncFeatureKeys.supplies,
        localId: localId,
      );

      if (metadata?.identity.remoteId == null) {
        await syncMetadataRepository.markPendingUpload(
          txn,
          featureKey: SyncFeatureKeys.supplies,
          localId: localId,
          localUuid: localUuid,
          createdAt: createdAt,
          updatedAt: changedAt,
        );
      } else {
        await syncMetadataRepository.markPendingUpdate(
          txn,
          featureKey: SyncFeatureKeys.supplies,
          localId: localId,
          localUuid: localUuid,
          remoteId: metadata!.identity.remoteId,
          createdAt: createdAt,
          updatedAt: changedAt,
        );
      }

      await syncQueueRepository.enqueueMutation(
        txn,
        featureKey: SyncFeatureKeys.supplies,
        entityType: 'supply',
        localEntityId: localId,
        localUuid: localUuid,
        remoteId: metadata?.identity.remoteId,
        operation: metadata?.identity.remoteId == null
            ? SyncQueueOperation.create
            : SyncQueueOperation.update,
        localUpdatedAt: changedAt,
      );
    }
  }
}
