import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/record_identity.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_error_type.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_remote_identity_recovery.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/supply.dart';
import '../domain/entities/supply_cost_history_entry.dart';
import '../domain/entities/supply_inventory.dart';
import '../domain/services/supply_inventory_math.dart';
import '../domain/repositories/supply_repository.dart';
import 'models/remote_supply_record.dart';
import 'models/supply_sync_payload.dart';
import 'support/supply_cost_history_support.dart';
import 'support/supply_inventory_support.dart';
import 'support/supply_linked_product_support.dart';
import 'support/supply_sync_mutation_support.dart';

class SqliteSupplyRepository implements SupplyRepository {
  SqliteSupplyRepository(this._appDatabase)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase),
      _remoteIdentityRecovery = SyncRemoteIdentityRecovery(_appDatabase);

  static const String featureKey = SyncFeatureKeys.supplies;

  final AppDatabase _appDatabase;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final SyncRemoteIdentityRecovery _remoteIdentityRecovery;

  @override
  Future<int> create(SupplyInput input) async {
    final database = await _appDatabase.database;
    _validateInput(input);
    return database.transaction((txn) async {
      final now = DateTime.now();
      final uuid = IdGenerator.next();
      final id = await txn.insert(TableNames.supplies, {
        'uuid': uuid,
        'name': input.name.trim(),
        'sku': _cleanNullable(input.sku),
        'unit_type': SupplyUnitTypes.normalize(input.unitType),
        'purchase_unit_type': SupplyUnitTypes.normalize(input.purchaseUnitType),
        'conversion_factor': input.conversionFactor,
        'last_purchase_price_cents': input.lastPurchasePriceCents,
        'average_purchase_price_cents': input.averagePurchasePriceCents,
        'current_stock_mil': null,
        'minimum_stock_mil': input.minimumStockMil,
        'default_supplier_id': input.defaultSupplierId,
        'is_active': input.isActive ? 1 : 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      if (input.lastPurchasePriceCents > 0 ||
          input.averagePurchasePriceCents != null) {
        await SupplyCostHistorySupport.recordManualSnapshot(
          txn,
          supplyId: id,
          snapshot: SupplyCostSnapshot(
            lastPurchasePriceCents: input.lastPurchasePriceCents,
            averagePurchasePriceCents: input.averagePurchasePriceCents,
            purchaseUnitType: SupplyUnitTypes.normalize(input.purchaseUnitType),
            conversionFactor: input.conversionFactor,
          ),
          changedAt: now,
          eventType: SupplyCostHistoryEventType.manualEdit,
          changeSummary: 'Cadastro inicial com referencia manual de custo.',
          notes: 'Referencia inicial informada no cadastro do insumo.',
        );
      }

      await SupplyInventorySupport.applyManualStockTarget(
        txn,
        supplyId: id,
        supplyUuid: uuid,
        targetStockMil: input.currentStockMil,
        occurredAt: now,
        notes: 'Saldo inicial informado no cadastro do insumo.',
      );

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
        entityType: 'supply',
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
  Future<void> deactivate(int id) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        return;
      }

      final now = DateTime.now();
      await txn.update(
        TableNames.supplies,
        {'is_active': 0, 'updated_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await SupplyLinkedProductSupport.recalculateLinkedProducts(
        txn,
        supplyIds: [id],
        changedAt: now,
        syncMetadataRepository: _syncMetadataRepository,
        syncQueueRepository: _syncQueueRepository,
      );

      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: id,
      );
      final localUuid = existing['uuid'] as String;
      final createdAt = DateTime.parse(existing['created_at'] as String);
      if (metadata?.identity.remoteId == null) {
        await _syncMetadataRepository.markPendingUpload(
          txn,
          featureKey: featureKey,
          localId: id,
          localUuid: localUuid,
          createdAt: createdAt,
          updatedAt: now,
        );
        await _syncQueueRepository.enqueueMutation(
          txn,
          featureKey: featureKey,
          entityType: 'supply',
          localEntityId: id,
          localUuid: localUuid,
          remoteId: null,
          operation: SyncQueueOperation.create,
          localUpdatedAt: now,
        );
        return;
      }

      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: localUuid,
        remoteId: metadata!.identity.remoteId,
        createdAt: createdAt,
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'supply',
        localEntityId: id,
        localUuid: localUuid,
        remoteId: metadata.identity.remoteId,
        operation: SyncQueueOperation.update,
        localUpdatedAt: now,
      );
    });
  }

  @override
  Future<Supply?> findById(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        s.*,
        f.nome AS default_supplier_name
      FROM ${TableNames.supplies} s
      LEFT JOIN ${TableNames.fornecedores} f
        ON f.id = s.default_supplier_id
      WHERE s.id = ?
      LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapSupply(rows.first);
  }

  @override
  Future<List<SupplyInventoryOverview>> listInventoryOverview({
    String query = '',
  }) async {
    final database = await _appDatabase.database;
    final trimmedQuery = query.trim();
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        s.*,
        f.nome AS default_supplier_name,
        COUNT(sim.id) AS movement_count,
        MAX(sim.occurred_at) AS last_movement_at,
        MAX(CASE
          WHEN sim.source_type = '${SupplyInventorySourceType.purchase.storageValue}'
           AND sim.movement_type = '${SupplyInventoryMovementType.inbound.storageValue}'
          THEN sim.occurred_at
          ELSE NULL
        END) AS last_purchase_at
      FROM ${TableNames.supplies} s
      LEFT JOIN ${TableNames.fornecedores} f
        ON f.id = s.default_supplier_id
      LEFT JOIN ${TableNames.supplyInventoryMovements} sim
        ON sim.supply_id = s.id
      WHERE 1 = 1
    ''');

    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
        AND (
          s.name LIKE ? COLLATE NOCASE
          OR COALESCE(s.sku, '') LIKE ? COLLATE NOCASE
          OR COALESCE(f.nome, '') LIKE ? COLLATE NOCASE
        )
      ''');
      final likeQuery = '%$trimmedQuery%';
      args.addAll([likeQuery, likeQuery, likeQuery]);
    }

    buffer.write('''
      GROUP BY s.id
      ORDER BY s.is_active DESC, s.name COLLATE NOCASE ASC
    ''');

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapInventoryOverview).toList(growable: false);
  }

  @override
  Future<List<SupplyInventoryMovement>> listInventoryMovements({
    int? supplyId,
    SupplyInventorySourceType? sourceType,
    DateTime? occurredFrom,
    DateTime? occurredTo,
    int limit = 200,
  }) async {
    final database = await _appDatabase.database;
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        sim.*,
        s.name AS supply_name
      FROM ${TableNames.supplyInventoryMovements} sim
      INNER JOIN ${TableNames.supplies} s
        ON s.id = sim.supply_id
      WHERE 1 = 1
    ''');

    if (supplyId != null) {
      buffer.write(' AND sim.supply_id = ?');
      args.add(supplyId);
    }
    if (sourceType != null) {
      buffer.write(' AND sim.source_type = ?');
      args.add(sourceType.storageValue);
    }
    if (occurredFrom != null) {
      buffer.write(' AND sim.occurred_at >= ?');
      args.add(occurredFrom.toIso8601String());
    }
    if (occurredTo != null) {
      buffer.write(' AND sim.occurred_at <= ?');
      args.add(occurredTo.toIso8601String());
    }

    buffer.write(' ORDER BY sim.occurred_at DESC, sim.id DESC LIMIT ?');
    args.add(limit);

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapInventoryMovement).toList(growable: false);
  }

  @override
  Future<List<SupplyReorderSuggestion>> listReorderSuggestions({
    String query = '',
    SupplyReorderFilter filter = SupplyReorderFilter.all,
  }) async {
    final overview = await listInventoryOverview(query: query);
    return SupplyReorderSuggestion.sortOperational(
      overview
          .where((item) => item.isAlert)
          .map(
            (item) => SupplyReorderSuggestion(
              overview: item,
              shortageMil: item.shortageMil,
            ),
          )
          .toList(growable: false),
      filter: filter,
    );
  }

  @override
  Future<SupplyInventoryConsistencyReport> verifyInventoryConsistency({
    Iterable<int>? supplyIds,
    bool repair = true,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) async {
      final checkedAt = DateTime.now();
      final report = await SupplyInventorySupport.verifyInventoryConsistency(
        txn,
        supplyIds: supplyIds,
        checkedAt: checkedAt,
        repair: repair,
      );
      if (repair && report.repairedSupplyIds.isNotEmpty) {
        await SupplySyncMutationSupport.markSuppliesForSync(
          txn,
          supplyIds: report.repairedSupplyIds,
          changedAt: checkedAt,
          syncMetadataRepository: _syncMetadataRepository,
          syncQueueRepository: _syncQueueRepository,
        );
      }
      return report;
    });
  }

  @override
  Future<List<SupplyCostHistoryEntry>> listCostHistory({
    required int supplyId,
    int limit = 20,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.supplyCostHistory,
      where: 'supply_id = ?',
      whereArgs: [supplyId],
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(SupplyCostHistorySupport.mapRow).toList(growable: false);
  }

  @override
  Future<List<Supply>> search({
    String query = '',
    bool activeOnly = false,
  }) async {
    final database = await _appDatabase.database;
    final trimmedQuery = query.trim();
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        s.*,
        f.nome AS default_supplier_name
      FROM ${TableNames.supplies} s
      LEFT JOIN ${TableNames.fornecedores} f
        ON f.id = s.default_supplier_id
      WHERE 1 = 1
    ''');

    if (activeOnly) {
      buffer.write(' AND s.is_active = 1');
    }

    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
        AND (
          s.name LIKE ? COLLATE NOCASE
          OR COALESCE(s.sku, '') LIKE ? COLLATE NOCASE
          OR COALESCE(f.nome, '') LIKE ? COLLATE NOCASE
        )
      ''');
      final likeQuery = '%$trimmedQuery%';
      args.add(likeQuery);
      args.add(likeQuery);
      args.add(likeQuery);
    }

    buffer.write(' ORDER BY s.is_active DESC, s.name COLLATE NOCASE ASC');
    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapSupply).toList(growable: false);
  }

  @override
  Future<void> update(int id, SupplyInput input) async {
    final database = await _appDatabase.database;
    _validateInput(input);

    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        throw const ValidationException('Insumo nao encontrado.');
      }

      final linkedRecipeCount = Sqflite.firstIntValue(
        await txn.rawQuery(
          '''
          SELECT COUNT(*) AS total
          FROM ${TableNames.productRecipeItems}
          WHERE supply_id = ?
        ''',
          [id],
        ),
      );
      final existingUnitType = existing['unit_type'] as String? ?? 'un';
      final normalizedUnitType = SupplyUnitTypes.normalize(input.unitType);
      final normalizedPurchaseUnitType = SupplyUnitTypes.normalize(
        input.purchaseUnitType,
      );
      if ((linkedRecipeCount ?? 0) > 0 &&
          normalizedUnitType != existingUnitType) {
        throw const ValidationException(
          'Nao e possivel alterar a unidade de uso de um insumo ja vinculado em fichas tecnicas.',
        );
      }

      final now = DateTime.now();
      await txn.update(
        TableNames.supplies,
        {
          'name': input.name.trim(),
          'sku': _cleanNullable(input.sku),
          'unit_type': normalizedUnitType,
          'purchase_unit_type': normalizedPurchaseUnitType,
          'conversion_factor': input.conversionFactor,
          'last_purchase_price_cents': input.lastPurchasePriceCents,
          'average_purchase_price_cents': input.averagePurchasePriceCents,
          'minimum_stock_mil': input.minimumStockMil,
          'default_supplier_id': input.defaultSupplierId,
          'is_active': input.isActive ? 1 : 0,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final priceChanged =
          (existing['last_purchase_price_cents'] as int? ?? 0) !=
          input.lastPurchasePriceCents;
      final conversionChanged =
          (existing['conversion_factor'] as int? ?? 1) !=
          input.conversionFactor;
      final purchaseUnitChanged =
          (existing['purchase_unit_type'] as String? ?? 'un') !=
          normalizedPurchaseUnitType;
      final averagePriceChanged =
          (existing['average_purchase_price_cents'] as int?) !=
          input.averagePurchasePriceCents;
      final activeChanged =
          (existing['is_active'] as int? ?? 1) != (input.isActive ? 1 : 0);

      if (priceChanged ||
          conversionChanged ||
          purchaseUnitChanged ||
          averagePriceChanged) {
        final changeSummary = _manualChangeSummary(
          existing: existing,
          input: input,
          normalizedPurchaseUnitType: normalizedPurchaseUnitType,
          priceChanged: priceChanged,
          conversionChanged: conversionChanged,
          purchaseUnitChanged: purchaseUnitChanged,
          averagePriceChanged: averagePriceChanged,
        );
        await SupplyCostHistorySupport.recordManualSnapshot(
          txn,
          supplyId: id,
          snapshot: SupplyCostSnapshot(
            lastPurchasePriceCents: input.lastPurchasePriceCents,
            averagePurchasePriceCents: input.averagePurchasePriceCents,
            purchaseUnitType: normalizedPurchaseUnitType,
            conversionFactor: input.conversionFactor,
          ),
          changedAt: now,
          eventType: conversionChanged
              ? SupplyCostHistoryEventType.conversionChanged
              : SupplyCostHistoryEventType.manualEdit,
          changeSummary: changeSummary,
          notes: 'Referencia manual atualizada no cadastro do insumo.',
        );
      }

      if (priceChanged ||
          conversionChanged ||
          purchaseUnitChanged ||
          activeChanged) {
        await SupplyLinkedProductSupport.recalculateLinkedProducts(
          txn,
          supplyIds: [id],
          changedAt: now,
          syncMetadataRepository: _syncMetadataRepository,
          syncQueueRepository: _syncQueueRepository,
        );
      }

      await SupplyInventorySupport.applyManualStockTarget(
        txn,
        supplyId: id,
        supplyUuid: existing['uuid'] as String,
        targetStockMil: input.currentStockMil,
        occurredAt: now,
        notes: 'Saldo operacional ajustado pelo cadastro do insumo.',
      );

      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: id,
      );
      final localUuid = existing['uuid'] as String;
      final createdAt = DateTime.parse(existing['created_at'] as String);
      if (metadata?.identity.remoteId == null) {
        await _syncMetadataRepository.markPendingUpload(
          txn,
          featureKey: featureKey,
          localId: id,
          localUuid: localUuid,
          createdAt: createdAt,
          updatedAt: now,
        );
      } else {
        await _syncMetadataRepository.markPendingUpdate(
          txn,
          featureKey: featureKey,
          localId: id,
          localUuid: localUuid,
          remoteId: metadata!.identity.remoteId,
          createdAt: createdAt,
          updatedAt: now,
        );
      }
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'supply',
        localEntityId: id,
        localUuid: localUuid,
        remoteId: metadata?.identity.remoteId,
        operation: metadata?.identity.remoteId == null
            ? SyncQueueOperation.create
            : SyncQueueOperation.update,
        localUpdatedAt: now,
      );
    });
  }

  Future<void> seedPendingSyncIfNeeded() async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT
          s.id,
          s.uuid,
          s.created_at,
          s.updated_at
        FROM ${TableNames.supplies} s
        LEFT JOIN ${TableNames.syncRegistros} sync
          ON sync.feature_key = '$featureKey'
          AND sync.local_id = s.id
        WHERE sync.local_id IS NULL
      ''');

      for (final row in rows) {
        final localId = row['id'] as int;
        final localUuid = row['uuid'] as String;
        final createdAt = DateTime.parse(row['created_at'] as String);
        final updatedAt = DateTime.parse(row['updated_at'] as String);
        await _syncMetadataRepository.markPendingUpload(
          txn,
          featureKey: featureKey,
          localId: localId,
          localUuid: localUuid,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
        await _syncQueueRepository.enqueueMutation(
          txn,
          featureKey: featureKey,
          entityType: 'supply',
          localEntityId: localId,
          localUuid: localUuid,
          remoteId: null,
          operation: SyncQueueOperation.create,
          localUpdatedAt: updatedAt,
        );
      }
    });
  }

  Future<SupplySyncPayload?> findSupplyForSync(int supplyId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        s.*,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        supplier_sync.remote_id AS supplier_remote_id
      FROM ${TableNames.supplies} s
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = s.id
      LEFT JOIN ${TableNames.syncRegistros} supplier_sync
        ON supplier_sync.feature_key = '${SyncFeatureKeys.suppliers}'
        AND supplier_sync.local_id = s.default_supplier_id
      WHERE s.id = ?
      LIMIT 1
    ''',
      [supplyId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapSyncPayload(database, rows.first);
  }

  Future<List<SupplySyncPayload>> listForSync() async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
      SELECT
        s.*,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        supplier_sync.remote_id AS supplier_remote_id
      FROM ${TableNames.supplies} s
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = s.id
      LEFT JOIN ${TableNames.syncRegistros} supplier_sync
        ON supplier_sync.feature_key = '${SyncFeatureKeys.suppliers}'
        AND supplier_sync.local_id = s.default_supplier_id
      ORDER BY s.updated_at DESC, s.name COLLATE NOCASE ASC
    ''');
    final payloads = <SupplySyncPayload>[];
    for (final row in rows) {
      payloads.add(await _mapSyncPayload(database, row));
    }
    return payloads;
  }

  Future<Supply?> findByRemoteId(String remoteId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        s.*,
        f.nome AS default_supplier_name
      FROM ${TableNames.supplies} s
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = s.id
      LEFT JOIN ${TableNames.fornecedores} f
        ON f.id = s.default_supplier_id
      WHERE sync.remote_id = ?
      LIMIT 1
    ''',
      [remoteId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapSupply(rows.first);
  }

  Future<void> upsertFromRemote(RemoteSupplyRecord remote) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final localMatch = await _findLocalMatchForRemote(txn, remote);
      final mappedSupplierId = await _resolveLocalDefaultSupplierId(
        txn,
        remote.remoteDefaultSupplierId,
      );

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
            existing['updated_at'] as String,
          );
          if (localUpdatedAt.isAfter(remote.updatedAt)) {
            await _syncMetadataRepository.markPendingUpdate(
              txn,
              featureKey: featureKey,
              localId: localId,
              localUuid: localUuid,
              remoteId: remote.remoteId,
              createdAt: createdAt,
              updatedAt: localUpdatedAt,
            );
            await _syncQueueRepository.enqueueMutation(
              txn,
              featureKey: featureKey,
              entityType: 'supply',
              localEntityId: localId,
              localUuid: localUuid,
              remoteId: remote.remoteId,
              operation: SyncQueueOperation.update,
              localUpdatedAt: localUpdatedAt,
            );
            return;
          }
        }

        await txn.update(
          TableNames.supplies,
          {
            'name': remote.name,
            'sku': remote.sku,
            'unit_type': remote.unitType,
            'purchase_unit_type': remote.purchaseUnitType,
            'conversion_factor': remote.conversionFactor,
            'last_purchase_price_cents': remote.lastPurchasePriceCents,
            'average_purchase_price_cents': remote.averagePurchasePriceCents,
            'current_stock_mil': remote.currentStockMil,
            'minimum_stock_mil': remote.minimumStockMil,
            'default_supplier_id': mappedSupplierId,
            'is_active': (remote.deletedAt == null && remote.isActive) ? 1 : 0,
            'updated_at': remote.updatedAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      } else {
        localUuid = remote.localUuid.trim().isNotEmpty
            ? remote.localUuid.trim()
            : IdGenerator.next();
        createdAt = remote.createdAt;
        localId = await txn.insert(TableNames.supplies, {
          'uuid': localUuid,
          'name': remote.name,
          'sku': remote.sku,
          'unit_type': remote.unitType,
          'purchase_unit_type': remote.purchaseUnitType,
          'conversion_factor': remote.conversionFactor,
          'last_purchase_price_cents': remote.lastPurchasePriceCents,
          'average_purchase_price_cents': remote.averagePurchasePriceCents,
          'current_stock_mil': remote.currentStockMil,
          'minimum_stock_mil': remote.minimumStockMil,
          'default_supplier_id': mappedSupplierId,
          'is_active': (remote.deletedAt == null && remote.isActive) ? 1 : 0,
          'created_at': remote.createdAt.toIso8601String(),
          'updated_at': remote.updatedAt.toIso8601String(),
        });
      }

      await _replaceCostHistoryFromRemote(
        txn,
        localSupplyId: localId,
        remoteHistory: remote.costHistory,
      );
      if (await SupplyInventorySupport.hasAnyMovement(txn, supplyId: localId)) {
        await SupplyInventorySupport.rebuildSupplyStockCache(
          txn,
          supplyIds: [localId],
          changedAt: remote.updatedAt,
        );
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
    required SupplySyncPayload supply,
    required RemoteSupplyRecord remote,
  }) async {
    final database = await _appDatabase.database;
    final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
      database,
      featureKey: featureKey,
      remoteId: remote.remoteId,
    );
    if (metadataByRemoteId != null &&
        metadataByRemoteId.identity.localId != null &&
        metadataByRemoteId.identity.localId != supply.supplyId) {
      await upsertFromRemote(remote);
      return;
    }

    final mappedSupplierId = await _resolveLocalDefaultSupplierId(
      database,
      remote.remoteDefaultSupplierId,
    );

    await database.transaction((txn) async {
      await txn.update(
        TableNames.supplies,
        {
          'name': remote.name,
          'sku': remote.sku,
          'unit_type': remote.unitType,
          'purchase_unit_type': remote.purchaseUnitType,
          'conversion_factor': remote.conversionFactor,
          'last_purchase_price_cents': remote.lastPurchasePriceCents,
          'average_purchase_price_cents': remote.averagePurchasePriceCents,
          'current_stock_mil': remote.currentStockMil,
          'minimum_stock_mil': remote.minimumStockMil,
          'default_supplier_id': mappedSupplierId,
          'is_active': (remote.deletedAt == null && remote.isActive) ? 1 : 0,
          'updated_at': remote.updatedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [supply.supplyId],
      );

      await _replaceCostHistoryFromRemote(
        txn,
        localSupplyId: supply.supplyId,
        remoteHistory: remote.costHistory,
      );
      if (await SupplyInventorySupport.hasAnyMovement(
        txn,
        supplyId: supply.supplyId,
      )) {
        await SupplyInventorySupport.rebuildSupplyStockCache(
          txn,
          supplyIds: [supply.supplyId],
          changedAt: remote.updatedAt,
        );
      }
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: supply.supplyId,
        localUuid: supply.supplyUuid,
        remoteId: remote.remoteId,
        origin: RecordOrigin.merged,
        createdAt: supply.createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  Future<void> markSyncError({
    required SupplySyncPayload supply,
    required String message,
    required SyncErrorType errorType,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    await database.transaction((txn) async {
      await _syncMetadataRepository.markSyncError(
        txn,
        featureKey: featureKey,
        localId: supply.supplyId,
        localUuid: supply.supplyUuid,
        remoteId: supply.remoteId,
        createdAt: supply.createdAt,
        updatedAt: now,
        message: message,
        errorType: errorType,
      );
    });
  }

  Future<void> markConflict({
    required SupplySyncPayload supply,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: featureKey,
        localId: supply.supplyId,
        localUuid: supply.supplyUuid,
        remoteId: supply.remoteId,
        createdAt: supply.createdAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> recoverMissingRemoteIdentity({
    required SupplySyncPayload supply,
    SyncQueueItem? queueItem,
  }) async {
    await _remoteIdentityRecovery.recoverForReupload(
      featureKey: featureKey,
      entityType: queueItem?.entityType ?? 'supply',
      localEntityId: supply.supplyId,
      localUuid: supply.supplyUuid,
      staleRemoteId: supply.remoteId ?? queueItem?.remoteId,
      createdAt: supply.createdAt,
      updatedAt: supply.updatedAt,
      queueItem: queueItem,
      entityLabel: 'insumo "${supply.name}"',
    );
  }

  Future<Map<String, Object?>?> _findRowById(
    DatabaseExecutor db,
    int id,
  ) async {
    final rows = await db.query(
      TableNames.supplies,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  void _validateInput(SupplyInput input) {
    if (input.name.trim().isEmpty) {
      throw const ValidationException('Informe o nome do insumo.');
    }

    final unitType = SupplyUnitTypes.normalize(input.unitType);
    final purchaseUnitType = SupplyUnitTypes.normalize(input.purchaseUnitType);
    if (!SupplyUnitTypes.areCompatible(unitType, purchaseUnitType)) {
      throw const ValidationException(
        'A unidade de compra precisa ser compativel com a unidade de uso.',
      );
    }

    if (input.conversionFactor <= 0) {
      throw const ValidationException(
        'Informe um fator de conversao maior que zero.',
      );
    }

    if (unitType == purchaseUnitType && input.conversionFactor != 1) {
      throw const ValidationException(
        'Quando a unidade de compra e a de uso sao iguais, o fator deve ser 1.',
      );
    }

    if (input.lastPurchasePriceCents < 0) {
      throw const ValidationException(
        'O valor da ultima compra nao pode ser negativo.',
      );
    }

    if (input.currentStockMil != null && input.currentStockMil! < 0) {
      throw const ValidationException(
        'O saldo operacional informado nao pode ser negativo no cadastro.',
      );
    }

    if (input.minimumStockMil != null && input.minimumStockMil! < 0) {
      throw const ValidationException(
        'O estoque minimo nao pode ser negativo.',
      );
    }
  }

  Supply _mapSupply(Map<String, Object?> row) {
    return Supply(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      name: row['name'] as String? ?? '',
      sku: row['sku'] as String?,
      unitType: SupplyUnitTypes.normalize(row['unit_type'] as String?),
      purchaseUnitType: SupplyUnitTypes.normalize(
        row['purchase_unit_type'] as String?,
      ),
      conversionFactor: row['conversion_factor'] as int? ?? 1,
      lastPurchasePriceCents: row['last_purchase_price_cents'] as int? ?? 0,
      averagePurchasePriceCents: row['average_purchase_price_cents'] as int?,
      currentStockMil: row['current_stock_mil'] as int?,
      minimumStockMil: row['minimum_stock_mil'] as int?,
      defaultSupplierId: row['default_supplier_id'] as int?,
      defaultSupplierName: row['default_supplier_name'] as String?,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  SupplyInventoryMovement _mapInventoryMovement(Map<String, Object?> row) {
    return SupplyInventoryMovement(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      remoteId: row['remote_id'] as String?,
      supplyId: row['supply_id'] as int,
      supplyName: row['supply_name'] as String? ?? 'Insumo',
      movementType: supplyInventoryMovementTypeFromStorage(
        row['movement_type'] as String?,
      ),
      sourceType: supplyInventorySourceTypeFromStorage(
        row['source_type'] as String?,
      ),
      sourceLocalUuid: row['source_local_uuid'] as String?,
      sourceRemoteId: row['source_remote_id'] as String?,
      quantityDeltaMil: row['quantity_delta_mil'] as int? ?? 0,
      unitType: row['unit_type'] as String? ?? 'un',
      balanceAfterMil: row['balance_after_mil'] as int?,
      notes: row['notes'] as String?,
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  SupplyInventoryOverview _mapInventoryOverview(Map<String, Object?> row) {
    final supply = _mapSupply(row);
    final hasOperationalBaseline = (row['movement_count'] as int? ?? 0) > 0;
    return SupplyInventoryOverview(
      supply: supply,
      hasOperationalBaseline: hasOperationalBaseline,
      inventoryStatus: SupplyInventoryMath.resolveStatus(
        isActive: supply.isActive,
        hasOperationalBaseline: hasOperationalBaseline,
        currentStockMil: supply.currentStockMil,
        minimumStockMil: supply.minimumStockMil,
      ),
      lastMovementAt: row['last_movement_at'] == null
          ? null
          : DateTime.parse(row['last_movement_at'] as String),
      lastPurchaseAt: row['last_purchase_at'] == null
          ? null
          : DateTime.parse(row['last_purchase_at'] as String),
    );
  }

  Future<SupplySyncPayload> _mapSyncPayload(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final historyRows = await db.rawQuery(
      '''
      SELECT
        sch.*,
        purchase_sync.remote_id AS purchase_remote_id,
        ic.uuid AS purchase_item_local_uuid
      FROM ${TableNames.supplyCostHistory} sch
      LEFT JOIN ${TableNames.syncRegistros} purchase_sync
        ON purchase_sync.feature_key = '${SyncFeatureKeys.purchases}'
        AND purchase_sync.local_id = sch.purchase_id
      LEFT JOIN ${TableNames.itensCompra} ic
        ON ic.id = sch.purchase_item_id
      WHERE sch.supply_id = ?
      ORDER BY sch.occurred_at DESC, sch.id DESC
    ''',
      [row['id'] as int],
    );

    return SupplySyncPayload(
      supplyId: row['id'] as int,
      supplyUuid: row['uuid'] as String,
      remoteId: row['sync_remote_id'] as String?,
      defaultSupplierLocalId: row['default_supplier_id'] as int?,
      defaultSupplierRemoteId: row['supplier_remote_id'] as String?,
      name: row['name'] as String? ?? '',
      sku: row['sku'] as String?,
      unitType: SupplyUnitTypes.normalize(row['unit_type'] as String?),
      purchaseUnitType: SupplyUnitTypes.normalize(
        row['purchase_unit_type'] as String?,
      ),
      conversionFactor: row['conversion_factor'] as int? ?? 1,
      lastPurchasePriceCents: row['last_purchase_price_cents'] as int? ?? 0,
      averagePurchasePriceCents: row['average_purchase_price_cents'] as int?,
      currentStockMil: row['current_stock_mil'] as int?,
      minimumStockMil: row['minimum_stock_mil'] as int?,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      syncStatus: syncStatusFromStorage(row['sync_status'] as String?),
      lastSyncedAt: row['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(row['sync_last_synced_at'] as String),
      costHistory: historyRows
          .map(
            (history) => SupplyCostHistorySyncPayload(
              historyId: history['id'] as int,
              historyUuid: history['uuid'] as String,
              purchaseLocalId: history['purchase_id'] as int?,
              purchaseRemoteId: history['purchase_remote_id'] as String?,
              purchaseItemLocalUuid:
                  history['purchase_item_local_uuid'] as String?,
              source: history['source'] as String? ?? 'manual',
              eventType: history['event_type'] as String? ?? 'manual_edit',
              purchaseUnitType:
                  history['purchase_unit_type'] as String? ?? 'un',
              conversionFactor: history['conversion_factor'] as int? ?? 1,
              lastPurchasePriceCents:
                  history['last_purchase_price_cents'] as int? ?? 0,
              averagePurchasePriceCents:
                  history['average_purchase_price_cents'] as int?,
              changeSummary: history['change_summary'] as String?,
              notes: history['notes'] as String?,
              occurredAt: DateTime.parse(history['occurred_at'] as String),
              createdAt: DateTime.parse(history['created_at'] as String),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<int?> _resolveLocalDefaultSupplierId(
    DatabaseExecutor db,
    String? remoteSupplierId,
  ) async {
    if (remoteSupplierId == null || remoteSupplierId.trim().isEmpty) {
      return null;
    }

    final metadata = await _syncMetadataRepository.findByRemoteId(
      db,
      featureKey: SyncFeatureKeys.suppliers,
      remoteId: remoteSupplierId.trim(),
    );
    return metadata?.identity.localId;
  }

  Future<_LocalSupplyMatch?> _findLocalMatchForRemote(
    DatabaseExecutor db,
    RemoteSupplyRecord remote,
  ) async {
    final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
      db,
      featureKey: featureKey,
      remoteId: remote.remoteId,
    );
    if (metadataByRemoteId?.identity.localId != null) {
      return _LocalSupplyMatch(
        localId: metadataByRemoteId!.identity.localId!,
        localUuid:
            metadataByRemoteId.identity.localUuid ?? remote.localUuid.trim(),
        createdAt: metadataByRemoteId.createdAt,
      );
    }

    final trimmedUuid = remote.localUuid.trim();
    if (trimmedUuid.isNotEmpty) {
      final metadataByLocalUuid = await _syncMetadataRepository.findByLocalUuid(
        db,
        featureKey: featureKey,
        localUuid: trimmedUuid,
      );
      if (metadataByLocalUuid?.identity.localId != null) {
        return _LocalSupplyMatch(
          localId: metadataByLocalUuid!.identity.localId!,
          localUuid: metadataByLocalUuid.identity.localUuid ?? trimmedUuid,
          createdAt: metadataByLocalUuid.createdAt,
        );
      }

      final rows = await db.query(
        TableNames.supplies,
        columns: const ['id', 'uuid', 'created_at'],
        where: 'uuid = ?',
        whereArgs: [trimmedUuid],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return _LocalSupplyMatch(
          localId: rows.first['id'] as int,
          localUuid: rows.first['uuid'] as String,
          createdAt: DateTime.parse(rows.first['created_at'] as String),
        );
      }
    }

    return null;
  }

  Future<void> _replaceCostHistoryFromRemote(
    DatabaseExecutor txn, {
    required int localSupplyId,
    required List<RemoteSupplyCostHistoryRecord> remoteHistory,
  }) async {
    await txn.delete(
      TableNames.supplyCostHistory,
      where: 'supply_id = ?',
      whereArgs: [localSupplyId],
    );

    for (final entry in remoteHistory) {
      int? purchaseLocalId;
      int? purchaseItemLocalId;

      if (entry.purchaseRemoteId != null &&
          entry.purchaseRemoteId!.trim().isNotEmpty) {
        final purchaseMetadata = await _syncMetadataRepository.findByRemoteId(
          txn,
          featureKey: SyncFeatureKeys.purchases,
          remoteId: entry.purchaseRemoteId!.trim(),
        );
        purchaseLocalId = purchaseMetadata?.identity.localId;

        if (purchaseLocalId != null &&
            entry.purchaseItemLocalUuid != null &&
            entry.purchaseItemLocalUuid!.trim().isNotEmpty) {
          final itemRows = await txn.query(
            TableNames.itensCompra,
            columns: const ['id'],
            where: 'compra_id = ? AND uuid = ?',
            whereArgs: [purchaseLocalId, entry.purchaseItemLocalUuid!.trim()],
            limit: 1,
          );
          purchaseItemLocalId = itemRows.isEmpty
              ? null
              : itemRows.first['id'] as int;
        }
      }

      await txn.insert(TableNames.supplyCostHistory, {
        'uuid': entry.localUuid.trim().isNotEmpty
            ? entry.localUuid.trim()
            : IdGenerator.next(),
        'supply_id': localSupplyId,
        'purchase_id': purchaseLocalId,
        'purchase_item_id': purchaseItemLocalId,
        'source': entry.source,
        'event_type': entry.eventType,
        'purchase_unit_type': entry.purchaseUnitType,
        'conversion_factor': entry.conversionFactor,
        'last_purchase_price_cents': entry.lastPurchasePriceCents,
        'average_purchase_price_cents': entry.averagePurchasePriceCents,
        'change_summary': _cleanNullable(entry.changeSummary),
        'notes': _cleanNullable(entry.notes),
        'occurred_at': entry.occurredAt.toIso8601String(),
        'created_at': entry.createdAt.toIso8601String(),
      });
    }
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _manualChangeSummary({
    required Map<String, Object?> existing,
    required SupplyInput input,
    required String normalizedPurchaseUnitType,
    required bool priceChanged,
    required bool conversionChanged,
    required bool purchaseUnitChanged,
    required bool averagePriceChanged,
  }) {
    final changes = <String>[];
    if (priceChanged) {
      changes.add(
        'Ultimo preco ${_formatCents(existing['last_purchase_price_cents'] as int? ?? 0)} -> ${_formatCents(input.lastPurchasePriceCents)}',
      );
    }
    if (averagePriceChanged) {
      changes.add(
        'Preco medio ${_formatNullableCents(existing['average_purchase_price_cents'] as int?)} -> ${_formatNullableCents(input.averagePurchasePriceCents)}',
      );
    }
    if (purchaseUnitChanged) {
      changes.add(
        'Unidade de compra ${(existing['purchase_unit_type'] as String? ?? 'un')} -> $normalizedPurchaseUnitType',
      );
    }
    if (conversionChanged) {
      changes.add(
        'Fator ${(existing['conversion_factor'] as int? ?? 1)} -> ${input.conversionFactor}',
      );
    }

    if (changes.isEmpty) {
      return 'Referencia manual revisada sem alterar o custo do insumo.';
    }
    return changes.join(' | ');
  }

  String _formatCents(int value) => 'R\$ ${(value / 100).toStringAsFixed(2)}';

  String _formatNullableCents(int? value) {
    if (value == null) {
      return 'sem media';
    }
    return _formatCents(value);
  }
}

class _LocalSupplyMatch {
  const _LocalSupplyMatch({
    required this.localId,
    required this.localUuid,
    required this.createdAt,
  });

  final int localId;
  final String localUuid;
  final DateTime createdAt;
}
