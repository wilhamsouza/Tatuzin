import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/record_identity.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_error_type.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../caixa/data/cash_database_support.dart';
import '../../caixa/domain/entities/cash_enums.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/purchase.dart';
import '../domain/entities/purchase_detail.dart';
import '../domain/entities/purchase_item.dart';
import '../domain/entities/purchase_payment.dart';
import '../domain/entities/purchase_status.dart';
import '../domain/repositories/purchase_repository.dart';
import 'models/purchase_item_model.dart';
import 'models/purchase_model.dart';
import 'models/purchase_payment_model.dart';
import 'models/purchase_sync_payload.dart';
import 'models/remote_purchase_record.dart';

class SqlitePurchaseRepository implements PurchaseRepository {
  SqlitePurchaseRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase);

  static const String featureKey = SyncFeatureKeys.purchases;

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;

  @override
  Future<int> create(PurchaseUpsertInput input) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) async {
      final prepared = await _preparePurchase(txn, input);
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
          'produto_id': item.productId,
          'nome_produto_snapshot': item.productNameSnapshot,
          'unidade_medida_snapshot': item.unitMeasureSnapshot,
          'quantidade_mil': item.quantityMil,
          'custo_unitario_centavos': item.unitCostCents,
          'subtotal_centavos': item.subtotalCents,
        });
      }

      await _applyStockEntries(txn, prepared.items, factor: 1);

      if (prepared.paidAmountCents > 0) {
        await _insertPayment(
          txn,
          purchaseId: purchaseId,
          supplierName: prepared.supplierName,
          amountCents: prepared.paidAmountCents,
          paymentMethod: prepared.paymentMethod,
          registeredAt: now,
          notes: 'Pagamento inicial da compra',
        );
      }

      await _registerPurchaseForSync(
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
      await _validateStockReversal(txn, previousItems);

      final prepared = await _preparePurchase(txn, input);
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      await _applyStockEntries(txn, previousItems, factor: -1);
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
          'produto_id': item.productId,
          'nome_produto_snapshot': item.productNameSnapshot,
          'unidade_medida_snapshot': item.unitMeasureSnapshot,
          'quantidade_mil': item.quantityMil,
          'custo_unitario_centavos': item.unitCostCents,
          'subtotal_centavos': item.subtotalCents,
        });
      }
      await _applyStockEntries(txn, prepared.items, factor: 1);

      if (prepared.paidAmountCents > 0) {
        await _insertPayment(
          txn,
          purchaseId: id,
          supplierName: prepared.supplierName,
          amountCents: prepared.paidAmountCents,
          paymentMethod: prepared.paymentMethod,
          registeredAt: now,
          notes: 'Pagamento registrado na edicao da compra',
        );
      }

      await _registerPurchaseForSync(
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
      await _validateStockReversal(txn, items);
      await _applyStockEntries(txn, items, factor: -1);

      final now = DateTime.now();
      final nowIso = now.toIso8601String();
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

      await _registerPurchaseForSync(
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
    final rows = await database.rawQuery(
      '${_selectPurchaseQuery()} AND c.id = ? GROUP BY ${_purchaseGroupBy()} LIMIT 1',
      [purchaseId],
    );
    if (rows.isEmpty) {
      throw const ValidationException('Compra nao encontrada.');
    }

    final items = await _fetchItemModels(database, purchaseId);
    final payments = await _fetchPaymentModels(database, purchaseId);

    return PurchaseDetail(
      purchase: PurchaseModel.fromMap(rows.first),
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
      await _insertPayment(
        txn,
        purchaseId: input.purchaseId,
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
          'status': _resolveStatus(
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

      await _registerPurchaseForSync(
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
    final buffer = StringBuffer(_selectPurchaseQuery());

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
      ' GROUP BY ${_purchaseGroupBy()} ORDER BY c.data_compra DESC, c.id DESC',
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
    final rows = await database.rawQuery(
      '${_selectPurchaseQuery()} AND c.id = ? GROUP BY ${_purchaseGroupBy()} LIMIT 1',
      [purchaseId],
    );
    if (rows.isEmpty) {
      return null;
    }

    return PurchaseModel.fromMap(rows.first);
  }

  Future<Purchase?> findByRemoteId(String remoteId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectPurchaseQuery()} AND sync.remote_id = ? GROUP BY ${_purchaseGroupBy()} LIMIT 1',
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
      '${_selectPurchaseQuery()} GROUP BY ${_purchaseGroupBy()} ORDER BY c.data_compra DESC, c.id DESC',
    );
    return rows.map(PurchaseModel.fromMap).toList();
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
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: purchase.purchaseId,
        localUuid: purchase.purchaseUuid,
        remoteId: remote.remoteId,
        origin: RecordOrigin.local,
        createdAt: purchase.createdAt,
        updatedAt: purchase.updatedAt,
        syncedAt: DateTime.now(),
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

      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: purchase.purchaseId,
        localUuid: purchase.purchaseUuid,
        remoteId: remote.remoteId,
        origin: RecordOrigin.local,
        createdAt: purchase.createdAt,
        updatedAt: purchase.updatedAt,
        syncedAt: DateTime.now(),
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
      await _syncMetadataRepository.markSyncError(
        txn,
        featureKey: featureKey,
        localId: purchase.purchaseId,
        localUuid: purchase.purchaseUuid,
        remoteId: purchase.remoteId,
        createdAt: purchase.createdAt,
        updatedAt: DateTime.now(),
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
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: featureKey,
        localId: purchase.purchaseId,
        localUuid: purchase.purchaseUuid,
        remoteId: purchase.remoteId,
        createdAt: purchase.createdAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> _registerPurchaseForSync(
    DatabaseExecutor txn, {
    required int purchaseId,
    required String purchaseUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final metadata = await _syncMetadataRepository.findByLocalId(
      txn,
      featureKey: featureKey,
      localId: purchaseId,
    );
    final remoteId = metadata?.identity.remoteId;
    if (remoteId == null) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: featureKey,
        localId: purchaseId,
        localUuid: purchaseUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: purchaseId,
        localUuid: purchaseUuid,
        remoteId: remoteId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: featureKey,
      entityType: 'purchase',
      localEntityId: purchaseId,
      localUuid: purchaseUuid,
      remoteId: remoteId,
      operation: remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
  }

  Future<PurchaseSyncPayload?> _loadPurchaseForSync(
    DatabaseExecutor db,
    int purchaseId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        c.*,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        supplier_sync.remote_id AS supplier_remote_id
      FROM ${TableNames.compras} c
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = c.id
      LEFT JOIN ${TableNames.syncRegistros} supplier_sync
        ON supplier_sync.feature_key = '${SyncFeatureKeys.suppliers}'
        AND supplier_sync.local_id = c.fornecedor_id
      WHERE c.id = ?
      LIMIT 1
    ''',
      [purchaseId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final itemsRows = await db.rawQuery(
      '''
      SELECT
        ic.*,
        product_sync.remote_id AS produto_remote_id
      FROM ${TableNames.itensCompra} ic
      LEFT JOIN ${TableNames.syncRegistros} product_sync
        ON product_sync.feature_key = '${SyncFeatureKeys.products}'
        AND product_sync.local_id = ic.produto_id
      WHERE ic.compra_id = ?
      ORDER BY ic.id ASC
    ''',
      [purchaseId],
    );
    final paymentRows = await db.query(
      TableNames.compraPagamentos,
      where: 'compra_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'data_hora ASC, id ASC',
    );

    return PurchaseSyncPayload(
      purchaseId: row['id'] as int,
      purchaseUuid: row['uuid'] as String,
      remoteId: row['sync_remote_id'] as String?,
      supplierLocalId: row['fornecedor_id'] as int,
      supplierRemoteId: row['supplier_remote_id'] as String?,
      documentNumber: row['numero_documento'] as String?,
      notes: row['observacao'] as String?,
      purchasedAt: DateTime.parse(row['data_compra'] as String),
      dueDate: row['data_vencimento'] == null
          ? null
          : DateTime.parse(row['data_vencimento'] as String),
      paymentMethod: row['forma_pagamento'] == null
          ? null
          : PaymentMethodX.fromDb(row['forma_pagamento'] as String),
      status: PurchaseStatusX.fromDb(row['status'] as String),
      subtotalCents: row['subtotal_centavos'] as int,
      discountCents: row['desconto_centavos'] as int? ?? 0,
      surchargeCents: row['acrescimo_centavos'] as int? ?? 0,
      freightCents: row['frete_centavos'] as int? ?? 0,
      finalAmountCents: row['valor_final_centavos'] as int,
      paidAmountCents: row['valor_pago_centavos'] as int? ?? 0,
      pendingAmountCents: row['valor_pendente_centavos'] as int? ?? 0,
      cancelledAt: row['cancelada_em'] == null
          ? null
          : DateTime.parse(row['cancelada_em'] as String),
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      syncStatus: syncStatusFromStorage(row['sync_status'] as String?),
      lastSyncedAt: row['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(row['sync_last_synced_at'] as String),
      items: itemsRows
          .map(
            (item) => PurchaseSyncItemPayload(
              itemId: item['id'] as int,
              itemUuid: item['uuid'] as String,
              productLocalId: item['produto_id'] as int,
              productRemoteId: item['produto_remote_id'] as String?,
              productNameSnapshot: item['nome_produto_snapshot'] as String,
              unitMeasureSnapshot:
                  item['unidade_medida_snapshot'] as String? ?? 'un',
              quantityMil: item['quantidade_mil'] as int? ?? 0,
              unitCostCents: item['custo_unitario_centavos'] as int? ?? 0,
              subtotalCents: item['subtotal_centavos'] as int? ?? 0,
            ),
          )
          .toList(),
      payments: paymentRows
          .map(
            (payment) => PurchaseSyncPaymentPayload(
              paymentId: payment['id'] as int,
              paymentUuid: payment['uuid'] as String,
              amountCents: payment['valor_centavos'] as int? ?? 0,
              paymentMethod: PaymentMethodX.fromDb(
                payment['forma_pagamento'] as String? ?? 'dinheiro',
              ),
              paidAt: DateTime.parse(payment['data_hora'] as String),
              notes: payment['observacao'] as String?,
            ),
          )
          .toList(),
    );
  }

  Future<Map<String, Object?>?> _fetchPurchaseRow(
    DatabaseExecutor db,
    int purchaseId,
  ) async {
    final rows = await db.rawQuery(
      '${_selectPurchaseQuery()} AND c.id = ? GROUP BY ${_purchaseGroupBy()} LIMIT 1',
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

  Future<_PreparedPurchase> _preparePurchase(
    DatabaseExecutor db,
    PurchaseUpsertInput input,
  ) async {
    if (input.items.isEmpty) {
      throw const ValidationException(
        'Adicione pelo menos um item para confirmar a compra.',
      );
    }
    if (input.initialPaidAmountCents < 0) {
      throw const ValidationException(
        'O valor pago na compra nao pode ser negativo.',
      );
    }
    if (input.initialPaidAmountCents > 0 &&
        (input.paymentMethod == null ||
            input.paymentMethod == PaymentMethod.fiado)) {
      throw const ValidationException(
        'Informe uma forma de pagamento valida para registrar a saida no caixa.',
      );
    }

    final supplierRows = await db.query(
      TableNames.fornecedores,
      columns: ['id', 'nome', 'deletado_em'],
      where: 'id = ?',
      whereArgs: [input.supplierId],
      limit: 1,
    );
    if (supplierRows.isEmpty ||
        (supplierRows.first['deletado_em'] as String?) != null) {
      throw const ValidationException('Fornecedor nao encontrado.');
    }

    final uniqueProductIds = input.items
        .map((item) => item.productId)
        .toSet()
        .toList();
    final placeholders = List.filled(uniqueProductIds.length, '?').join(',');
    final productRows = await db.rawQuery('''
      SELECT
        id,
        nome,
        unidade_medida,
        estoque_mil,
        deletado_em
      FROM ${TableNames.produtos}
      WHERE id IN ($placeholders)
    ''', uniqueProductIds);
    final productMap = {for (final row in productRows) row['id'] as int: row};

    final items = <PurchaseItemModel>[];
    var subtotalCents = 0;

    for (final inputItem in input.items) {
      if (inputItem.quantityMil <= 0) {
        throw const ValidationException(
          'A quantidade dos itens da compra deve ser maior que zero.',
        );
      }
      if (inputItem.unitCostCents < 0) {
        throw const ValidationException(
          'O custo unitario do item nao pode ser negativo.',
        );
      }

      final productRow = productMap[inputItem.productId];
      if (productRow == null ||
          (productRow['deletado_em'] as String?) != null) {
        throw const ValidationException(
          'Um dos produtos selecionados nao esta mais disponivel.',
        );
      }
      final resolvedProductRow = productRow;

      final itemSubtotal = _calculateSubtotalCents(
        quantityMil: inputItem.quantityMil,
        unitCostCents: inputItem.unitCostCents,
      );
      subtotalCents += itemSubtotal;

      items.add(
        PurchaseItemModel(
          id: 0,
          uuid: '',
          purchaseId: 0,
          productId: inputItem.productId,
          productNameSnapshot: resolvedProductRow['nome'] as String,
          unitMeasureSnapshot:
              resolvedProductRow['unidade_medida'] as String? ?? 'un',
          quantityMil: inputItem.quantityMil,
          unitCostCents: inputItem.unitCostCents,
          subtotalCents: itemSubtotal,
        ),
      );
    }

    final finalAmountCents =
        subtotalCents -
        input.discountCents +
        input.surchargeCents +
        input.freightCents;
    if (finalAmountCents < 0) {
      throw const ValidationException(
        'O valor final da compra nao pode ficar negativo.',
      );
    }
    if (input.initialPaidAmountCents > finalAmountCents) {
      throw const ValidationException(
        'O valor pago nao pode ser maior que o valor final da compra.',
      );
    }

    return _PreparedPurchase(
      supplierName: supplierRows.first['nome'] as String,
      items: items,
      subtotalCents: subtotalCents,
      finalAmountCents: finalAmountCents,
      paidAmountCents: input.initialPaidAmountCents,
      pendingAmountCents: finalAmountCents - input.initialPaidAmountCents,
      paymentMethod: input.paymentMethod,
      status: _resolveStatus(
        finalAmountCents: finalAmountCents,
        paidAmountCents: input.initialPaidAmountCents,
        dueDate: input.dueDate,
      ),
    );
  }

  PurchaseStatus _resolveStatus({
    required int finalAmountCents,
    required int paidAmountCents,
    required DateTime? dueDate,
  }) {
    final pending = finalAmountCents - paidAmountCents;
    if (pending <= 0) {
      return PurchaseStatus.paga;
    }
    if (paidAmountCents > 0) {
      return PurchaseStatus.parcialmentePaga;
    }
    if (dueDate != null) {
      return PurchaseStatus.aberta;
    }
    return PurchaseStatus.recebida;
  }

  Future<void> _applyStockEntries(
    DatabaseExecutor db,
    List<PurchaseItem> items, {
    required int factor,
  }) async {
    final quantitiesByProduct = <int, int>{};
    for (final item in items) {
      quantitiesByProduct.update(
        item.productId,
        (current) => current + (item.quantityMil * factor),
        ifAbsent: () => item.quantityMil * factor,
      );
    }

    for (final entry in quantitiesByProduct.entries) {
      final productRows = await db.query(
        TableNames.produtos,
        columns: ['estoque_mil'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw const ValidationException(
          'Nao foi possivel atualizar o estoque de um dos produtos.',
        );
      }
      final currentStock = productRows.first['estoque_mil'] as int? ?? 0;
      final nextStock = currentStock + entry.value;
      if (nextStock < 0) {
        throw const ValidationException(
          'Nao ha estoque suficiente para cancelar esta compra.',
        );
      }

      await db.update(
        TableNames.produtos,
        {
          'estoque_mil': nextStock,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  Future<void> _validateStockReversal(
    DatabaseExecutor db,
    List<PurchaseItem> items,
  ) async {
    final quantitiesByProduct = <int, int>{};
    for (final item in items) {
      quantitiesByProduct.update(
        item.productId,
        (current) => current + item.quantityMil,
        ifAbsent: () => item.quantityMil,
      );
    }

    for (final entry in quantitiesByProduct.entries) {
      final rows = await db.query(
        TableNames.produtos,
        columns: ['estoque_mil', 'nome'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const ValidationException(
          'Nao foi possivel validar o estoque de um dos itens da compra.',
        );
      }
      final currentStock = rows.first['estoque_mil'] as int? ?? 0;
      if (currentStock < entry.value) {
        throw ValidationException(
          'Nao ha estoque suficiente para reverter a compra do produto ${rows.first['nome']}.',
        );
      }
    }
  }

  Future<_PurchasePaymentRecord> _insertPayment(
    DatabaseExecutor db, {
    required int purchaseId,
    required String supplierName,
    required int amountCents,
    required PaymentMethod? paymentMethod,
    required DateTime registeredAt,
    required String? notes,
  }) async {
    if (paymentMethod == null || paymentMethod == PaymentMethod.fiado) {
      throw const ValidationException(
        'Forma de pagamento invalida para a compra.',
      );
    }

    final sessionId = await CashDatabaseSupport.ensureOpenSession(
      db,
      timestamp: registeredAt,
      userId: _operationalContext.currentLocalUserId,
    );
    await CashSessionMathSupport.applySessionDeltas(
      db,
      sessionId: sessionId,
      withdrawalsDeltaCents: amountCents,
    );
    final movement = await CashDatabaseSupport.insertMovement(
      db,
      sessionId: sessionId,
      type: CashMovementType.sangria,
      amountCents: -amountCents,
      timestamp: registeredAt,
      referenceType: 'compra',
      referenceId: purchaseId,
      description: 'Pagamento de compra para $supplierName',
      paymentMethod: paymentMethod,
    );

    final paymentUuid = IdGenerator.next();
    final paymentId = await db.insert(TableNames.compraPagamentos, {
      'uuid': paymentUuid,
      'compra_id': purchaseId,
      'valor_centavos': amountCents,
      'forma_pagamento': paymentMethod.dbValue,
      'data_hora': registeredAt.toIso8601String(),
      'observacao': _cleanNullable(notes),
      'caixa_movimento_id': movement.id,
    });

    return _PurchasePaymentRecord(
      paymentId: paymentId,
      paymentUuid: paymentUuid,
      amountCents: amountCents,
      paymentMethod: paymentMethod,
      paidAt: registeredAt,
      notes: notes,
      cashMovementId: movement.id,
    );
  }

  int _calculateSubtotalCents({
    required int quantityMil,
    required int unitCostCents,
  }) {
    return ((quantityMil * unitCostCents) / 1000).round();
  }

  String _selectPurchaseQuery() {
    return '''
      SELECT
        c.*,
        f.nome AS fornecedor_nome,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        COUNT(ic.id) AS itens_quantidade
      FROM ${TableNames.compras} c
      INNER JOIN ${TableNames.fornecedores} f
        ON f.id = c.fornecedor_id
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = c.id
      LEFT JOIN ${TableNames.itensCompra} ic
        ON ic.compra_id = c.id
      WHERE 1 = 1
    ''';
  }

  String _purchaseGroupBy() {
    return '''
      c.id,
      c.uuid,
      c.fornecedor_id,
      c.numero_documento,
      c.observacao,
      c.data_compra,
      c.data_vencimento,
      c.forma_pagamento,
      c.status,
      c.subtotal_centavos,
      c.desconto_centavos,
      c.acrescimo_centavos,
      c.frete_centavos,
      c.valor_final_centavos,
      c.valor_pago_centavos,
      c.valor_pendente_centavos,
      c.cancelada_em,
      c.criado_em,
      c.atualizado_em,
      f.nome,
      sync.remote_id,
      sync.sync_status,
      sync.last_synced_at
    ''';
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
}

class _PreparedPurchase {
  const _PreparedPurchase({
    required this.supplierName,
    required this.items,
    required this.subtotalCents,
    required this.finalAmountCents,
    required this.paidAmountCents,
    required this.pendingAmountCents,
    required this.paymentMethod,
    required this.status,
  });

  final String supplierName;
  final List<PurchaseItemModel> items;
  final int subtotalCents;
  final int finalAmountCents;
  final int paidAmountCents;
  final int pendingAmountCents;
  final PaymentMethod? paymentMethod;
  final PurchaseStatus status;
}

class _PurchasePaymentRecord {
  const _PurchasePaymentRecord({
    required this.paymentId,
    required this.paymentUuid,
    required this.amountCents,
    required this.paymentMethod,
    required this.paidAt,
    required this.notes,
    required this.cashMovementId,
  });

  final int paymentId;
  final String paymentUuid;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final DateTime paidAt;
  final String? notes;
  final int? cashMovementId;
}
