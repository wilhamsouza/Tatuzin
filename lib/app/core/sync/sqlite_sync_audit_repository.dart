import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/table_names.dart';
import 'sync_audit_event_type.dart';
import 'sync_audit_log.dart';

class SqliteSyncAuditRepository {
  SqliteSyncAuditRepository(this._appDatabase);

  static const int retentionLimit = 1500;

  final AppDatabase _appDatabase;

  Future<void> log({
    required String featureKey,
    String? entityType,
    int? localEntityId,
    String? localUuid,
    String? remoteId,
    required SyncAuditEventType eventType,
    required String message,
    Map<String, dynamic>? details,
    DateTime? createdAt,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _appDatabase.database;
    final timestamp = createdAt ?? DateTime.now();
    await db.insert(TableNames.syncAuditLogs, <String, Object?>{
      'feature_key': featureKey,
      'entity_type': entityType,
      'local_entity_id': localEntityId,
      'local_uuid': localUuid,
      'remote_id': remoteId,
      'event_type': eventType.storageValue,
      'message': message,
      'details_json': details == null ? null : jsonEncode(details),
      'created_at': timestamp.toIso8601String(),
    });

    await _trimRetention(db);
  }

  Future<List<SyncAuditLog>> listRecent({
    int limit = 60,
    Iterable<String>? featureKeys,
  }) async {
    final db = await _appDatabase.database;
    final whereArgs = <Object?>[];
    String? where;
    if (featureKeys != null && featureKeys.isNotEmpty) {
      final placeholders = List.filled(featureKeys.length, '?').join(', ');
      where = 'feature_key IN ($placeholders)';
      whereArgs.addAll(featureKeys);
    }

    final rows = await db.query(
      TableNames.syncAuditLogs,
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );

    return rows.map(_mapRow).toList();
  }

  Future<void> _trimRetention(DatabaseExecutor db) async {
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${TableNames.syncAuditLogs}',
    );
    final total = countRows.first['total'] as int? ?? 0;
    if (total <= retentionLimit) {
      return;
    }

    final overflow = total - retentionLimit;
    await db.delete(
      TableNames.syncAuditLogs,
      where:
          'id IN (SELECT id FROM ${TableNames.syncAuditLogs} ORDER BY created_at ASC, id ASC LIMIT ?)',
      whereArgs: <Object?>[overflow],
    );
  }

  SyncAuditLog _mapRow(Map<String, Object?> row) {
    final detailsJson = row['details_json'] as String?;
    return SyncAuditLog(
      id: row['id'] as int,
      featureKey: row['feature_key'] as String,
      entityType: row['entity_type'] as String?,
      localEntityId: row['local_entity_id'] as int?,
      localUuid: row['local_uuid'] as String?,
      remoteId: row['remote_id'] as String?,
      eventType: syncAuditEventTypeFromStorage(row['event_type'] as String?),
      message: row['message'] as String? ?? '',
      details: detailsJson == null || detailsJson.trim().isEmpty
          ? null
          : jsonDecode(detailsJson) as Map<String, dynamic>,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
