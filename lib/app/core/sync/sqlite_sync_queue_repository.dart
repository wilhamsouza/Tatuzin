import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/table_names.dart';
import 'sqlite_sync_audit_repository.dart';
import 'sync_audit_event_type.dart';
import 'sync_conflict_info.dart';
import 'sync_error_type.dart';
import 'sync_feature_keys.dart';
import 'sync_queue_feature_summary.dart';
import 'sync_queue_item.dart';
import 'sync_queue_operation.dart';
import 'sync_queue_repository.dart';
import 'sync_queue_status.dart';

class SqliteSyncQueueRepository implements SyncQueueRepository {
  SqliteSyncQueueRepository(this._appDatabase)
    : _auditRepository = SqliteSyncAuditRepository(_appDatabase);

  static const Duration staleLockThreshold = Duration(minutes: 2);

  final AppDatabase _appDatabase;
  final SqliteSyncAuditRepository _auditRepository;

  @override
  Future<void> enqueueMutation(
    DatabaseExecutor db, {
    required String featureKey,
    required String entityType,
    required int localEntityId,
    required String? localUuid,
    required String? remoteId,
    required SyncQueueOperation operation,
    required DateTime localUpdatedAt,
  }) async {
    final now = DateTime.now();
    final correlationKey = _buildCorrelationKey(
      featureKey: featureKey,
      entityType: entityType,
      localEntityId: localEntityId,
    );
    final rows = await db.query(
      TableNames.syncQueue,
      where: 'correlation_key = ?',
      whereArgs: [correlationKey],
      limit: 1,
    );

    if (rows.isEmpty) {
      final queueId = await db.insert(TableNames.syncQueue, {
        'feature_key': featureKey,
        'entity_type': entityType,
        'local_entity_id': localEntityId,
        'local_uuid': localUuid,
        'remote_id': remoteId,
        'operation_type': operation.storageValue,
        'status': _statusForOperation(operation).storageValue,
        'attempt_count': 0,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'locked_at': null,
        'last_processed_at': null,
        'correlation_key': correlationKey,
        'local_updated_at': localUpdatedAt.toIso8601String(),
        'remote_updated_at': null,
        'conflict_reason': null,
      });
      await _auditRepository.log(
        executor: db,
        featureKey: featureKey,
        entityType: entityType,
        localEntityId: localEntityId,
        localUuid: localUuid,
        remoteId: remoteId,
        eventType: SyncAuditEventType.queued,
        message: 'Item enfileirado para ${operation.storageValue}.',
        details: <String, dynamic>{
          'queueId': queueId,
          'operation': operation.storageValue,
          'status': _statusForOperation(operation).storageValue,
          'localUpdatedAt': localUpdatedAt.toIso8601String(),
          'correlationKey': correlationKey,
        },
        createdAt: now,
      );
      return;
    }

    final existing = _mapRow(rows.first);
    if (operation == SyncQueueOperation.delete &&
        existing.operation == SyncQueueOperation.create &&
        (remoteId ?? existing.remoteId) == null) {
      await db.delete(
        TableNames.syncQueue,
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      await _auditRepository.log(
        executor: db,
        featureKey: existing.featureKey,
        entityType: existing.entityType,
        localEntityId: existing.localEntityId,
        localUuid: existing.localUuid,
        remoteId: existing.remoteId,
        eventType: SyncAuditEventType.queueCompacted,
        message:
            'A fila foi consolidada e removeu um create local ainda nao sincronizado.',
        details: <String, dynamic>{
          'queueId': existing.id,
          'operation': existing.operation.storageValue,
          'requestedOperation': operation.storageValue,
          'correlationKey': correlationKey,
        },
        createdAt: now,
      );
      return;
    }

    final mergedOperation = _mergeOperation(
      current: existing.operation,
      next: operation,
      remoteId: remoteId ?? existing.remoteId,
    );

    await db.update(
      TableNames.syncQueue,
      {
        'entity_type': entityType,
        'local_uuid': localUuid ?? existing.localUuid,
        'remote_id': remoteId,
        'operation_type': mergedOperation.storageValue,
        'status': _statusForOperation(mergedOperation).storageValue,
        'attempt_count': 0,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'updated_at': now.toIso8601String(),
        'locked_at': null,
        'last_processed_at': existing.lastProcessedAt?.toIso8601String(),
        'local_updated_at': localUpdatedAt.toIso8601String(),
        'remote_updated_at': null,
        'conflict_reason': null,
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    await _auditRepository.log(
      executor: db,
      featureKey: existing.featureKey,
      entityType: entityType,
      localEntityId: localEntityId,
      localUuid: localUuid ?? existing.localUuid,
      remoteId: remoteId,
      eventType: SyncAuditEventType.queueCompacted,
      message: 'A fila consolidou mutacoes repetidas para o mesmo registro.',
      details: <String, dynamic>{
        'queueId': existing.id,
        'previousOperation': existing.operation.storageValue,
        'mergedOperation': mergedOperation.storageValue,
        'localUpdatedAt': localUpdatedAt.toIso8601String(),
        'correlationKey': correlationKey,
      },
      createdAt: now,
    );
  }

  String _buildCorrelationKey({
    required String featureKey,
    required String entityType,
    required int localEntityId,
  }) {
    return '$featureKey:$entityType:$localEntityId';
  }

  @override
  Future<void> removeForEntity(
    DatabaseExecutor db, {
    required String featureKey,
    required int localEntityId,
  }) async {
    await db.delete(
      TableNames.syncQueue,
      where: 'feature_key = ? AND local_entity_id = ?',
      whereArgs: [featureKey, localEntityId],
    );
  }

  @override
  Future<List<SyncQueueItem>> listEligibleItems({
    Iterable<String>? featureKeys,
    required bool retryOnly,
    DateTime? now,
  }) async {
    final database = await _appDatabase.database;
    final currentTime = now ?? DateTime.now();
    final rows = await database.query(
      TableNames.syncQueue,
      orderBy: 'updated_at ASC, id ASC',
    );

    return rows
        .map(_mapRow)
        .where(
          (item) => _isEligible(
            item,
            retryOnly: retryOnly,
            now: currentTime,
            featureKeys: featureKeys,
          ),
        )
        .toList();
  }

  @override
  Future<SyncQueueItem?> lockItem(int queueId, {DateTime? now}) async {
    final database = await _appDatabase.database;
    final currentTime = now ?? DateTime.now();
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final item = _mapRow(rows.first);
    final isLocked =
        item.lockedAt != null &&
        currentTime.difference(item.lockedAt!) < staleLockThreshold;
    if (isLocked && item.status == SyncQueueStatus.processing) {
      return null;
    }

    await database.update(
      TableNames.syncQueue,
      {
        'status': SyncQueueStatus.processing.storageValue,
        'attempt_count': item.attemptCount + 1,
        'locked_at': currentTime.toIso8601String(),
        'updated_at': currentTime.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
    await _auditRepository.log(
      featureKey: item.featureKey,
      entityType: item.entityType,
      localEntityId: item.localEntityId,
      localUuid: item.localUuid,
      remoteId: item.remoteId,
      eventType: SyncAuditEventType.processingStarted,
      message: 'Processamento iniciado pela fila local.',
      details: <String, dynamic>{
        'queueId': item.id,
        'attemptCount': item.attemptCount + 1,
        'operation': item.operation.storageValue,
      },
      createdAt: currentTime,
    );

    final lockedRows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    if (lockedRows.isEmpty) {
      return null;
    }

    return _mapRow(lockedRows.first);
  }

  @override
  Future<void> markSynced(
    int queueId, {
    required String? remoteId,
    required DateTime processedAt,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    final item = rows.isEmpty ? null : _mapRow(rows.first);
    await database.update(
      TableNames.syncQueue,
      {
        'remote_id': remoteId,
        'status': SyncQueueStatus.synced.storageValue,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'updated_at': processedAt.toIso8601String(),
        'locked_at': null,
        'last_processed_at': processedAt.toIso8601String(),
        'remote_updated_at': processedAt.toIso8601String(),
        'conflict_reason': null,
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
    if (item != null) {
      await _auditRepository.log(
        featureKey: item.featureKey,
        entityType: item.entityType,
        localEntityId: item.localEntityId,
        localUuid: item.localUuid,
        remoteId: remoteId ?? item.remoteId,
        eventType: SyncAuditEventType.synced,
        message: 'Item sincronizado com sucesso.',
        details: <String, dynamic>{
          'queueId': item.id,
          'operation': item.operation.storageValue,
          'attemptCount': item.attemptCount,
        },
        createdAt: processedAt,
      );
    }
  }

  @override
  Future<void> markBlocked(
    int queueId, {
    required String reason,
    required DateTime blockedAt,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    final item = rows.isEmpty ? null : _mapRow(rows.first);
    await database.update(
      TableNames.syncQueue,
      {
        'status': SyncQueueStatus.blockedDependency.storageValue,
        'next_retry_at': null,
        'last_error': reason,
        'last_error_type': SyncErrorType.dependency.storageValue,
        'updated_at': blockedAt.toIso8601String(),
        'locked_at': null,
        'last_processed_at': blockedAt.toIso8601String(),
        'conflict_reason': null,
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
    if (item != null) {
      await _auditRepository.log(
        featureKey: item.featureKey,
        entityType: item.entityType,
        localEntityId: item.localEntityId,
        localUuid: item.localUuid,
        remoteId: item.remoteId,
        eventType: SyncAuditEventType.blockedDependency,
        message: reason,
        details: <String, dynamic>{
          'queueId': item.id,
          'operation': item.operation.storageValue,
          'attemptCount': item.attemptCount,
        },
        createdAt: blockedAt,
      );
    }
  }

  @override
  Future<void> markConflict(
    int queueId, {
    required SyncConflictInfo conflict,
    required DateTime processedAt,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    final item = rows.isEmpty ? null : _mapRow(rows.first);
    await database.update(
      TableNames.syncQueue,
      {
        'status': SyncQueueStatus.conflict.storageValue,
        'next_retry_at': null,
        'last_error': conflict.reason,
        'last_error_type': SyncErrorType.conflict.storageValue,
        'updated_at': processedAt.toIso8601String(),
        'locked_at': null,
        'last_processed_at': processedAt.toIso8601String(),
        'local_updated_at': conflict.localUpdatedAt.toIso8601String(),
        'remote_updated_at': conflict.remoteUpdatedAt.toIso8601String(),
        'conflict_reason': conflict.reason,
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
    if (item != null) {
      await _auditRepository.log(
        featureKey: item.featureKey,
        entityType: item.entityType,
        localEntityId: item.localEntityId,
        localUuid: item.localUuid,
        remoteId: item.remoteId,
        eventType: SyncAuditEventType.conflictDetected,
        message: conflict.reason,
        details: <String, dynamic>{
          'queueId': item.id,
          'operation': item.operation.storageValue,
          'localUpdatedAt': conflict.localUpdatedAt.toIso8601String(),
          'remoteUpdatedAt': conflict.remoteUpdatedAt.toIso8601String(),
        },
        createdAt: processedAt,
      );
    }
  }

  @override
  Future<void> markFailure(
    int queueId, {
    required String message,
    required SyncErrorType errorType,
    required DateTime processedAt,
    required DateTime? nextRetryAt,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    final item = rows.isEmpty ? null : _mapRow(rows.first);
    await database.update(
      TableNames.syncQueue,
      {
        'status': SyncQueueStatus.syncError.storageValue,
        'next_retry_at': nextRetryAt?.toIso8601String(),
        'last_error': message,
        'last_error_type': errorType.storageValue,
        'updated_at': processedAt.toIso8601String(),
        'locked_at': null,
        'last_processed_at': processedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
    if (item != null) {
      await _auditRepository.log(
        featureKey: item.featureKey,
        entityType: item.entityType,
        localEntityId: item.localEntityId,
        localUuid: item.localUuid,
        remoteId: item.remoteId,
        eventType: SyncAuditEventType.failed,
        message: message,
        details: <String, dynamic>{
          'queueId': item.id,
          'operation': item.operation.storageValue,
          'errorType': errorType.storageValue,
          'nextRetryAt': nextRetryAt?.toIso8601String(),
        },
        createdAt: processedAt,
      );
    }
  }

  @override
  Future<void> reenqueueAsCreate(
    int queueId, {
    required DateTime requeuedAt,
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    final item = rows.isEmpty ? null : _mapRow(rows.first);
    if (item == null) {
      return;
    }

    await database.update(
      TableNames.syncQueue,
      {
        'remote_id': null,
        'operation_type': SyncQueueOperation.create.storageValue,
        'status': SyncQueueStatus.pendingUpload.storageValue,
        'attempt_count': 0,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'updated_at': requeuedAt.toIso8601String(),
        'locked_at': null,
        'last_processed_at': requeuedAt.toIso8601String(),
        'remote_updated_at': null,
        'conflict_reason': null,
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );

    await _auditRepository.log(
      executor: database,
      featureKey: item.featureKey,
      entityType: item.entityType,
      localEntityId: item.localEntityId,
      localUuid: item.localUuid,
      remoteId: item.remoteId,
      eventType: SyncAuditEventType.queueReenqueuedAsCreate,
      message: 'Registro remoto antigo nao existe mais; item foi reenfileirado como criacao.',
      details: <String, dynamic>{
        'queueId': item.id,
        'previousOperation': item.operation.storageValue,
        'previousStatus': item.status.storageValue,
        'newOperation': SyncQueueOperation.create.storageValue,
        'newStatus': SyncQueueStatus.pendingUpload.storageValue,
        'correlationKey': item.correlationKey,
      },
      createdAt: requeuedAt,
    );
  }

  @override
  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.syncQueue,
      orderBy: 'feature_key ASC, updated_at DESC',
    );

    final grouped = <String, List<SyncQueueItem>>{};
    for (final row in rows) {
      final item = _mapRow(row);
      grouped.putIfAbsent(item.featureKey, () => <SyncQueueItem>[]).add(item);
    }

    return grouped.entries.map((entry) {
      final items = entry.value;
      var pendingCount = 0;
      var processingCount = 0;
      var syncedCount = 0;
      var errorCount = 0;
      var blockedCount = 0;
      var conflictCount = 0;
      var totalAttemptCount = 0;
      DateTime? lastProcessedAt;
      DateTime? nextRetryAt;
      String? lastError;
      SyncErrorType? lastErrorType;
      DateTime? lastErrorAt;

      for (final item in items) {
        totalAttemptCount += item.attemptCount;
        switch (item.status) {
          case SyncQueueStatus.pendingUpload:
          case SyncQueueStatus.pendingUpdate:
            pendingCount++;
            break;
          case SyncQueueStatus.processing:
            processingCount++;
            break;
          case SyncQueueStatus.synced:
            syncedCount++;
            break;
          case SyncQueueStatus.syncError:
            errorCount++;
            break;
          case SyncQueueStatus.blockedDependency:
            blockedCount++;
            break;
          case SyncQueueStatus.conflict:
            conflictCount++;
            break;
        }

        if (item.lastProcessedAt != null &&
            (lastProcessedAt == null ||
                item.lastProcessedAt!.isAfter(lastProcessedAt))) {
          lastProcessedAt = item.lastProcessedAt;
        }

        if (item.nextRetryAt != null &&
            (nextRetryAt == null || item.nextRetryAt!.isBefore(nextRetryAt))) {
          nextRetryAt = item.nextRetryAt;
        }

        if (item.lastError != null &&
            (lastErrorAt == null || item.updatedAt.isAfter(lastErrorAt))) {
          lastErrorAt = item.updatedAt;
          lastError = item.lastError;
          lastErrorType = item.lastErrorType;
        }
      }

      return SyncQueueFeatureSummary(
        featureKey: entry.key,
        displayName: _displayNameFor(entry.key),
        totalTracked: items.length,
        pendingCount: pendingCount,
        processingCount: processingCount,
        syncedCount: syncedCount,
        errorCount: errorCount,
        blockedCount: blockedCount,
        conflictCount: conflictCount,
        totalAttemptCount: totalAttemptCount,
        lastProcessedAt: lastProcessedAt,
        nextRetryAt: nextRetryAt,
        lastError: lastError,
        lastErrorType: lastErrorType,
      );
    }).toList();
  }

  bool _isEligible(
    SyncQueueItem item, {
    required bool retryOnly,
    required DateTime now,
    required Iterable<String>? featureKeys,
  }) {
    if (featureKeys != null && !featureKeys.contains(item.featureKey)) {
      return false;
    }

    final lockIsFresh =
        item.lockedAt != null &&
        now.difference(item.lockedAt!) < staleLockThreshold;
    if (item.status == SyncQueueStatus.processing && lockIsFresh) {
      return false;
    }

    if (item.status == SyncQueueStatus.synced ||
        item.status == SyncQueueStatus.conflict) {
      return false;
    }

    if (retryOnly && item.status == SyncQueueStatus.blockedDependency) {
      return false;
    }

    if (retryOnly &&
        item.status == SyncQueueStatus.syncError &&
        item.nextRetryAt != null &&
        item.nextRetryAt!.isAfter(now)) {
      return false;
    }

    return item.status == SyncQueueStatus.pendingUpload ||
        item.status == SyncQueueStatus.pendingUpdate ||
        item.status == SyncQueueStatus.syncError ||
        item.status == SyncQueueStatus.blockedDependency ||
        item.status == SyncQueueStatus.processing;
  }

  SyncQueueOperation _mergeOperation({
    required SyncQueueOperation current,
    required SyncQueueOperation next,
    required String? remoteId,
  }) {
    if (current == SyncQueueOperation.create &&
        next == SyncQueueOperation.update) {
      return SyncQueueOperation.create;
    }

    if (next == SyncQueueOperation.delete) {
      return SyncQueueOperation.delete;
    }

    if (next == SyncQueueOperation.cancel) {
      return SyncQueueOperation.cancel;
    }

    return next;
  }

  SyncQueueStatus _statusForOperation(SyncQueueOperation operation) {
    switch (operation) {
      case SyncQueueOperation.create:
        return SyncQueueStatus.pendingUpload;
      case SyncQueueOperation.update:
      case SyncQueueOperation.delete:
      case SyncQueueOperation.cancel:
        return SyncQueueStatus.pendingUpdate;
    }
  }

  SyncQueueItem _mapRow(Map<String, Object?> row) {
    return SyncQueueItem(
      id: row['id'] as int,
      featureKey: row['feature_key'] as String,
      entityType: row['entity_type'] as String,
      localEntityId: row['local_entity_id'] as int,
      localUuid: row['local_uuid'] as String?,
      remoteId: row['remote_id'] as String?,
      operation: syncQueueOperationFromStorage(
        row['operation_type'] as String?,
      ),
      status: syncQueueStatusFromStorage(row['status'] as String?),
      attemptCount: row['attempt_count'] as int? ?? 0,
      nextRetryAt: row['next_retry_at'] == null
          ? null
          : DateTime.parse(row['next_retry_at'] as String),
      lastError: row['last_error'] as String?,
      lastErrorType: row['last_error_type'] == null
          ? null
          : syncErrorTypeFromStorage(row['last_error_type'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lockedAt: row['locked_at'] == null
          ? null
          : DateTime.parse(row['locked_at'] as String),
      lastProcessedAt: row['last_processed_at'] == null
          ? null
          : DateTime.parse(row['last_processed_at'] as String),
      correlationKey: row['correlation_key'] as String,
      localUpdatedAt: row['local_updated_at'] == null
          ? null
          : DateTime.parse(row['local_updated_at'] as String),
      remoteUpdatedAt: row['remote_updated_at'] == null
          ? null
          : DateTime.parse(row['remote_updated_at'] as String),
      conflictReason: row['conflict_reason'] as String?,
    );
  }

  String _displayNameFor(String featureKey) {
    return switch (featureKey) {
      SyncFeatureKeys.categories => 'Categorias',
      SyncFeatureKeys.supplies => 'Insumos',
      SyncFeatureKeys.products => 'Produtos',
      SyncFeatureKeys.productRecipes => 'Fichas tecnicas',
      SyncFeatureKeys.customers => 'Clientes',
      SyncFeatureKeys.suppliers => 'Fornecedores',
      SyncFeatureKeys.purchases => 'Compras',
      SyncFeatureKeys.sales => 'Vendas',
      SyncFeatureKeys.financialEvents => 'Eventos financeiros',
      SyncFeatureKeys.saleCancellations => 'Cancelamentos de venda',
      SyncFeatureKeys.fiadoPayments => 'Pagamentos de fiado',
      SyncFeatureKeys.cashEvents => 'Eventos de caixa',
      SyncFeatureKeys.fiado => 'Fiado',
      SyncFeatureKeys.cashMovements => 'Movimentos de caixa',
      _ => featureKey,
    };
  }
}
