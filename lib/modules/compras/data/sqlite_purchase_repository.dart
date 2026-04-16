import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_error_type.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../insumos/data/support/supply_inventory_support.dart';
import '../../insumos/data/support/supply_purchase_cost_support.dart';
import '../../insumos/domain/entities/supply_cost_history_entry.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/purchase.dart';
import '../domain/entities/purchase_item.dart';
import '../domain/entities/purchase_detail.dart';
import '../domain/entities/purchase_payment.dart';
import '../domain/entities/purchase_status.dart';
import '../domain/repositories/purchase_repository.dart';
import 'models/purchase_item_model.dart';
import 'models/purchase_model.dart';
import 'models/purchase_payment_model.dart';
import 'models/purchase_sync_payload.dart';
import 'models/remote_purchase_record.dart';
import 'sql/purchase_query_sql.dart';
import 'support/purchase_payment_writer.dart';
import 'support/purchase_preparation_support.dart';
import 'support/purchase_stock_support.dart';
import 'support/purchase_sync_payload_loader.dart';
import 'support/purchase_sync_state_support.dart';

class SqlitePurchaseRepository implements PurchaseRepository {
  SqlitePurchaseRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase) {
    _syncStateSupport = PurchaseSyncStateSupport(
      syncMetadataRepository: _syncMetadataRepository,
      syncQueueRepository: _syncQueueRepository,
      featureKey: featureKey,
    );
  }

  static const String featureKey = SyncFeatureKeys.purchases;

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  late final PurchaseSyncStateSupport _syncStateSupport;

  @override
  Future<int> create(PurchaseUpsertInput input) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) async {
      final prepared = await PurchasePreparationSupport.preparePurchase(
        txn,
        input,
      );
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final purchaseUuid = IdGenerator.next();
      final purchaseId = await txn.insert(TableNames.compras, {
        'uuid': purchaseUuid,
        'fornecedor_id': input.supplierId,
        'numero_documento': _cleanNullable(input.documentNumber),
        'observacao': _cleanNullable(input.notes),
        'data_compra': input.purchasedAt.toIso8601String(),
        'data_vencimento': input.dueDate?.toIso8601String(),
        'forma_pagamento': input.paymentMethod?.dbValue,
        'status': prepared.status.dbValue,
        'subtotal_centavos': prepared.subtotalCents,
        'desconto_centavos': input.discountCents,
        'acrescimo_centavos': input.surchargeCents,
        'frete_centavos': input.freightCents,
        'valor_final_centavos': prepared.finalAmountCents,
        'valor_pago_centavos': prepared.paidAmountCents,
        'valor_pendente_centavos': prepared.pendingAmountCents,
        'cancelada_em': null,
        'criado_em': nowIso,
        'atualizado_em': nowIso,
      });

      for (final item in prepared.items) {
        await txn.insert(TableNames.itensCompra, {
          'uuid': IdGenerator.next(),
          'compra_id': purchaseId,
          'item_type': item.itemType.storageValue,
          'produto_id': item.productId,
          'produto_variante_id': item.productVariantId,
          'supply_id': item.supplyId,
          'nome_item_snapshot': item.itemNameSnapshot,
          'sku_variante_snapshot': item.variantSkuSnapshot,
          'cor_variante_snapshot': item.variantColorLabelSnapshot,
          'tamanho_variante_snapshot': item.variantSizeLabelSnapshot,
          'unidade_medida_snapshot': item.unitMeasureSnapshot,
          'quantidade_mil': item.quantityMil,
          'custo_unitario_centavos': item.unitCostCents,
          'subtotal_centavos': item.subtotalCents,
        });
      }

      await PurchaseStockSupport.applyStockEntries(
        txn,
        prepared.items,
        factor: 1,
      );
      await SupplyInventorySupport.replacePurchaseEntries(
        txn,
        purchaseUuid: purchaseUuid,
        items: prepared.items,
        occurredAt: now,
      );
      await SupplyPurchaseCostSupport.refreshSupplyPricing(
        txn,
        supplyIds: _collectSupplyIds(prepared.items),
        changedAt: now,
        eventType: SupplyCostHistoryEventType.purchaseCreated,
        syncMetadataRepository: _syncMetadataRepository,
        syncQueueRepository: SqliteSyncQueueRepository(_appDatabase),
      );

      if (prepared.paidAmountCents > 0) {
        await PurchasePaymentWriter.insertPayment(
          txn,
          purchaseId: purchaseId,
          currentLocalUserId: _operationalContext.currentLocalUserId,
          supplierName: prepared.supplierName,
          amountCents: prepared.paidAmountCents,
          paymentMethod: prepared.paymentMethod,
          registeredAt: now,
          notes: 'Pagamento inicial da compra',
        );
      }

      await _syncStateSupport.registerPurchaseForSync(
        txn,
        purchaseId: purchaseId,
        purchaseUuid: purchaseUuid,
        createdAt: now,
        updatedAt: now,
      );

      return purchaseId;
    });
  }

  @override
  Future<void> update(int id, PurchaseUpsertInput input) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final purchaseRow = await _fetchPurchaseRow(txn, id);
      if (purchaseRow == null) {
        throw const ValidationException('Compra nao encontrada.');
      }

      final currentStatus = PurchaseStatusX.fromDb(
        purchaseRow['status'] as String,
      );
      if (currentStatus == PurchaseStatus.cancelada) {
        throw const ValidationException(
          'Nao e possivel editar uma compra cancelada.',
        );
      }

      final paymentCount =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''
              SELECT COUNT(*) AS total
              FROM ${TableNames.compraPagamentos}
              WHERE compra_id = ?
            ''',
              [id],
            ),
          ) ??
          0;
      if (paymentCount > 0) {
        throw const ValidationException(
          'Nao e possivel editar compras com pagamentos registrados.',
        );
      }

      final previousItems = await _fetchItemModels(txn, id);
      await PurchaseStockSupport.validateStockReversal(txn, previousItems);

      final prepared = await PurchasePreparationSupport.preparePurchase(
        txn,
        input,
      );
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final affectedSupplyIds = <int>{
        ..._collectSupplyIds(previousItems),
        ..._collectSupplyIds(prepared.items),
      };

      await PurchaseStockSupport.applyStockEntries(
        txn,
        previousItems,
        factor: -1,
      );
      await txn.delete(
        TableNames.itensCompra,
        where: 'compra_id = ?',
        whereArgs: [id],
      );

      await txn.update(
        TableNames.compras,
        {
          'fornecedor_id': input.supplierId,
          'numero_documento': _cleanNullable(input.documentNumber),
          'observacao': _cleanNullable(input.notes),
          'data_compra': input.purchasedAt.toIso8601String(),
          'data_vencimento': input.dueDate?.toIso8601String(),
          'forma_pagamento': input.paymentMethod?.dbValue,
          'status': prepared.status.dbValue,
          'subtotal_centavos': prepared.subtotalCents,
          'desconto_centavos': input.discountCents,
          'acrescimo_centavos': input.surchargeCents,
          'frete_centavos': input.freightCents,
          'valor_final_centavos': prepared.finalAmountCents,
          'valor_pago_centavos': prepared.paidAmountCents,
          'valor_pendente_centavos': prepared.pendingAmountCents,
          'atualizado_em': nowIso,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      for (final item in prepared.items) {
        await txn.insert(TableNames.itensCompra, {
          'uuid': IdGenerator.next(),
          'compra_id': id,
          'item_type': item.itemType.storageValue,
          'produto_id': item.productId,
          'produto_variante_id': item.productVariantId,
          'supply_id': item.supplyId,
          'nome_item_snapshot': item.itemNameSnapshot,
          'sku_variante_snapshot': item.variantSkuSnapshot,
          'cor_variante_snapshot': item.variantColorLabelSnapshot,
          'tamanho_variante_snapshot': item.variantSizeLabelSnapshot,
          'unidade_medida_snapshot': item.unitMeasureSnapshot,
          'quantidade_mil': item.quantityMil,
          'custo_unitario_centavos': item.unitCostCents,
          'subtotal_centavos': item.subtotalCents,
        });
      }
      await PurchaseStockSupport.applyStockEntries(
        txn,
        prepared.items,
        factor: 1,
      );
      await SupplyInventorySupport.replacePurchaseEntries(
        txn,
        purchaseUuid: purchaseRow['uuid'] as String,
        items: prepared.items,
        occurredAt: now,
      );
      await SupplyPurchaseCostSupport.refreshSupplyPricing(
        txn,
        supplyIds: affectedSupplyIds,
        changedAt: now,
        eventType: SupplyCostHistoryEventType.purchaseUpdated,
        syncMetadataRepository: _syncMetadataRepository,
        syncQueueRepository: SqliteSyncQueueRepository(_appDatabase),
      );

      if (prepared.paidAmountCents > 0) {
        await PurchasePaymentWriter.insertPayment(
          txn,
          purchaseId: id,
          currentLocalUserId: _operationalContext.currentLocalUserId,
          supplierName: prepared.supplierName,
          amountCents: prepared.paidAmountCents,
          paymentMethod: prepared.paymentMethod,
          registeredAt: now,
          notes: 'Pagamento registrado na edicao da compra',
        );
      }

      await _syncStateSupport.registerPurchaseForSync(
        txn,
        purchaseId: id,
        purchaseUuid: purchaseRow['uuid'] as String,
        createdAt: DateTime.parse(purchaseRow['criado_em'] as String),
        updatedAt: now,
      );
    });
  }

  @override
  Future<void> cancel(int purchaseId, {String? reason}) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final purchaseRow = await _fetchPurchaseRow(txn, purchaseId);
      if (purchaseRow == null) {
        throw const ValidationException('Compra nao encontrada.');
      }

      final currentStatus = PurchaseStatusX.fromDb(
        purchaseRow['status'] as String,
      );
      if (currentStatus == PurchaseStatus.cancelada) {
        return;
      }

      final items = await _fetchItemModels(txn, purchaseId);
      await PurchaseStockSupport.validateStockReversal(txn, items);
      await PurchaseStockSupport.applyStockEntries(txn, items, factor: -1);

      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      await SupplyInventorySupport.cancelPurchaseEntries(
        txn,
        purchaseUuid: purchaseRow['uuid'] as String,
        occurredAt: now,
      );
      await txn.update(
        TableNames.compras,
        {
          'status': PurchaseStatus.cancelada.dbValue,
          'cancelada_em': nowIso,
          'atualizado_em': nowIso,
          'observacao': _mergeNotes(
            purchaseRow['observacao'] as String?,
            reason == null || reason.trim().isEmpty
                ? 'Compra cancelada.'
                : 'Compra cancelada: ${reason.trim()}',
          ),
        },
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
      await SupplyPurchaseCostSupport.refreshSupplyPricing(
        txn,
        supplyIds: _collectSupplyIds(items),
        changedAt: now,
        eventType: SupplyCostHistoryEventType.purchaseCanceled,
        syncMetadataRepository: _syncMetadataRepository,
        syncQueueRepository: SqliteSyncQueueRepository(_appDatabase),
      );

      await _syncStateSupport.registerPurchaseForSync(
        txn,
        purchaseId: purchaseId,
        purchaseUuid: purchaseRow['uuid'] as String,
        createdAt: DateTime.parse(purchaseRow['criado_em'] as String),
        updatedAt: now,
      );
    });
  }

  @override
  Future<PurchaseDetail> fetchDetail(int purchaseId) async {
    final database = await _appDatabase.database;
    final purchaseRow = await _fetchPurchaseRow(database, purchaseId);
    if (purchaseRow == null) {
      throw const ValidationException('Compra nao encontrada.');
    }

    final items = await _fetchItemModels(database, purchaseId);
    final payments = await _fetchPaymentModels(database, purchaseId);

    return PurchaseDetail(
      purchase: PurchaseModel.fromMap(purchaseRow),
      items: items,
      payments: payments,
    );
  }

  @override
  Future<PurchaseDetail> registerPayment(PurchasePaymentInput input) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final purchaseRow = await _fetchPurchaseRow(txn, input.purchaseId);
      if (purchaseRow == null) {
        throw const ValidationException('Compra nao encontrada.');
      }

      final status = PurchaseStatusX.fromDb(purchaseRow['status'] as String);
      if (status == PurchaseStatus.cancelada) {
        throw const ValidationException(
          'Nao e possivel registrar pagamento em compra cancelada.',
        );
      }
      if (status == PurchaseStatus.paga) {
        throw const ValidationException('Esta compra ja esta paga.');
      }
      if (input.paymentMethod == PaymentMethod.fiado) {
        throw const ValidationException(
          'Selecione uma forma de pagamento valida para a compra.',
        );
      }

      final pendingCents = purchaseRow['valor_pendente_centavos'] as int? ?? 0;
      if (input.amountCents <= 0) {
        throw const ValidationException(
          'Informe um valor de pagamento maior que zero.',
        );
      }
      if (input.amountCents > pendingCents) {
        throw const ValidationException(
          'O valor informado excede o saldo pendente desta compra.',
        );
      }

      final now = DateTime.now();
      await PurchasePaymentWriter.insertPayment(
        txn,
        purchaseId: input.purchaseId,
        currentLocalUserId: _operationalContext.currentLocalUserId,
        supplierName: purchaseRow['fornecedor_nome'] as String? ?? 'Fornecedor',
        amountCents: input.amountCents,
        paymentMethod: input.paymentMethod,
        registeredAt: now,
        notes: input.notes,
      );

      final currentPaid = purchaseRow['valor_pago_centavos'] as int? ?? 0;
      final nextPaid = currentPaid + input.amountCents;
      final finalAmount = purchaseRow['valor_final_centavos'] as int? ?? 0;
      final nextPending = finalAmount - nextPaid;
      await txn.update(
        TableNames.compras,
        {
          'valor_pago_centavos': nextPaid,
          'valor_pendente_centavos': nextPending < 0 ? 0 : nextPending,
          'status': PurchasePreparationSupport.resolveStatus(
            finalAmountCents: finalAmount,
            paidAmountCents: nextPaid,
            dueDate: purchaseRow['data_vencimento'] == null
                ? null
                : DateTime.parse(purchaseRow['data_vencimento'] as String),
          ).dbValue,
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [input.purchaseId],
      );

      await _syncStateSupport.registerPurchaseForSync(
        txn,
        purchaseId: input.purchaseId,
        purchaseUuid: purchaseRow['uuid'] as String,
        createdAt: DateTime.parse(purchaseRow['criado_em'] as String),
        updatedAt: now,
      );
    });

    return fetchDetail(input.purchaseId);
  }

  @override
  Future<List<Purchase>> search({
    String query = '',
    PurchaseStatus? status,
    int? supplierId,
  }) async {
    final database = await _appDatabase.database;
    final args = <Object?>[];
    final buffer = StringBuffer(
      PurchaseQuerySql.selectPurchaseBase(featureKey: featureKey),
    );

    if (status != null) {
      buffer.write(' AND c.status = ?');
      args.add(status.dbValue);
    }

    if (supplierId != null) {
      buffer.write(' AND c.fornecedor_id = ?');
      args.add(supplierId);
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
        AND (
          f.nome LIKE ? COLLATE NOCASE
          OR COALESCE(c.numero_documento, '') LIKE ? COLLATE NOCASE
          OR COALESCE(f.documento, '') LIKE ? COLLATE NOCASE
        )
      ''');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
    }

    buffer.write(
      ' GROUP BY ${PurchaseQuerySql.purchaseGroupBy()} ORDER BY ${PurchaseQuerySql.defaultGroupedOrderBy()}',
    );

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(PurchaseModel.fromMap).toList();
  }

  Future<List<PurchasePayment>> listPaymentsForPurchase(int purchaseId) async {
    final database = await _appDatabase.database;
    return _fetchPaymentModels(database, purchaseId);
  }

  Future<Purchase?> findById(int purchaseId) async {
    final database = await _appDatabase.database;
    final purchaseRow = await _fetchPurchaseRow(database, purchaseId);
    if (purchaseRow == null) {
      return null;
    }

    return PurchaseModel.fromMap(purchaseRow);
  }

  Future<Purchase?> findByRemoteId(String remoteId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      PurchaseQuerySql.selectPurchaseByRemoteId(featureKey: featureKey),
      [remoteId],
    );
    if (rows.isEmpty) {
      return null;
    }

    return PurchaseModel.fromMap(rows.first);
  }

  Future<List<Purchase>> listForSync() async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      PurchaseQuerySql.selectPurchasesForListing(featureKey: featureKey),
    );
    return rows.map(PurchaseModel.fromMap).toList();
  }

  Future<void> seedPendingSupplyPurchaseSyncIfNeeded() async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT
          c.id,
          c.uuid,
          c.criado_em,
          c.atualizado_em
        FROM ${TableNames.compras} c
        INNER JOIN ${TableNames.itensCompra} ic
          ON ic.compra_id = c.id
          AND ic.item_type = 'supply'
        LEFT JOIN ${TableNames.syncRegistros} sync
          ON sync.feature_key = '$featureKey'
          AND sync.local_id = c.id
        WHERE sync.local_id IS NULL
           OR sync.sync_status = 'local_only'
        GROUP BY c.id, c.uuid, c.criado_em, c.atualizado_em
      ''');

      for (final row in rows) {
        await _syncStateSupport.registerPurchaseForSync(
          txn,
          purchaseId: row['id'] as int,
          purchaseUuid: row['uuid'] as String,
          createdAt: DateTime.parse(row['criado_em'] as String),
          updatedAt: DateTime.parse(row['atualizado_em'] as String),
        );
      }
    });
  }

  Future<PurchaseSyncPayload?> findPurchaseForSync(int purchaseId) async {
    final database = await _appDatabase.database;
    return _loadPurchaseForSync(database, purchaseId);
  }

  Future<void> applyPushResult({
    required PurchaseSyncPayload purchase,
    required RemotePurchaseRecord remote,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncStateSupport.markSynced(
        txn,
        purchase: purchase,
        remoteId: remote.remoteId,
      );
      await _markLinkedSuppliesForSync(
        txn,
        purchase.items,
        changedAt: DateTime.now(),
      );
    });
  }

  Future<void> reconcileRemoteSnapshot(RemotePurchaseRecord remote) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final metadataByRemote = await _syncMetadataRepository.findByRemoteId(
        txn,
        featureKey: featureKey,
        remoteId: remote.remoteId,
      );

      PurchaseSyncPayload? purchase;
      if (metadataByRemote != null) {
        purchase = await _loadPurchaseForSync(
          txn,
          metadataByRemote.identity.localId!,
        );
      }

      if (purchase == null) {
        final localRows = await txn.query(
          TableNames.compras,
          where: 'uuid = ?',
          whereArgs: [remote.localUuid],
          limit: 1,
        );
        if (localRows.isEmpty) {
          return;
        }

        purchase = await _loadPurchaseForSync(
          txn,
          localRows.first['id'] as int,
        );
      }

      if (purchase == null) {
        return;
      }

      await _syncStateSupport.markSynced(
        txn,
        purchase: purchase,
        remoteId: remote.remoteId,
      );
    });
  }

  Future<void> markSyncError({
    required PurchaseSyncPayload purchase,
    required String message,
    required SyncErrorType errorType,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncStateSupport.markSyncError(
        txn,
        purchase: purchase,
        message: message,
        errorType: errorType,
      );
    });
  }

  Future<void> markConflict({
    required PurchaseSyncPayload purchase,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      await _syncStateSupport.markConflict(
        txn,
        purchase: purchase,
        message: message,
        detectedAt: detectedAt,
      );
    });
  }

  Future<PurchaseSyncPayload?> _loadPurchaseForSync(
    DatabaseExecutor db,
    int purchaseId,
  ) async {
    return PurchaseSyncPayloadLoader.load(
      db,
      purchaseId: purchaseId,
      featureKey: featureKey,
    );
  }

  Future<Map<String, Object?>?> _fetchPurchaseRow(
    DatabaseExecutor db,
    int purchaseId,
  ) async {
    final rows = await db.rawQuery(
      PurchaseQuerySql.selectPurchaseById(featureKey: featureKey),
      [purchaseId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<List<PurchaseItemModel>> _fetchItemModels(
    DatabaseExecutor db,
    int purchaseId,
  ) async {
    final rows = await db.query(
      TableNames.itensCompra,
      where: 'compra_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'id ASC',
    );
    return rows.map(PurchaseItemModel.fromMap).toList();
  }

  Future<List<PurchasePaymentModel>> _fetchPaymentModels(
    DatabaseExecutor db,
    int purchaseId,
  ) async {
    final rows = await db.query(
      TableNames.compraPagamentos,
      where: 'compra_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'data_hora DESC, id DESC',
    );
    return rows.map(PurchasePaymentModel.fromMap).toList();
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _mergeNotes(String? current, String? appended) {
    final cleanedCurrent = _cleanNullable(current);
    final cleanedAppended = _cleanNullable(appended);
    if (cleanedCurrent == null) {
      return cleanedAppended;
    }
    if (cleanedAppended == null) {
      return cleanedCurrent;
    }
    return '$cleanedCurrent\n$cleanedAppended';
  }

  Set<int> _collectSupplyIds(List<PurchaseItem> items) {
    return items
        .where((item) => item.isSupply && item.supplyId != null)
        .map((item) => item.supplyId!)
        .toSet();
  }

  Future<void> _markLinkedSuppliesForSync(
    DatabaseExecutor txn,
    List<PurchaseSyncItemPayload> items, {
    required DateTime changedAt,
  }) async {
    final supplyIds = items
        .where((item) => item.isSupply && item.supplyLocalId != null)
        .map((item) => item.supplyLocalId!)
        .toSet();
    if (supplyIds.isEmpty) {
      return;
    }

    final placeholders = List.filled(supplyIds.length, '?').join(',');
    final rows = await txn.query(
      TableNames.supplies,
      columns: const ['id', 'uuid', 'created_at'],
      where: 'id IN ($placeholders)',
      whereArgs: supplyIds.toList(growable: false),
    );

    for (final row in rows) {
      final localId = row['id'] as int;
      final localUuid = row['uuid'] as String;
      final createdAt = DateTime.parse(row['created_at'] as String);
      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: SyncFeatureKeys.supplies,
        localId: localId,
      );

      if (metadata?.identity.remoteId == null) {
        await _syncMetadataRepository.markPendingUpload(
          txn,
          featureKey: SyncFeatureKeys.supplies,
          localId: localId,
          localUuid: localUuid,
          createdAt: createdAt,
          updatedAt: changedAt,
        );
      } else {
        await _syncMetadataRepository.markPendingUpdate(
          txn,
          featureKey: SyncFeatureKeys.supplies,
          localId: localId,
          localUuid: localUuid,
          remoteId: metadata!.identity.remoteId,
          createdAt: createdAt,
          updatedAt: changedAt,
        );
      }

      await _syncQueueRepository.enqueueMutation(
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
