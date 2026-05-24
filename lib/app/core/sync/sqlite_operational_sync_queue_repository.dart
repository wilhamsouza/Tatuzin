import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/table_names.dart';
import '../utils/app_logger.dart';
import 'operational_sync_event.dart';
import 'operational_sync_policy.dart';
import 'operational_sync_queue_item.dart';
import 'operational_sync_queue_repository.dart';
import 'operational_sync_queue_status.dart';
import 'operational_sync_remote_datasource.dart';
import 'sync_error_type.dart';
import 'sync_queue_feature_summary.dart';

class SqliteOperationalSyncQueueRepository
    implements OperationalSyncQueueRepository {
  SqliteOperationalSyncQueueRepository(this._appDatabase);

  static const _checkpointKey = 'pdv.last_pulled_server_version';
  static const _snapshotVersionKey = 'server_first.snapshot_version';
  static const _partialStatusKey = 'pdv.partial_status';
  static const _lastPullErrorKey = 'pdv.last_pull_error';
  static const _lastPullErrorAtKey = 'pdv.last_pull_error_at';
  static const _lastPullSucceededAtKey = 'pdv.last_pull_succeeded_at';
  static const _lastSnapshotErrorKey = 'server_first.last_snapshot_error';
  static const _lastSnapshotErrorAtKey = 'server_first.last_snapshot_error_at';
  static const _lastSnapshotSucceededAtKey =
      'server_first.last_snapshot_succeeded_at';
  static const _featureKey = 'pdv';
  static const stalePushingThreshold = Duration(minutes: 2);

  final AppDatabase _appDatabase;

  @override
  Future<bool> enqueue(
    DatabaseExecutor db, {
    required OperationalSyncEvent event,
  }) async {
    if (!OperationalSyncPolicy.isLocalFirstEntity(event.entity)) {
      AppLogger.warn(
        '[OperationalSync] enqueue_blocked code=${OperationalSyncPolicy.entityNotLocalFirstCode} '
        'entity=${event.entity} operation=${event.operation}',
      );
      return false;
    }

    if (!OperationalSyncPolicy.isAllowedOperation(event.operation)) {
      AppLogger.warn(
        '[OperationalSync] enqueue_blocked code=${OperationalSyncPolicy.invalidOperationCode} '
        'entity=${event.entity} operation=${event.operation}',
      );
      return false;
    }

    final now = DateTime.now().toIso8601String();
    final id = await db.insert(
      TableNames.operationalSyncEvents,
      {
        'event_id': event.eventId,
        'feature': event.feature,
        'entity': event.entity,
        'operation': event.operation.trim().toLowerCase(),
        'entity_local_id': event.entityLocalId,
        'entity_server_id': event.entityServerId,
        'occurred_at': event.occurredAt.toUtc().toIso8601String(),
        'payload_json': event.encodePayload(),
        'status': OperationalSyncQueueStatus.pending.storageValue,
        'attempt_count': 0,
        'next_retry_at': null,
        'server_version': null,
        'error_code': null,
        'error_message': null,
        'conflict_id': null,
        'created_at': now,
        'updated_at': now,
        'pushing_started_at': null,
        'last_pushed_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (id == 0) {
      AppLogger.info(
        '[OperationalSync] enqueue_duplicate eventId=${event.eventId}',
      );
      return false;
    }

    AppLogger.info(
      '[OperationalSync] enqueue_accepted eventId=${event.eventId} '
      'entity=${event.entity} operation=${event.operation}',
    );
    return true;
  }

  @override
  Future<List<OperationalSyncQueueItem>> listPending({
    required int limit,
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
    DateTime? now,
  }) async {
    final database = await _appDatabase.database;
    final currentTime = now ?? DateTime.now();
    final statuses = retryOnly
        ? <String>[OperationalSyncQueueStatus.failed.storageValue]
        : <String>[
            OperationalSyncQueueStatus.pending.storageValue,
            OperationalSyncQueueStatus.failed.storageValue,
          ];
    final placeholders = List.filled(statuses.length, '?').join(', ');
    final retryWhere = ignoreRetryBackoff
        ? ''
        : ' AND (next_retry_at IS NULL OR next_retry_at <= ?)';
    final retryArgs = ignoreRetryBackoff
        ? const <Object?>[]
        : <Object?>[currentTime.toIso8601String()];
    final rows = await database.query(
      TableNames.operationalSyncEvents,
      where: 'status IN ($placeholders)$retryWhere',
      whereArgs: <Object?>[...statuses, ...retryArgs],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );

    return rows.map(_mapRow).toList(growable: false);
  }

  @override
  Future<void> markPushing(
    Iterable<OperationalSyncQueueItem> items, {
    required DateTime startedAt,
  }) async {
    final ids = items.map((item) => item.id).toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final database = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      '''
      UPDATE ${TableNames.operationalSyncEvents}
      SET
        status = ?,
        attempt_count = attempt_count + 1,
        pushing_started_at = ?,
        updated_at = ?
      WHERE id IN ($placeholders)
      ''',
      <Object?>[
        OperationalSyncQueueStatus.pushing.storageValue,
        startedAt.toIso8601String(),
        startedAt.toIso8601String(),
        ...ids,
      ],
    );
  }

  @override
  Future<void> markAccepted({
    required String eventId,
    required String? serverVersion,
    required DateTime processedAt,
  }) {
    return _markTerminal(
      eventId: eventId,
      status: OperationalSyncQueueStatus.accepted,
      processedAt: processedAt,
      serverVersion: serverVersion,
    );
  }

  @override
  Future<void> markDuplicate({
    required String eventId,
    required String? serverVersion,
    required DateTime processedAt,
  }) {
    return _markTerminal(
      eventId: eventId,
      status: OperationalSyncQueueStatus.duplicate,
      processedAt: processedAt,
      serverVersion: serverVersion,
    );
  }

  @override
  Future<void> markRejected({
    required String eventId,
    required String code,
    required String message,
    required DateTime processedAt,
  }) {
    return _markTerminal(
      eventId: eventId,
      status: OperationalSyncQueueStatus.rejected,
      processedAt: processedAt,
      errorCode: code,
      errorMessage: message,
    );
  }

  @override
  Future<void> markConflict({
    required String eventId,
    required String? serverVersion,
    required String code,
    required String message,
    required String? conflictId,
    required DateTime processedAt,
  }) {
    return _markTerminal(
      eventId: eventId,
      status: OperationalSyncQueueStatus.conflict,
      processedAt: processedAt,
      serverVersion: serverVersion,
      errorCode: code,
      errorMessage: message,
      conflictId: conflictId,
    );
  }

  @override
  Future<void> markFailed(
    Iterable<OperationalSyncQueueItem> items, {
    required String message,
    required DateTime failedAt,
    required DateTime? nextRetryAt,
  }) async {
    final ids = items.map((item) => item.id).toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final database = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      '''
      UPDATE ${TableNames.operationalSyncEvents}
      SET
        status = ?,
        next_retry_at = ?,
        error_code = ?,
        error_message = ?,
        updated_at = ?,
        last_pushed_at = ?,
        pushing_started_at = NULL
      WHERE id IN ($placeholders)
      ''',
      <Object?>[
        OperationalSyncQueueStatus.failed.storageValue,
        nextRetryAt?.toIso8601String(),
        'SYNC_PUSH_FAILED',
        message,
        failedAt.toIso8601String(),
        failedAt.toIso8601String(),
        ...ids,
      ],
    );
  }

  @override
  Future<int> recoverStalePushing({
    required Duration staleAfter,
    DateTime? now,
  }) async {
    final database = await _appDatabase.database;
    final currentTime = now ?? DateTime.now();
    final cutoff = currentTime.subtract(staleAfter).toIso8601String();
    final recovered = await database.rawUpdate(
      '''
      UPDATE ${TableNames.operationalSyncEvents}
      SET
        status = ?,
        next_retry_at = NULL,
        error_code = COALESCE(error_code, ?),
        error_message = COALESCE(error_message, ?),
        updated_at = ?,
        last_pushed_at = COALESCE(last_pushed_at, pushing_started_at),
        pushing_started_at = NULL
      WHERE status = ?
        AND pushing_started_at IS NOT NULL
        AND pushing_started_at <= ?
      ''',
      <Object?>[
        OperationalSyncQueueStatus.pending.storageValue,
        'SYNC_PUSH_STALE',
        'Envio operacional anterior ficou interrompido e voltou para a fila.',
        currentTime.toIso8601String(),
        OperationalSyncQueueStatus.pushing.storageValue,
        cutoff,
      ],
    );

    if (recovered > 0) {
      AppLogger.warn(
        '[OperationalSync] stale_pushing_recovered count=$recovered '
        'stale_after_seconds=${staleAfter.inSeconds}',
      );
    }

    return recovered;
  }

  @override
  Future<String> readCheckpoint() async {
    return await _readState(_checkpointKey) ?? '0';
  }

  @override
  Future<void> saveCheckpoint(String serverVersion) {
    return _saveState(_checkpointKey, serverVersion);
  }

  @override
  Future<String?> readSnapshotVersion() {
    return _readState(_snapshotVersionKey);
  }

  @override
  Future<void> saveSnapshotVersion(String serverFirstSnapshotVersion) {
    return _saveState(_snapshotVersionKey, serverFirstSnapshotVersion);
  }

  @override
  Future<void> recordPullSucceeded({required DateTime completedAt}) async {
    await _saveState(_lastPullSucceededAtKey, completedAt.toIso8601String());
    await _deleteState(_lastPullErrorKey);
    await _deleteState(_lastPullErrorAtKey);
    if (!await _hasState(_lastSnapshotErrorKey)) {
      await _saveState(_partialStatusKey, 'ok');
    }
  }

  @override
  Future<void> recordPullFailed({
    required String message,
    required DateTime failedAt,
  }) async {
    await _saveState(_partialStatusKey, 'pushOkPullFailed');
    await _saveState(_lastPullErrorKey, _summarizeMessage(message));
    await _saveState(_lastPullErrorAtKey, failedAt.toIso8601String());
  }

  @override
  Future<void> recordSnapshotSucceeded({
    required String serverFirstSnapshotVersion,
    required DateTime completedAt,
  }) async {
    await saveSnapshotVersion(serverFirstSnapshotVersion);
    await _saveState(
      _lastSnapshotSucceededAtKey,
      completedAt.toIso8601String(),
    );
    await _deleteState(_lastSnapshotErrorKey);
    await _deleteState(_lastSnapshotErrorAtKey);
    if (!await _hasState(_lastPullErrorKey)) {
      await _saveState(_partialStatusKey, 'ok');
    }
  }

  @override
  Future<void> recordSnapshotFailed({
    required String message,
    required DateTime failedAt,
  }) async {
    await _saveState(_partialStatusKey, 'snapshotFailed');
    await _saveState(_lastSnapshotErrorKey, _summarizeMessage(message));
    await _saveState(_lastSnapshotErrorAtKey, failedAt.toIso8601String());
  }

  @override
  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries() async {
    final database = await _appDatabase.database;
    final partialStatus = await _readState(_partialStatusKey);
    final lastPullError = await _readState(_lastPullErrorKey);
    final lastPullErrorAt = _parseDateTime(
      await _readState(_lastPullErrorAtKey),
    );
    final lastSnapshotError = await _readState(_lastSnapshotErrorKey);
    final lastSnapshotErrorAt = _parseDateTime(
      await _readState(_lastSnapshotErrorAtKey),
    );
    final rows = await database.query(
      TableNames.operationalSyncEvents,
      orderBy: 'updated_at DESC, id DESC',
    );
    if (rows.isEmpty &&
        partialStatus == null &&
        lastPullError == null &&
        lastSnapshotError == null) {
      return const <SyncQueueFeatureSummary>[];
    }

    var pendingCount = 0;
    var processingCount = 0;
    var activeProcessingCount = 0;
    var staleProcessingCount = 0;
    var acceptedCount = 0;
    var errorCount = 0;
    var conflictCount = 0;
    var totalAttempts = 0;
    DateTime? lastProcessedAt;
    DateTime? lastErrorAt;
    DateTime? nextRetryAt;
    String? lastError;
    SyncErrorType? lastErrorType;

    for (final row in rows) {
      final item = _mapRow(row);
      totalAttempts += item.attemptCount;
      switch (item.status) {
        case OperationalSyncQueueStatus.pending:
          pendingCount++;
          break;
        case OperationalSyncQueueStatus.pushing:
          processingCount++;
          if (_isStalePushing(item, DateTime.now())) {
            staleProcessingCount++;
          } else {
            activeProcessingCount++;
          }
          break;
        case OperationalSyncQueueStatus.accepted:
        case OperationalSyncQueueStatus.duplicate:
          acceptedCount++;
          break;
        case OperationalSyncQueueStatus.rejected:
        case OperationalSyncQueueStatus.failed:
          errorCount++;
          break;
        case OperationalSyncQueueStatus.conflict:
          conflictCount++;
          break;
      }

      if (item.lastPushedAt != null &&
          (lastProcessedAt == null ||
              item.lastPushedAt!.isAfter(lastProcessedAt))) {
        lastProcessedAt = item.lastPushedAt;
      }
      if (item.nextRetryAt != null &&
          (nextRetryAt == null || item.nextRetryAt!.isBefore(nextRetryAt))) {
        nextRetryAt = item.nextRetryAt;
      }
      if (item.errorMessage != null &&
          (lastErrorAt == null || item.updatedAt.isAfter(lastErrorAt))) {
        lastErrorAt = item.updatedAt;
        lastError = item.errorMessage;
        lastErrorType = item.status == OperationalSyncQueueStatus.conflict
            ? SyncErrorType.conflict
            : SyncErrorType.server;
      }
    }

    return <SyncQueueFeatureSummary>[
      SyncQueueFeatureSummary(
        featureKey: _featureKey,
        displayName: 'PDV operacional',
        totalTracked: rows.length,
        pendingCount: pendingCount,
        processingCount: processingCount,
        activeProcessingCount: activeProcessingCount,
        staleProcessingCount: staleProcessingCount,
        syncedCount: acceptedCount,
        errorCount: errorCount,
        blockedCount: 0,
        conflictCount: conflictCount,
        totalAttemptCount: totalAttempts,
        lastProcessedAt: lastProcessedAt,
        nextRetryAt: nextRetryAt,
        lastError: lastError ?? lastPullError ?? lastSnapshotError,
        lastErrorType: lastErrorType,
        lastErrorAt:
            lastErrorAt ?? _latestDate(lastPullErrorAt, lastSnapshotErrorAt),
        partialStatus: partialStatus,
        lastPullError: lastPullError,
        lastSnapshotError: lastSnapshotError,
      ),
    ];
  }

  @override
  Future<OperationalSyncDiagnosticReport> buildDiagnosticReport({
    List<OperationalSyncConflict> conflicts = const <OperationalSyncConflict>[],
  }) async {
    final summaries = await listFeatureSummaries();
    final summary = summaries.isEmpty ? null : summaries.first;
    final openConflicts = conflicts
        .where((conflict) => conflict.status.toUpperCase() == 'OPEN')
        .length;
    final resolvedConflicts = conflicts
        .where((conflict) => conflict.status.toUpperCase() == 'RESOLVED')
        .length;
    final ignoredConflicts = conflicts
        .where((conflict) => conflict.status.toUpperCase() == 'IGNORED')
        .length;
    return OperationalSyncDiagnosticReport(
      pendingCount: summary?.pendingCount ?? 0,
      failedCount: summary?.errorCount ?? 0,
      openConflictCount: openConflicts + (summary?.conflictCount ?? 0),
      resolvedConflictCount: resolvedConflicts,
      ignoredConflictCount: ignoredConflicts,
      lastLocalError: summary?.lastError,
      lastLocalErrorEntity: _lastErrorEntity(summary?.lastError),
      lastPushAt: summary?.lastProcessedAt,
      lastPullAt: _parseDateTime(await _readState(_lastPullSucceededAtKey)),
      lastSuccessfulSyncAt: _latestDate(
        summary?.lastProcessedAt,
        _parseDateTime(await _readState(_lastPullSucceededAtKey)),
      ),
      safeDetails: <String, dynamic>{
        'feature': _featureKey,
        'totalTracked': summary?.totalTracked ?? 0,
        'staleProcessingCount': summary?.staleProcessingCount ?? 0,
        'lastPullError': summary?.lastPullError,
        'lastSnapshotError': summary?.lastSnapshotError,
      },
    );
  }

  @override
  Future<int> repairOperationalOrderItemTotalCents() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.operationalSyncEvents,
      where: 'status = ? AND entity = ?',
      whereArgs: [
        OperationalSyncQueueStatus.failed.storageValue,
        'operationalOrderItem',
      ],
    );
    var repaired = 0;
    final now = DateTime.now().toIso8601String();
    for (final row in rows) {
      final rawPayload = row['payload_json'] as String? ?? '{}';
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final currentTotal = _intValue(decoded['totalCents']);
      if (currentTotal != null && currentTotal >= 0) {
        continue;
      }
      final totalCents = _deriveOperationalOrderItemTotalCents(decoded);
      if (totalCents == null) {
        continue;
      }
      decoded['totalCents'] = max(0, totalCents);
      await database.update(
        TableNames.operationalSyncEvents,
        {
          'payload_json': jsonEncode(decoded),
          'status': OperationalSyncQueueStatus.pending.storageValue,
          'next_retry_at': null,
          'error_code': null,
          'error_message': null,
          'pushing_started_at': null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      repaired++;
    }
    if (repaired > 0) {
      await _deleteState(_lastPullErrorKey);
      await _deleteState(_lastPullErrorAtKey);
    }
    return repaired;
  }

  @override
  Future<int> reenqueueRecoverableFailedEvents() async {
    final repaired = await repairOperationalOrderItemTotalCents();
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.operationalSyncEvents,
      where: 'status = ? AND entity = ?',
      whereArgs: [
        OperationalSyncQueueStatus.failed.storageValue,
        'operationalOrderItem',
      ],
    );
    var requeued = 0;
    final now = DateTime.now().toIso8601String();
    for (final row in rows) {
      final decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final totalCents = _intValue(decoded['totalCents']);
      if (totalCents == null || totalCents < 0) {
        continue;
      }
      await database.update(
        TableNames.operationalSyncEvents,
        {
          'status': OperationalSyncQueueStatus.pending.storageValue,
          'next_retry_at': null,
          'error_code': null,
          'error_message': null,
          'pushing_started_at': null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      requeued++;
    }
    return repaired + requeued;
  }

  @override
  Future<int> clearResolvedConflictCache({
    required List<OperationalSyncConflict> conflicts,
  }) async {
    final resolvedIds = conflicts
        .where(
          (conflict) =>
              conflict.status.toUpperCase() == 'RESOLVED' ||
              conflict.status.toUpperCase() == 'IGNORED',
        )
        .map((conflict) => conflict.id)
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    if (resolvedIds.isEmpty) {
      return 0;
    }
    final database = await _appDatabase.database;
    final placeholders = List.filled(resolvedIds.length, '?').join(', ');
    final now = DateTime.now().toIso8601String();
    return database.rawUpdate(
      '''
      UPDATE ${TableNames.operationalSyncEvents}
      SET
        status = ?,
        error_code = NULL,
        error_message = NULL,
        conflict_id = NULL,
        next_retry_at = NULL,
        pushing_started_at = NULL,
        updated_at = ?
      WHERE status = ? AND conflict_id IN ($placeholders)
      ''',
      <Object?>[
        OperationalSyncQueueStatus.duplicate.storageValue,
        now,
        OperationalSyncQueueStatus.conflict.storageValue,
        ...resolvedIds,
      ],
    );
  }

  Future<void> _markTerminal({
    required String eventId,
    required OperationalSyncQueueStatus status,
    required DateTime processedAt,
    String? serverVersion,
    String? errorCode,
    String? errorMessage,
    String? conflictId,
  }) async {
    final database = await _appDatabase.database;
    await database.update(
      TableNames.operationalSyncEvents,
      {
        'status': status.storageValue,
        'server_version': serverVersion,
        'error_code': errorCode,
        'error_message': errorMessage,
        'conflict_id': conflictId,
        'next_retry_at': null,
        'updated_at': processedAt.toIso8601String(),
        'last_pushed_at': processedAt.toIso8601String(),
        'pushing_started_at': null,
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  bool _isStalePushing(OperationalSyncQueueItem item, DateTime now) {
    final pushingStartedAt = item.pushingStartedAt;
    return pushingStartedAt != null &&
        now.difference(pushingStartedAt) >= stalePushingThreshold;
  }

  Future<String?> _readState(String key) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.operationalSyncState,
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> _saveState(String key, String value) async {
    final database = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await database.insert(
      TableNames.operationalSyncState,
      {'key': key, 'value': value, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _deleteState(String key) async {
    final database = await _appDatabase.database;
    await database.delete(
      TableNames.operationalSyncState,
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<bool> _hasState(String key) async {
    final value = await _readState(key);
    return value != null && value.trim().isNotEmpty;
  }

  String _summarizeMessage(String message) {
    final normalized = message.trim();
    if (normalized.length <= 400) {
      return normalized;
    }
    return '${normalized.substring(0, 400)}...';
  }

  DateTime? _latestDate(DateTime? first, DateTime? second) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.isAfter(second) ? first : second;
  }

  String? _lastErrorEntity(String? message) {
    if (message == null) {
      return null;
    }
    if (message.contains('operationalOrderItem')) {
      return 'operationalOrderItem';
    }
    return null;
  }

  int? _deriveOperationalOrderItemTotalCents(Map<String, dynamic> payload) {
    final subtotal = _intValue(payload['subtotalCents']);
    if (subtotal != null) {
      return max(0, subtotal);
    }
    final unitPrice = _intValue(payload['unitPriceCents']);
    final quantityMil = _intValue(payload['quantityMil']);
    if (unitPrice == null || quantityMil == null || quantityMil < 0) {
      return null;
    }
    final discount = _intValue(payload['discountCents']) ?? 0;
    return max(0, ((unitPrice * quantityMil) ~/ 1000) - discount);
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  OperationalSyncQueueItem _mapRow(Map<String, Object?> row) {
    return OperationalSyncQueueItem(
      id: row['id'] as int,
      event: OperationalSyncEvent.fromStorage(
        eventId: row['event_id'] as String,
        feature: row['feature'] as String,
        entity: row['entity'] as String,
        operation: row['operation'] as String,
        entityLocalId: row['entity_local_id'] as String?,
        entityServerId: row['entity_server_id'] as String?,
        occurredAt: row['occurred_at'] as String,
        payloadJson: row['payload_json'] as String,
      ),
      status: operationalSyncQueueStatusFromStorage(row['status'] as String?),
      attemptCount: row['attempt_count'] as int? ?? 0,
      nextRetryAt: _parseDateTime(row['next_retry_at']),
      serverVersion: row['server_version'] as String?,
      errorCode: row['error_code'] as String?,
      errorMessage: row['error_message'] as String?,
      conflictId: row['conflict_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      pushingStartedAt: _parseDateTime(row['pushing_started_at']),
      lastPushedAt: _parseDateTime(row['last_pushed_at']),
    );
  }

  DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }
}
