import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/record_identity.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_error_type.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_remote_identity_recovery.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/client.dart';
import '../domain/repositories/client_repository.dart';
import 'models/remote_customer_record.dart';

class SqliteClientRepository implements ClientRepository {
  SqliteClientRepository(this._appDatabase)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase),
      _remoteIdentityRecovery = SyncRemoteIdentityRecovery(_appDatabase);

  static const String featureKey = SyncFeatureKeys.customers;

  final AppDatabase _appDatabase;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final SyncRemoteIdentityRecovery _remoteIdentityRecovery;

  @override
  Future<int> create(ClientInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    final uuid = IdGenerator.next();

    return database.transaction((txn) async {
      final id = await txn.insert(TableNames.clientes, {
        'uuid': uuid,
        'nome': input.name.trim(),
        'telefone': _cleanNullable(input.phone),
        'endereco': _cleanNullable(input.address),
        'observacao': _cleanNullable(input.notes),
        'saldo_devedor_centavos': 0,
        'credit_balance': 0,
        'ativo': input.isActive ? 1 : 0,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'deletado_em': null,
      });

      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: uuid,
        createdAt: now,
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'customer',
        localEntityId: id,
        localUuid: uuid,
        remoteId: null,
        operation: SyncQueueOperation.create,
        localUpdatedAt: now,
      );

      return id;
    });
  }

  @override
  Future<void> delete(int id) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        return;
      }

      await txn.update(
        TableNames.clientes,
        {
          'ativo': 0,
          'deletado_em': now.toIso8601String(),
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: id,
      );

      if (metadata?.identity.remoteId == null) {
        await _syncMetadataRepository.removeByLocalId(
          txn,
          featureKey: featureKey,
          localId: id,
        );
        await _syncQueueRepository.removeForEntity(
          txn,
          featureKey: featureKey,
          localEntityId: id,
        );
        return;
      }

      final remoteId = metadata!.identity.remoteId;

      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: existing['uuid'] as String,
        remoteId: remoteId,
        createdAt: DateTime.parse(existing['criado_em'] as String),
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'customer',
        localEntityId: id,
        localUuid: existing['uuid'] as String,
        remoteId: remoteId,
        operation: SyncQueueOperation.delete,
        localUpdatedAt: now,
      );
    });
  }

  @override
  Future<List<Client>> search({String query = ''}) async {
    final database = await _appDatabase.database;
    final trimmedQuery = query.trim();

    final buffer = StringBuffer(_selectQuery(includeDeleted: false));
    final args = <Object?>[];

    if (trimmedQuery.isNotEmpty) {
      buffer.write(' AND c.nome LIKE ? COLLATE NOCASE');
      args.add('%$trimmedQuery%');
    }

    buffer.write(' ORDER BY c.nome COLLATE NOCASE ASC');

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapClient).toList();
  }

  @override
  Future<void> update(int id, ClientInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        return;
      }

      await txn.update(
        TableNames.clientes,
        {
          'nome': input.name.trim(),
          'telefone': _cleanNullable(input.phone),
          'endereco': _cleanNullable(input.address),
          'observacao': _cleanNullable(input.notes),
          'ativo': input.isActive ? 1 : 0,
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: id,
      );

      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: existing['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        createdAt: DateTime.parse(existing['criado_em'] as String),
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'customer',
        localEntityId: id,
        localUuid: existing['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        operation: metadata?.identity.remoteId == null
            ? SyncQueueOperation.create
            : SyncQueueOperation.update,
        localUpdatedAt: now,
      );
    });
  }

  Future<List<Client>> listForSync() async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectQuery(includeDeleted: true)}'
      ' ORDER BY c.atualizado_em DESC, c.nome COLLATE NOCASE ASC',
    );
    return rows.map(_mapClient).toList();
  }

  Future<Client?> findById(int id, {bool includeDeleted = true}) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectQuery(includeDeleted: includeDeleted)}'
      '''
        AND c.id = ?
        LIMIT 1
      ''',
      [id],
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapClient(rows.first);
  }

  Future<Client?> findByRemoteId(String remoteId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectQuery(includeDeleted: true)}'
      '''
        AND sync.remote_id = ?
        LIMIT 1
      ''',
      [remoteId],
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapClient(rows.first);
  }

  Future<void> upsertFromRemote(RemoteCustomerRecord remote) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
        txn,
        featureKey: featureKey,
        remoteId: remote.remoteId,
      );
      final metadataByLocalUuid = await _syncMetadataRepository.findByLocalUuid(
        txn,
        featureKey: featureKey,
        localUuid: remote.localUuid,
      );
      final metadata = metadataByRemoteId ?? metadataByLocalUuid;

      int localId;
      String localUuid;
      DateTime createdAt;
      final syncedAt = DateTime.now();
      Map<String, Object?>? existing;

      if (metadata != null && metadata.identity.localId != null) {
        localId = metadata.identity.localId!;
        existing = await _findRowById(txn, localId);
      } else {
        existing = await _findRowByUuid(txn, remote.localUuid);
        localId = (existing?['id'] as int?) ?? -1;
      }

      if (existing != null) {
        final localUpdatedAt = DateTime.parse(
          existing['atualizado_em'] as String,
        );
        if (localUpdatedAt.isAfter(remote.updatedAt)) {
          await _syncMetadataRepository.markPendingUpdate(
            txn,
            featureKey: featureKey,
            localId: existing['id'] as int,
            localUuid: existing['uuid'] as String,
            remoteId: remote.remoteId,
            createdAt: DateTime.parse(existing['criado_em'] as String),
            updatedAt: localUpdatedAt,
          );
          await _syncQueueRepository.enqueueMutation(
            txn,
            featureKey: featureKey,
            entityType: 'customer',
            localEntityId: existing['id'] as int,
            localUuid: existing['uuid'] as String,
            remoteId: remote.remoteId,
            operation: SyncQueueOperation.update,
            localUpdatedAt: localUpdatedAt,
          );
          return;
        }

        localUuid = existing['uuid'] as String;
        createdAt = DateTime.parse(existing['criado_em'] as String);
        localId = existing['id'] as int;

        await txn.update(
          TableNames.clientes,
          {
            'nome': remote.name,
            'telefone': remote.phone,
            'endereco': remote.address,
            'observacao': remote.notes,
            'credit_balance': existing['credit_balance'] as int? ?? 0,
            'ativo': remote.isActive ? 1 : 0,
            'atualizado_em': remote.updatedAt.toIso8601String(),
            'deletado_em': remote.deletedAt?.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      } else {
        localUuid = remote.localUuid;
        createdAt = remote.createdAt;
        localId = await txn.insert(TableNames.clientes, {
          'uuid': localUuid,
          'nome': remote.name,
          'telefone': remote.phone,
          'endereco': remote.address,
          'observacao': remote.notes,
          'saldo_devedor_centavos': 0,
          'credit_balance': 0,
          'ativo': remote.isActive ? 1 : 0,
          'criado_em': remote.createdAt.toIso8601String(),
          'atualizado_em': remote.updatedAt.toIso8601String(),
          'deletado_em': remote.deletedAt?.toIso8601String(),
        });
      }

      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: localId,
        localUuid: localUuid,
        remoteId: remote.remoteId,
        origin: existing == null ? RecordOrigin.remote : RecordOrigin.merged,
        createdAt: createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: syncedAt,
      );
    });
  }

  Future<void> applyPushResult({
    required Client client,
    required RemoteCustomerRecord remote,
  }) async {
    final database = await _appDatabase.database;
    final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
      database,
      featureKey: featureKey,
      remoteId: remote.remoteId,
    );

    if (metadataByRemoteId != null &&
        metadataByRemoteId.identity.localId != null &&
        metadataByRemoteId.identity.localId != client.id) {
      await upsertFromRemote(remote);
      return;
    }

    await database.transaction((txn) async {
      await txn.update(
        TableNames.clientes,
        {
          'nome': remote.name,
          'telefone': remote.phone,
          'endereco': remote.address,
          'observacao': remote.notes,
          'ativo': remote.isActive ? 1 : 0,
          'atualizado_em': remote.updatedAt.toIso8601String(),
          'deletado_em': remote.deletedAt?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [client.id],
      );

      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: client.id,
        localUuid: client.uuid,
        remoteId: remote.remoteId,
        origin: RecordOrigin.merged,
        createdAt: client.createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  Future<void> markSyncError({
    required Client client,
    required String message,
    required SyncErrorType errorType,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      await _syncMetadataRepository.markSyncError(
        txn,
        featureKey: featureKey,
        localId: client.id,
        localUuid: client.uuid,
        remoteId: client.remoteId,
        createdAt: client.createdAt,
        updatedAt: now,
        message: message,
        errorType: errorType,
      );
    });
  }

  Future<void> markConflict({
    required Client client,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: featureKey,
        localId: client.id,
        localUuid: client.uuid,
        remoteId: client.remoteId,
        createdAt: client.createdAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> recoverMissingRemoteIdentity({
    required Client client,
    SyncQueueItem? queueItem,
  }) async {
    await _remoteIdentityRecovery.recoverForReupload(
      featureKey: featureKey,
      entityType: queueItem?.entityType ?? 'customer',
      localEntityId: client.id,
      localUuid: client.uuid,
      staleRemoteId: client.remoteId ?? queueItem?.remoteId,
      createdAt: client.createdAt,
      updatedAt: client.updatedAt,
      queueItem: queueItem,
      entityLabel: 'cliente "${client.name}"',
    );
  }

  String _selectQuery({required bool includeDeleted}) {
    final buffer = StringBuffer('''
      SELECT
        c.*,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at
      FROM ${TableNames.clientes} c
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = c.id
      WHERE 1 = 1
    ''');

    if (!includeDeleted) {
      buffer.write(' AND c.deletado_em IS NULL');
    }

    return buffer.toString();
  }

  Future<Map<String, Object?>?> _findRowById(
    DatabaseExecutor db,
    int id,
  ) async {
    final rows = await db.query(
      TableNames.clientes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<Map<String, Object?>?> _findRowByUuid(
    DatabaseExecutor db,
    String uuid,
  ) async {
    final rows = await db.query(
      TableNames.clientes,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Client _mapClient(Map<String, Object?> row) {
    return Client(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      name: row['nome'] as String,
      phone: row['telefone'] as String?,
      address: row['endereco'] as String?,
      notes: row['observacao'] as String?,
      debtorBalanceCents: row['saldo_devedor_centavos'] as int,
      creditBalanceCents: row['credit_balance'] as int? ?? 0,
      isActive: (row['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      deletedAt: row['deletado_em'] == null
          ? null
          : DateTime.parse(row['deletado_em'] as String),
      remoteId: row['sync_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(row['sync_status'] as String?),
      lastSyncedAt: row['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(row['sync_last_synced_at'] as String),
    );
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
