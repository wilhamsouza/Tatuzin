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
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/supplier.dart';
import '../domain/repositories/supplier_repository.dart';
import 'models/remote_supplier_record.dart';
import 'models/supplier_model.dart';

class SqliteSupplierRepository implements SupplierRepository {
  SqliteSupplierRepository(this._appDatabase)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase),
      _remoteIdentityRecovery = SyncRemoteIdentityRecovery(_appDatabase);

  static const String featureKey = SyncFeatureKeys.suppliers;

  final AppDatabase _appDatabase;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final SyncRemoteIdentityRecovery _remoteIdentityRecovery;

  @override
  Future<int> create(SupplierInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    final uuid = IdGenerator.next();

    return database.transaction((txn) async {
      final id = await txn.insert(TableNames.fornecedores, {
        'uuid': uuid,
        'nome': input.name.trim(),
        'nome_fantasia': _cleanNullable(input.tradeName),
        'telefone': _cleanNullable(input.phone),
        'email': _cleanNullable(input.email),
        'endereco': _cleanNullable(input.address),
        'documento': _cleanNullable(input.document),
        'contato_responsavel': _cleanNullable(input.contactPerson),
        'observacao': _cleanNullable(input.notes),
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
        entityType: 'supplier',
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
        TableNames.fornecedores,
        {
          'ativo': 0,
          'atualizado_em': now.toIso8601String(),
          'deletado_em': now.toIso8601String(),
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
        entityType: 'supplier',
        localEntityId: id,
        localUuid: existing['uuid'] as String,
        remoteId: remoteId,
        operation: SyncQueueOperation.delete,
        localUpdatedAt: now,
      );
    });
  }

  @override
  Future<Supplier?> findById(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectBaseQuery(includeDeleted: true)} AND f.id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return SupplierModel.fromMap(rows.first);
  }

  Future<Supplier?> findByRemoteId(String remoteId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectBaseQuery(includeDeleted: true)} AND sync.remote_id = ? LIMIT 1',
      [remoteId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return SupplierModel.fromMap(rows.first);
  }

  Future<List<Supplier>> listForSync() async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectBaseQuery(includeDeleted: true)}'
      '''
      GROUP BY ${_groupByColumns()}
      ORDER BY f.atualizado_em DESC, f.nome COLLATE NOCASE ASC
    ''',
    );
    return rows.map(SupplierModel.fromMap).toList();
  }

  @override
  Future<List<Supplier>> search({String query = ''}) async {
    final database = await _appDatabase.database;
    final trimmedQuery = query.trim();
    final args = <Object?>[];
    final buffer = StringBuffer(_selectBaseQuery(includeDeleted: false));

    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
        AND (
          f.nome LIKE ? COLLATE NOCASE
          OR COALESCE(f.nome_fantasia, '') LIKE ? COLLATE NOCASE
          OR COALESCE(f.telefone, '') LIKE ? COLLATE NOCASE
          OR COALESCE(f.documento, '') LIKE ? COLLATE NOCASE
        )
      ''');
      for (var index = 0; index < 4; index++) {
        args.add('%$trimmedQuery%');
      }
    }

    buffer.write('''
      GROUP BY ${_groupByColumns()}
      ORDER BY f.ativo DESC, f.nome COLLATE NOCASE ASC
    ''');

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(SupplierModel.fromMap).toList();
  }

  @override
  Future<void> update(int id, SupplierInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        return;
      }

      await txn.update(
        TableNames.fornecedores,
        {
          'nome': input.name.trim(),
          'nome_fantasia': _cleanNullable(input.tradeName),
          'telefone': _cleanNullable(input.phone),
          'email': _cleanNullable(input.email),
          'endereco': _cleanNullable(input.address),
          'documento': _cleanNullable(input.document),
          'contato_responsavel': _cleanNullable(input.contactPerson),
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
        entityType: 'supplier',
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

  Future<void> upsertFromRemote(RemoteSupplierRecord remote) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final localMatch = await _findLocalMatchForRemote(txn, remote);
      int localId;
      String localUuid;
      DateTime createdAt;

      if (localMatch != null) {
        localId = localMatch.localId;
        localUuid = localMatch.localUuid;
        createdAt = localMatch.createdAt;

        final existing = await _findRowById(txn, localId);
        if (existing != null) {
          final localUpdatedAt = DateTime.parse(
            existing['atualizado_em'] as String,
          );
          if (localUpdatedAt.isAfter(remote.updatedAt)) {
            return;
          }
        }

        await txn.update(
          TableNames.fornecedores,
          {
            'nome': remote.name,
            'nome_fantasia': remote.tradeName,
            'telefone': remote.phone,
            'email': remote.email,
            'endereco': remote.address,
            'documento': remote.document,
            'contato_responsavel': remote.contactPerson,
            'observacao': remote.notes,
            'ativo': remote.isActive ? 1 : 0,
            'atualizado_em': remote.updatedAt.toIso8601String(),
            'deletado_em': remote.deletedAt?.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      } else {
        localUuid = remote.localUuid.trim().isNotEmpty
            ? remote.localUuid.trim()
            : IdGenerator.next();
        createdAt = remote.createdAt;
        localId = await txn.insert(TableNames.fornecedores, {
          'uuid': localUuid,
          'nome': remote.name,
          'nome_fantasia': remote.tradeName,
          'telefone': remote.phone,
          'email': remote.email,
          'endereco': remote.address,
          'documento': remote.document,
          'contato_responsavel': remote.contactPerson,
          'observacao': remote.notes,
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
        origin: localMatch == null ? RecordOrigin.remote : RecordOrigin.merged,
        createdAt: createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  Future<void> applyPushResult({
    required Supplier supplier,
    required RemoteSupplierRecord remote,
  }) async {
    final database = await _appDatabase.database;
    final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
      database,
      featureKey: featureKey,
      remoteId: remote.remoteId,
    );

    if (metadataByRemoteId != null &&
        metadataByRemoteId.identity.localId != null &&
        metadataByRemoteId.identity.localId != supplier.id) {
      await upsertFromRemote(remote);
      return;
    }

    await database.transaction((txn) async {
      await txn.update(
        TableNames.fornecedores,
        {
          'nome': remote.name,
          'nome_fantasia': remote.tradeName,
          'telefone': remote.phone,
          'email': remote.email,
          'endereco': remote.address,
          'documento': remote.document,
          'contato_responsavel': remote.contactPerson,
          'observacao': remote.notes,
          'ativo': remote.isActive ? 1 : 0,
          'atualizado_em': remote.updatedAt.toIso8601String(),
          'deletado_em': remote.deletedAt?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [supplier.id],
      );

      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: supplier.id,
        localUuid: supplier.uuid,
        remoteId: remote.remoteId,
        origin: RecordOrigin.merged,
        createdAt: supplier.createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  Future<void> markSyncError({
    required Supplier supplier,
    required String message,
    required SyncErrorType errorType,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      await _syncMetadataRepository.markSyncError(
        txn,
        featureKey: featureKey,
        localId: supplier.id,
        localUuid: supplier.uuid,
        remoteId: supplier.remoteId,
        createdAt: supplier.createdAt,
        updatedAt: now,
        message: message,
        errorType: errorType,
      );
    });
  }

  Future<void> markConflict({
    required Supplier supplier,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: featureKey,
        localId: supplier.id,
        localUuid: supplier.uuid,
        remoteId: supplier.remoteId,
        createdAt: supplier.createdAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> recoverMissingRemoteIdentity({
    required Supplier supplier,
    SyncQueueItem? queueItem,
  }) async {
    await _remoteIdentityRecovery.recoverForReupload(
      featureKey: featureKey,
      entityType: queueItem?.entityType ?? 'supplier',
      localEntityId: supplier.id,
      localUuid: supplier.uuid,
      staleRemoteId: supplier.remoteId ?? queueItem?.remoteId,
      createdAt: supplier.createdAt,
      updatedAt: supplier.updatedAt,
      queueItem: queueItem,
      entityLabel: 'fornecedor "${supplier.name}"',
    );
  }

  Future<_LocalSupplierMatch?> _findLocalMatchForRemote(
    DatabaseExecutor db,
    RemoteSupplierRecord remote,
  ) async {
    final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
      db,
      featureKey: featureKey,
      remoteId: remote.remoteId,
    );
    if (metadataByRemoteId?.identity.localId != null) {
      return _LocalSupplierMatch(
        localId: metadataByRemoteId!.identity.localId!,
        localUuid: metadataByRemoteId.identity.localUuid ?? IdGenerator.next(),
        createdAt: metadataByRemoteId.createdAt,
      );
    }

    if (remote.localUuid.trim().isNotEmpty) {
      final metadataByLocalUuid = await _syncMetadataRepository.findByLocalUuid(
        db,
        featureKey: featureKey,
        localUuid: remote.localUuid.trim(),
      );
      if (metadataByLocalUuid?.identity.localId != null) {
        return _LocalSupplierMatch(
          localId: metadataByLocalUuid!.identity.localId!,
          localUuid:
              metadataByLocalUuid.identity.localUuid ?? remote.localUuid.trim(),
          createdAt: metadataByLocalUuid.createdAt,
        );
      }

      final rows = await db.query(
        TableNames.fornecedores,
        columns: const ['id', 'uuid', 'criado_em'],
        where: 'uuid = ?',
        whereArgs: [remote.localUuid.trim()],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return _LocalSupplierMatch(
          localId: rows.first['id'] as int,
          localUuid: rows.first['uuid'] as String,
          createdAt: DateTime.parse(rows.first['criado_em'] as String),
        );
      }
    }

    final normalizedDocument = _normalizeIdentityValue(remote.document);
    if (normalizedDocument != null) {
      final rows = await db.query(
        TableNames.fornecedores,
        columns: const ['id', 'uuid', 'criado_em'],
        where: 'documento = ?',
        whereArgs: [remote.document],
        limit: 2,
      );
      if (rows.length == 1) {
        final metadata = await _syncMetadataRepository.findByLocalId(
          db,
          featureKey: featureKey,
          localId: rows.first['id'] as int,
        );
        if (metadata?.identity.remoteId == null) {
          return _LocalSupplierMatch(
            localId: rows.first['id'] as int,
            localUuid: rows.first['uuid'] as String,
            createdAt: DateTime.parse(rows.first['criado_em'] as String),
          );
        }
      }
    }

    return null;
  }

  String _selectBaseQuery({required bool includeDeleted}) {
    final buffer = StringBuffer('''
      SELECT
        f.*,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        COALESCE(
          SUM(
            CASE
              WHEN c.status IN ('aberta', 'recebida', 'parcialmente_paga')
                THEN c.valor_pendente_centavos
              ELSE 0
            END
          ),
          0
        ) AS pendencia_centavos,
        COALESCE(
          SUM(
            CASE
              WHEN c.status IN ('aberta', 'recebida', 'parcialmente_paga')
                THEN 1
              ELSE 0
            END
          ),
          0
        ) AS pendencia_quantidade
      FROM ${TableNames.fornecedores} f
      LEFT JOIN ${TableNames.compras} c
        ON c.fornecedor_id = f.id
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = f.id
      WHERE 1 = 1
    ''');

    if (!includeDeleted) {
      buffer.write(' AND f.deletado_em IS NULL');
    }

    return buffer.toString();
  }

  String _groupByColumns() {
    return '''
      f.id,
      f.uuid,
      f.nome,
      f.nome_fantasia,
      f.telefone,
      f.email,
      f.endereco,
      f.documento,
      f.contato_responsavel,
      f.observacao,
      f.ativo,
      f.criado_em,
      f.atualizado_em,
      f.deletado_em,
      sync.remote_id,
      sync.sync_status,
      sync.last_synced_at
    ''';
  }

  Future<Map<String, Object?>?> _findRowById(
    DatabaseExecutor db,
    int id,
  ) async {
    final rows = await db.query(
      TableNames.fornecedores,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeIdentityValue(String? value) {
    final cleaned = _cleanNullable(value);
    return cleaned?.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  }
}

class _LocalSupplierMatch {
  const _LocalSupplierMatch({
    required this.localId,
    required this.localUuid,
    required this.createdAt,
  });

  final int localId;
  final String localUuid;
  final DateTime createdAt;
}
