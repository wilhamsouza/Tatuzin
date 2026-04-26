import 'package:sqflite/sqflite.dart';

import '../database/table_names.dart';
import 'reconciliation_local_comparable_record.dart';
import 'reconciliation_local_record_mapper.dart';
import 'sync_feature_keys.dart';
import 'sync_metadata.dart';
import 'sync_queue_item.dart';

class ReconciliationLocalSimpleLoader {
  const ReconciliationLocalSimpleLoader._();

  static Future<List<ReconciliationLocalComparableRecord>> loadCategories(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final rows = await database.rawQuery('''
      SELECT
        id,
        uuid,
        nome,
        descricao,
        ativo,
        criado_em,
        atualizado_em,
        deletado_em
      FROM ${TableNames.categorias}
      ORDER BY nome COLLATE NOCASE ASC, id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return ReconciliationLocalRecordMapper.mapCategory(
        row,
        localId: localId,
        metadata: metadata,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.categories,
              'category',
              localId,
            )],
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
      );
    }).toList();
  }

  static Future<List<ReconciliationLocalComparableRecord>> loadCustomers(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final rows = await database.rawQuery('''
      SELECT
        id,
        uuid,
        nome,
        telefone,
        endereco,
        observacao,
        ativo,
        criado_em,
        atualizado_em,
        deletado_em
      FROM ${TableNames.clientes}
      ORDER BY nome COLLATE NOCASE ASC, id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return ReconciliationLocalRecordMapper.mapCustomer(
        row,
        localId: localId,
        metadata: metadata,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.customers,
              'customer',
              localId,
            )],
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
      );
    }).toList();
  }

  static Future<List<ReconciliationLocalComparableRecord>> loadSuppliers(
    DatabaseExecutor database, {
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final rows = await database.rawQuery('''
      SELECT
        id,
        uuid,
        nome,
        nome_fantasia,
        telefone,
        email,
        endereco,
        documento,
        contato_responsavel,
        observacao,
        ativo,
        criado_em,
        atualizado_em,
        deletado_em
      FROM ${TableNames.fornecedores}
      ORDER BY nome COLLATE NOCASE ASC, id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return ReconciliationLocalRecordMapper.mapSupplier(
        row,
        localId: localId,
        metadata: metadata,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.suppliers,
              'supplier',
              localId,
            )],
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
      );
    }).toList();
  }

  static String _entityKey(
    String featureKey,
    String entityType,
    int localEntityId,
  ) {
    return '$featureKey:$entityType:$localEntityId';
  }
}
