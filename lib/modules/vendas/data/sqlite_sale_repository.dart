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
import '../../carrinho/domain/entities/cart_item.dart';
import '../domain/entities/checkout_input.dart';
import '../domain/entities/completed_sale.dart';
import '../domain/entities/sale_enums.dart';
import '../domain/repositories/sale_repository.dart';
import 'models/sale_cancellation_sync_payload.dart';
import 'models/sale_sync_payload.dart';

class SqliteSaleRepository implements SaleRepository {
  SqliteSaleRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase);

  static const String featureKey = SyncFeatureKeys.sales;
  static const String cancellationFeatureKey =
      SyncFeatureKeys.saleCancellations;
  static const String financialEventFeatureKey =
      SyncFeatureKeys.financialEvents;

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;

  @override
  Future<CompletedSale> completeCashSale({required CheckoutInput input}) async {
    final database = await _appDatabase.database;

    return database.transaction<CompletedSale>((txn) async {
      return _completeSale(txn, input: input, saleType: SaleType.cash);
    });
  }

  @override
  Future<CompletedSale> completeCreditSale({
    required CheckoutInput input,
  }) async {
    final database = await _appDatabase.database;

    return database.transaction<CompletedSale>((txn) async {
      return _completeSale(txn, input: input, saleType: SaleType.fiado);
    });
  }

  @override
  Future<void> cancelSale({required int saleId, required String reason}) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      final saleRows = await txn.rawQuery(
        '''
        SELECT
          v.*,
          f.id AS fiado_id,
          f.valor_original_centavos AS fiado_valor_original_centavos,
          f.valor_aberto_centavos AS fiado_valor_aberto_centavos,
          f.status AS fiado_status
        FROM ${TableNames.vendas} v
        LEFT JOIN ${TableNames.fiado} f ON f.venda_id = v.id
        WHERE v.id = ?
        LIMIT 1
      ''',
        [saleId],
      );

      if (saleRows.isEmpty) {
        throw const ValidationException(
          'Venda nao encontrada para cancelamento.',
        );
      }

      final saleRow = saleRows.first;
      if ((saleRow['status'] as String) == SaleStatus.cancelled.dbValue) {
        throw const ValidationException('Esta venda ja foi cancelada.');
      }

      final soldItems = await txn.query(
        TableNames.itensVenda,
        where: 'venda_id = ?',
        whereArgs: [saleId],
      );

      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      for (final itemRow in soldItems) {
        final productId = itemRow['produto_id'] as int;
        final quantityMil = itemRow['quantidade_mil'] as int;
        final productRows = await txn.query(
          TableNames.produtos,
          columns: ['estoque_mil'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );

        if (productRows.isEmpty) {
          continue;
        }

        final currentStockMil = productRows.first['estoque_mil'] as int? ?? 0;
        await txn.update(
          TableNames.produtos,
          {
            'estoque_mil': currentStockMil + quantityMil,
            'atualizado_em': nowIso,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      final saleType = SaleTypeX.fromDb(saleRow['tipo_venda'] as String);
      final paymentMethod = PaymentMethodX.fromDb(
        saleRow['forma_pagamento'] as String,
      );
      final finalCents = saleRow['valor_final_centavos'] as int;
      final receiptNumber = saleRow['numero_cupom'] as String;

      if (saleType == SaleType.cash) {
        final sessionId = await CashDatabaseSupport.ensureOpenSession(
          txn,
          timestamp: now,
          userId: _operationalContext.currentLocalUserId,
          notes:
              'Sessao aberta automaticamente para registrar cancelamento de venda.',
        );
        await CashSessionMathSupport.applySessionDeltas(
          txn,
          sessionId: sessionId,
          salesDeltaCents: -finalCents,
        );
        final cashMovement = await CashDatabaseSupport.insertMovement(
          txn,
          sessionId: sessionId,
          type: CashMovementType.cancellation,
          amountCents: -finalCents,
          timestamp: now,
          referenceType: 'venda',
          referenceId: saleId,
          description:
              'Cancelamento da venda $receiptNumber. Motivo: ${reason.trim()}',
          paymentMethod: paymentMethod,
        );
        await _registerCashEventForSync(
          txn,
          movementId: cashMovement.id,
          movementUuid: cashMovement.uuid,
          createdAt: now,
        );
      } else {
        final fiadoId = saleRow['fiado_id'] as int?;
        final clientId = saleRow['cliente_id'] as int?;
        final fiadoOriginalCents =
            saleRow['fiado_valor_original_centavos'] as int? ?? 0;
        final fiadoOpenCents =
            saleRow['fiado_valor_aberto_centavos'] as int? ?? 0;
        final totalPaidCents = fiadoOriginalCents - fiadoOpenCents;
        int? cashMovementId;

        if (totalPaidCents > 0) {
          final sessionId = await CashDatabaseSupport.ensureOpenSession(
            txn,
            timestamp: now,
            userId: _operationalContext.currentLocalUserId,
            notes:
                'Sessao aberta automaticamente para registrar estorno de fiado.',
          );
          await CashSessionMathSupport.applySessionDeltas(
            txn,
            sessionId: sessionId,
            fiadoReceiptsDeltaCents: -totalPaidCents,
          );
          final cashMovement = await CashDatabaseSupport.insertMovement(
            txn,
            sessionId: sessionId,
            type: CashMovementType.cancellation,
            amountCents: -totalPaidCents,
            timestamp: now,
            referenceType: 'fiado',
            referenceId: fiadoId,
            description:
                'Estorno dos recebimentos do fiado da venda $receiptNumber. Motivo: ${reason.trim()}',
          );
          cashMovementId = cashMovement.id;
          await _registerCashEventForSync(
            txn,
            movementId: cashMovement.id,
            movementUuid: cashMovement.uuid,
            createdAt: now,
          );
        }

        if (fiadoId != null) {
          await txn.update(
            TableNames.fiado,
            {
              'valor_aberto_centavos': 0,
              'status': 'cancelado',
              'atualizado_em': nowIso,
              'quitado_em': null,
            },
            where: 'id = ?',
            whereArgs: [fiadoId],
          );

          if (clientId != null) {
            await _updateClientDebt(
              txn,
              clientId: clientId,
              deltaCents: -fiadoOpenCents,
              updatedAtIso: nowIso,
            );
          }

          await txn.insert(TableNames.fiadoLancamentos, {
            'uuid': IdGenerator.next(),
            'fiado_id': fiadoId,
            'cliente_id': clientId,
            'tipo_lancamento': 'cancelamento',
            'valor_centavos': -fiadoOpenCents,
            'data_lancamento': nowIso,
            'observacao':
                'Cancelamento da venda $receiptNumber. Motivo: ${reason.trim()}',
            'caixa_movimento_id': cashMovementId,
          });
        }
      }

      await txn.update(
        TableNames.vendas,
        {
          'status': SaleStatus.cancelled.dbValue,
          'cancelada_em': nowIso,
          'observacao': _mergeCancellationReason(
            saleRow['observacao'] as String?,
            reason,
          ),
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      final saleSync = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: saleId,
      );
      final remoteSaleId = saleSync?.identity.remoteId;
      if (remoteSaleId == null) {
        await _syncMetadataRepository.markPendingUpload(
          txn,
          featureKey: featureKey,
          localId: saleId,
          localUuid: saleRow['uuid'] as String,
          createdAt: DateTime.parse(saleRow['data_venda'] as String),
          updatedAt: now,
        );
        await _syncQueueRepository.enqueueMutation(
          txn,
          featureKey: featureKey,
          entityType: 'sale',
          localEntityId: saleId,
          localUuid: saleRow['uuid'] as String,
          remoteId: null,
          operation: SyncQueueOperation.create,
          localUpdatedAt: now,
        );
      }

      await _registerCancellationForSync(
        txn,
        saleId: saleId,
        saleUuid: saleRow['uuid'] as String,
        canceledAt: now,
      );
    });
  }

  Future<CompletedSale> _completeSale(
    DatabaseExecutor txn, {
    required CheckoutInput input,
    required SaleType saleType,
  }) async {
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final totalCents = input.itemsTotalCents;
    final finalCents = input.finalTotalCents;
    final saleUuid = IdGenerator.next();

    if (finalCents <= 0) {
      throw const ValidationException(
        'O valor final da venda precisa ser maior que zero.',
      );
    }

    if (input.clientId != null) {
      await _ensureClientExists(txn, input.clientId!);
    }

    if (saleType == SaleType.fiado && input.dueDate == null) {
      throw const ValidationException(
        'Informe o vencimento para registrar uma venda fiado.',
      );
    }

    final productSnapshots = await _loadProductSnapshots(txn, input.items);
    final receiptNumber = now.microsecondsSinceEpoch.toString();

    final saleId = await txn.insert(TableNames.vendas, {
      'uuid': saleUuid,
      'cliente_id': input.clientId,
      'tipo_venda': saleType.dbValue,
      'forma_pagamento': input.paymentMethod.dbValue,
      'status': SaleStatus.active.dbValue,
      'desconto_centavos': input.discountCents,
      'acrescimo_centavos': input.surchargeCents,
      'valor_total_centavos': totalCents,
      'valor_final_centavos': finalCents,
      'numero_cupom': receiptNumber,
      'data_venda': nowIso,
      'usuario_id': _operationalContext.currentLocalUserId,
      'observacao': _cleanNullable(input.notes),
      'cancelada_em': null,
      'venda_origem_id': null,
    });

    await _persistItemsAndDecreaseStock(
      txn,
      soldAtIso: nowIso,
      saleId: saleId,
      items: input.items,
      snapshots: productSnapshots,
    );

    int? fiadoId;
    if (saleType == SaleType.cash) {
      final sessionId = await CashDatabaseSupport.ensureOpenSession(
        txn,
        timestamp: now,
        userId: _operationalContext.currentLocalUserId,
      );
      await CashSessionMathSupport.applySessionDeltas(
        txn,
        sessionId: sessionId,
        salesDeltaCents: finalCents,
      );
      final cashMovement = await CashDatabaseSupport.insertMovement(
        txn,
        sessionId: sessionId,
        type: CashMovementType.sale,
        amountCents: finalCents,
        timestamp: now,
        referenceType: 'venda',
        referenceId: saleId,
        description:
            'Venda $receiptNumber recebida via ${input.paymentMethod.label}.',
        paymentMethod: input.paymentMethod,
      );
      await _registerCashEventForSync(
        txn,
        movementId: cashMovement.id,
        movementUuid: cashMovement.uuid,
        createdAt: now,
      );
    } else {
      final fiadoUuid = IdGenerator.next();
      fiadoId = await txn.insert(TableNames.fiado, {
        'uuid': fiadoUuid,
        'venda_id': saleId,
        'cliente_id': input.clientId,
        'valor_original_centavos': finalCents,
        'valor_aberto_centavos': finalCents,
        'vencimento': input.dueDate!.toIso8601String(),
        'status': 'pendente',
        'criado_em': nowIso,
        'atualizado_em': nowIso,
        'quitado_em': null,
      });

      await txn.insert(TableNames.fiadoLancamentos, {
        'uuid': IdGenerator.next(),
        'fiado_id': fiadoId,
        'cliente_id': input.clientId,
        'tipo_lancamento': 'abertura',
        'valor_centavos': finalCents,
        'data_lancamento': nowIso,
        'observacao': 'Abertura da nota referente a venda $receiptNumber.',
        'caixa_movimento_id': null,
      });

      await _updateClientDebt(
        txn,
        clientId: input.clientId!,
        deltaCents: finalCents,
        updatedAtIso: nowIso,
      );
    }

    await _registerSaleForSync(
      txn,
      saleId: saleId,
      saleUuid: saleUuid,
      createdAt: now,
    );

    return CompletedSale(
      saleId: saleId,
      receiptNumber: receiptNumber,
      totalCents: finalCents,
      itemsCount: input.items.length,
      soldAt: now,
      saleType: saleType,
      paymentMethod: input.paymentMethod,
      clientId: input.clientId,
      fiadoId: fiadoId,
    );
  }

  Future<Map<int, _ProductSnapshot>> _loadProductSnapshots(
    DatabaseExecutor txn,
    List<CartItem> items,
  ) async {
    final snapshots = <int, _ProductSnapshot>{};

    for (final item in items) {
      final productRows = await txn.query(
        TableNames.produtos,
        columns: [
          'id',
          'nome',
          'estoque_mil',
          'deletado_em',
          'custo_centavos',
          'unidade_medida',
          'tipo_produto',
        ],
        where: 'id = ?',
        whereArgs: [item.productId],
        limit: 1,
      );

      if (productRows.isEmpty || productRows.first['deletado_em'] != null) {
        throw ValidationException(
          'Produto indisponivel para venda: ${item.productName}',
        );
      }

      final row = productRows.first;
      final currentStockMil = row['estoque_mil'] as int? ?? 0;
      if (currentStockMil < item.quantityMil) {
        throw StockConflictException(
          'Estoque insuficiente para ${item.productName}. Disponivel: ${currentStockMil ~/ 1000}',
        );
      }

      snapshots[item.productId] = _ProductSnapshot(
        productId: item.productId,
        stockMil: currentStockMil,
        costCents: row['custo_centavos'] as int? ?? 0,
        unitMeasure: row['unidade_medida'] as String? ?? item.unitMeasure,
        productType: row['tipo_produto'] as String? ?? item.productType,
      );
    }

    return snapshots;
  }

  Future<void> _persistItemsAndDecreaseStock(
    DatabaseExecutor txn, {
    required String soldAtIso,
    required int saleId,
    required List<CartItem> items,
    required Map<int, _ProductSnapshot> snapshots,
  }) async {
    for (final item in items) {
      final snapshot = snapshots[item.productId]!;
      final newStockMil = snapshot.stockMil - item.quantityMil;

      await txn.update(
        TableNames.produtos,
        {'estoque_mil': newStockMil, 'atualizado_em': soldAtIso},
        where: 'id = ?',
        whereArgs: [item.productId],
      );

      final quantityUnits = item.quantityMil ~/ 1000;
      final costTotalCents = snapshot.costCents * quantityUnits;

      await txn.insert(TableNames.itensVenda, {
        'uuid': IdGenerator.next(),
        'venda_id': saleId,
        'produto_id': item.productId,
        'nome_produto_snapshot': item.productName,
        'quantidade_mil': item.quantityMil,
        'valor_unitario_centavos': item.unitPriceCents,
        'subtotal_centavos': item.subtotalCents,
        'custo_unitario_centavos': snapshot.costCents,
        'custo_total_centavos': costTotalCents,
        'unidade_medida_snapshot': snapshot.unitMeasure,
        'tipo_produto_snapshot': snapshot.productType,
      });
    }
  }

  Future<SaleSyncPayload?> findSaleForSync(int saleId) async {
    final database = await _appDatabase.database;
    return _loadSaleForSync(database, saleId);
  }

  Future<SaleCancellationSyncPayload?> findSaleCancellationForSync(
    int saleId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        v.id,
        v.uuid,
        v.valor_final_centavos,
        v.tipo_venda,
        v.cancelada_em,
        v.observacao,
        sales_sync.remote_id AS sale_remote_id,
        cancel_sync.remote_id AS cancel_remote_id,
        cancel_sync.sync_status AS cancel_sync_status,
        cancel_sync.last_synced_at AS cancel_last_synced_at
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.syncRegistros} sales_sync
        ON sales_sync.feature_key = '$featureKey'
        AND sales_sync.local_id = v.id
      LEFT JOIN ${TableNames.syncRegistros} cancel_sync
        ON cancel_sync.feature_key = '$cancellationFeatureKey'
        AND cancel_sync.local_id = v.id
      WHERE v.id = ?
      LIMIT 1
    ''',
      [saleId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final canceledAtIso = row['cancelada_em'] as String?;
    if (canceledAtIso == null) {
      return null;
    }

    return SaleCancellationSyncPayload(
      saleId: row['id'] as int,
      saleUuid: row['uuid'] as String,
      saleRemoteId: row['sale_remote_id'] as String?,
      remoteId: row['cancel_remote_id'] as String?,
      amountCents: row['valor_final_centavos'] as int? ?? 0,
      paymentType: row['tipo_venda'] as String? ?? 'vista',
      canceledAt: DateTime.parse(canceledAtIso),
      updatedAt: DateTime.parse(canceledAtIso),
      notes: row['observacao'] as String?,
      syncStatus: syncStatusFromStorage(row['cancel_sync_status'] as String?),
      lastSyncedAt: row['cancel_last_synced_at'] == null
          ? null
          : DateTime.parse(row['cancel_last_synced_at'] as String),
    );
  }

  Future<void> markSynced({
    required SaleSyncPayload sale,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        remoteId: remoteId,
        origin: RecordOrigin.local,
        createdAt: sale.soldAt,
        updatedAt: sale.updatedAt,
        syncedAt: syncedAt,
      );
    });
  }

  Future<void> markSyncError({
    required SaleSyncPayload sale,
    required String message,
    required SyncErrorType errorType,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      await _syncMetadataRepository.markSyncError(
        txn,
        featureKey: featureKey,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        remoteId: sale.remoteId,
        createdAt: sale.soldAt,
        updatedAt: now,
        message: message,
        errorType: errorType,
      );
    });
  }

  Future<void> markConflict({
    required SaleSyncPayload sale,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: featureKey,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        remoteId: sale.remoteId,
        createdAt: sale.soldAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> markCancellationSynced({
    required SaleCancellationSyncPayload sale,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: cancellationFeatureKey,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        remoteId: remoteId,
        origin: RecordOrigin.local,
        createdAt: sale.canceledAt,
        updatedAt: sale.updatedAt,
        syncedAt: syncedAt,
      );
    });
  }

  Future<void> markCancellationConflict({
    required SaleCancellationSyncPayload sale,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: cancellationFeatureKey,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        remoteId: sale.remoteId,
        createdAt: sale.canceledAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> _registerSaleForSync(
    DatabaseExecutor txn, {
    required int saleId,
    required String saleUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: featureKey,
      localId: saleId,
      localUuid: saleUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: featureKey,
      entityType: 'sale',
      localEntityId: saleId,
      localUuid: saleUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  Future<void> _registerCashEventForSync(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: SyncFeatureKeys.cashEvents,
      localId: movementId,
      localUuid: movementUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.cashEvents,
      entityType: 'cash_event',
      localEntityId: movementId,
      localUuid: movementUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  Future<void> _registerCancellationForSync(
    DatabaseExecutor txn, {
    required int saleId,
    required String saleUuid,
    required DateTime canceledAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: cancellationFeatureKey,
      localId: saleId,
      localUuid: saleUuid,
      createdAt: canceledAt,
      updatedAt: canceledAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: financialEventFeatureKey,
      entityType: 'sale_canceled_event',
      localEntityId: saleId,
      localUuid: saleUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: canceledAt,
    );
  }

  Future<SaleSyncPayload?> _loadSaleForSync(
    DatabaseExecutor db,
    int saleId,
  ) async {
    final saleRows = await db.rawQuery(
      '''
      SELECT
        v.id,
        v.uuid,
        v.cliente_id,
        v.tipo_venda,
        v.forma_pagamento,
        v.status,
        v.valor_final_centavos,
        v.numero_cupom,
        v.data_venda,
        v.observacao,
        COALESCE(v.cancelada_em, v.data_venda) AS venda_atualizada_em,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        client_sync.remote_id AS cliente_remote_id
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = v.id
      LEFT JOIN ${TableNames.syncRegistros} client_sync
        ON client_sync.feature_key = '${SyncFeatureKeys.customers}'
        AND client_sync.local_id = v.cliente_id
      WHERE v.id = ?
      LIMIT 1
    ''',
      [saleId],
    );

    if (saleRows.isEmpty) {
      return null;
    }

    final itemRows = await db.rawQuery(
      '''
      SELECT
        iv.id,
        iv.produto_id,
        iv.nome_produto_snapshot,
        iv.quantidade_mil,
        iv.valor_unitario_centavos,
        iv.subtotal_centavos,
        iv.custo_unitario_centavos,
        iv.custo_total_centavos,
        iv.unidade_medida_snapshot,
        iv.tipo_produto_snapshot,
        product_sync.remote_id AS produto_remote_id
      FROM ${TableNames.itensVenda} iv
      LEFT JOIN ${TableNames.syncRegistros} product_sync
        ON product_sync.feature_key = '${SyncFeatureKeys.products}'
        AND product_sync.local_id = iv.produto_id
      WHERE iv.venda_id = ?
      ORDER BY iv.id ASC
    ''',
      [saleId],
    );

    final items = itemRows
        .map(
          (row) => SaleSyncItemPayload(
            itemId: row['id'] as int,
            productLocalId: row['produto_id'] as int?,
            productRemoteId: row['produto_remote_id'] as String?,
            productNameSnapshot: row['nome_produto_snapshot'] as String,
            quantityMil: row['quantidade_mil'] as int,
            unitPriceCents: row['valor_unitario_centavos'] as int,
            totalPriceCents: row['subtotal_centavos'] as int,
            unitCostCents: row['custo_unitario_centavos'] as int,
            totalCostCents: row['custo_total_centavos'] as int,
            unitMeasure: row['unidade_medida_snapshot'] as String,
            productType: row['tipo_produto_snapshot'] as String,
          ),
        )
        .toList();

    final totalCostCents = items.fold<int>(
      0,
      (sum, item) => sum + item.totalCostCents,
    );
    final saleRow = saleRows.first;

    return SaleSyncPayload(
      saleId: saleRow['id'] as int,
      saleUuid: saleRow['uuid'] as String,
      receiptNumber: saleRow['numero_cupom'] as String,
      saleType: SaleTypeX.fromDb(saleRow['tipo_venda'] as String),
      paymentMethod: PaymentMethodX.fromDb(
        saleRow['forma_pagamento'] as String,
      ),
      status: SaleStatusX.fromDb(saleRow['status'] as String),
      totalAmountCents: saleRow['valor_final_centavos'] as int,
      totalCostCents: totalCostCents,
      soldAt: DateTime.parse(saleRow['data_venda'] as String),
      updatedAt: DateTime.parse(saleRow['venda_atualizada_em'] as String),
      clientLocalId: saleRow['cliente_id'] as int?,
      clientRemoteId: saleRow['cliente_remote_id'] as String?,
      notes: saleRow['observacao'] as String?,
      remoteId: saleRow['sync_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(saleRow['sync_status'] as String?),
      lastSyncedAt: saleRow['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(saleRow['sync_last_synced_at'] as String),
      items: items,
    );
  }

  Future<void> _ensureClientExists(DatabaseExecutor txn, int clientId) async {
    final clientRows = await txn.query(
      TableNames.clientes,
      columns: ['id', 'deletado_em'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (clientRows.isEmpty || clientRows.first['deletado_em'] != null) {
      throw const ValidationException(
        'Cliente selecionado nao esta disponivel.',
      );
    }
  }

  Future<void> _updateClientDebt(
    DatabaseExecutor txn, {
    required int clientId,
    required int deltaCents,
    required String updatedAtIso,
  }) async {
    final clientRows = await txn.query(
      TableNames.clientes,
      columns: ['saldo_devedor_centavos'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (clientRows.isEmpty) {
      throw const ValidationException('Cliente vinculado nao foi encontrado.');
    }

    final currentDebt = clientRows.first['saldo_devedor_centavos'] as int? ?? 0;
    final nextDebt = currentDebt + deltaCents;

    await txn.update(
      TableNames.clientes,
      {
        'saldo_devedor_centavos': nextDebt < 0 ? 0 : nextDebt,
        'atualizado_em': updatedAtIso,
      },
      where: 'id = ?',
      whereArgs: [clientId],
    );
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _mergeCancellationReason(String? existingNotes, String reason) {
    final trimmedExisting = _cleanNullable(existingNotes);
    final cancellationMessage = 'Cancelamento: ${reason.trim()}';
    if (trimmedExisting == null) {
      return cancellationMessage;
    }

    return '$trimmedExisting\n$cancellationMessage';
  }
}

class _ProductSnapshot {
  const _ProductSnapshot({
    required this.productId,
    required this.stockMil,
    required this.costCents,
    required this.unitMeasure,
    required this.productType,
  });

  final int productId;
  final int stockMil;
  final int costCents;
  final String unitMeasure;
  final String productType;
}
