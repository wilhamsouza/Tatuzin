import 'package:sqflite/sqflite.dart';

import '../app_context/record_identity.dart';
import '../database/app_database.dart';
import '../database/table_names.dart';
import 'sync_error_type.dart';
import 'sync_metadata.dart';
import 'sync_status.dart';

class SqliteSyncMetadataRepository {
  const SqliteSyncMetadataRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<List<SyncMetadata>> listByFeature(String featureKey) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncRegistros,
      where: 'feature_key = ?',
      whereArgs: [featureKey],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapRow).toList();
  }

  Future<SyncMetadata?> findByLocalId(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
  }) async {
    final rows = await db.query(
      TableNames.syncRegistros,
      where: 'feature_key = ? AND local_id = ?',
      whereArgs: [featureKey, localId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapRow(rows.first);
  }

  Future<SyncMetadata?> findByRemoteId(
    DatabaseExecutor db, {
    required String featureKey,
    required String remoteId,
  }) async {
    final rows = await db.query(
      TableNames.syncRegistros,
      where: 'feature_key = ? AND remote_id = ?',
      whereArgs: [featureKey, remoteId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapRow(rows.first);
  }

  Future<SyncMetadata?> findByLocalUuid(
    DatabaseExecutor db, {
    required String featureKey,
    required String localUuid,
  }) async {
    final rows = await db.query(
      TableNames.syncRegistros,
      where: 'feature_key = ? AND local_uuid = ?',
      whereArgs: [featureKey, localUuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapRow(rows.first);
  }

  Future<void> markPendingUpload(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    await _upsert(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: null,
      status: SyncStatus.pendingUpload,
      origin: RecordOrigin.local,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: null,
      lastError: null,
      lastErrorType: null,
      lastErrorAt: null,
    );
  }

  Future<void> markPendingUpdate(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    await _upsert(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: remoteId == null
          ? SyncStatus.pendingUpload
          : SyncStatus.pendingUpdate,
      origin: remoteId == null ? RecordOrigin.local : RecordOrigin.merged,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: null,
      lastError: null,
      lastErrorType: null,
      lastErrorAt: null,
    );
  }

  Future<void> markSynced(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String remoteId,
    required RecordOrigin origin,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime syncedAt,
  }) async {
    await _upsert(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: SyncStatus.synced,
      origin: origin,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: syncedAt,
      lastError: null,
      lastErrorType: null,
      lastErrorAt: null,
    );
  }

  Future<void> markSyncError(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String message,
    required SyncErrorType errorType,
  }) async {
    await _upsert(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: SyncStatus.syncError,
      origin: remoteId == null ? RecordOrigin.local : RecordOrigin.merged,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: null,
      lastError: message,
      lastErrorType: errorType.storageValue,
      lastErrorAt: updatedAt,
    );
  }

  Future<void> markConflict(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String message,
  }) async {
    await _upsert(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: SyncStatus.conflict,
      origin: remoteId == null ? RecordOrigin.local : RecordOrigin.merged,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: null,
      lastError: message,
      lastErrorType: SyncErrorType.conflict.storageValue,
      lastErrorAt: updatedAt,
    );
  }

  Future<void> saveExplicit(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required SyncStatus status,
    required RecordOrigin origin,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? lastSyncedAt,
    String? lastError,
    String? lastErrorType,
    DateTime? lastErrorAt,
  }) async {
    await _upsert(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: status,
      origin: origin,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastSyncedAt: lastSyncedAt,
      lastError: lastError,
      lastErrorType: lastErrorType,
      lastErrorAt: lastErrorAt,
    );
  }

  Future<void> removeByLocalId(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
  }) async {
    await db.delete(
      TableNames.syncRegistros,
      where: 'feature_key = ? AND local_id = ?',
      whereArgs: [featureKey, localId],
    );
  }

  Future<void> _upsert(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required SyncStatus status,
    required RecordOrigin origin,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? lastSyncedAt,
    required String? lastError,
    required String? lastErrorType,
    required DateTime? lastErrorAt,
  }) async {
    final values = <String, Object?>{
      'feature_key': featureKey,
      'local_id': localId,
      'local_uuid': localUuid,
      'remote_id': remoteId,
      'sync_status': status.storageValue,
      'origin': recordOriginToStorage(origin),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'last_error': lastError,
      'last_error_type': lastErrorType,
      'last_error_at': lastErrorAt?.toIso8601String(),
    };

    final existing = await findByLocalId(
      db,
      featureKey: featureKey,
      localId: localId,
    );

    if (existing == null) {
      await db.insert(TableNames.syncRegistros, values);
      return;
    }

    await db.update(
      TableNames.syncRegistros,
      values,
      where: 'feature_key = ? AND local_id = ?',
      whereArgs: [featureKey, localId],
    );
  }

  SyncMetadata _mapRow(Map<String, Object?> row) {
    return SyncMetadata(
      featureKey: row['feature_key'] as String,
      identity: RecordIdentity(
        localId: row['local_id'] as int?,
        localUuid: row['local_uuid'] as String?,
        remoteId: row['remote_id'] as String?,
        origin: recordOriginFromStorage(row['origin'] as String?),
        lastSyncedAt: row['last_synced_at'] == null
            ? null
            : DateTime.parse(row['last_synced_at'] as String),
      ),
      status: syncStatusFromStorage(row['sync_status'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lastSyncedAt: row['last_synced_at'] == null
          ? null
          : DateTime.parse(row['last_synced_at'] as String),
      lastError: row['last_error'] as String?,
      lastErrorType: row['last_error_type'] as String?,
      lastErrorAt: row['last_error_at'] == null
          ? null
          : DateTime.parse(row['last_error_at'] as String),
    );
  }
}
