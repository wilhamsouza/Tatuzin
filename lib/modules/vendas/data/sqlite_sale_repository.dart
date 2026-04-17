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
import '../../clientes/data/customer_credit_database_support.dart';
import '../../clientes/domain/entities/customer_credit_transaction.dart';
import '../../insumos/data/support/supply_inventory_support.dart';
import '../../insumos/data/support/supply_sync_mutation_support.dart';
import '../domain/entities/checkout_input.dart';
import '../domain/entities/completed_sale.dart';
import '../domain/entities/sale_enums.dart';
import '../domain/repositories/sale_repository.dart';
import 'models/sale_cancellation_sync_payload.dart';
import 'models/sale_sync_payload.dart';
import 'support/sale_cancellation_support.dart';
import 'support/sale_cash_effects_support.dart';
import 'support/sale_item_persistence_support.dart';
import 'support/sale_sync_payload_loader.dart';
import 'support/sale_sync_state_support.dart';
import 'support/sale_validation_support.dart';

class SqliteSaleRepository implements SaleRepository {
  SqliteSaleRepository(this._appDatabase, this._operationalContext)
    : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase) {
    _syncStateSupport = SaleSyncStateSupport(
      syncMetadataRepository: _syncMetadataRepository,
      syncQueueRepository: _syncQueueRepository,
      featureKey: featureKey,
      cashEventFeatureKey: SyncFeatureKeys.cashEvents,
      cancellationFeatureKey: cancellationFeatureKey,
      financialEventFeatureKey: financialEventFeatureKey,
    );
  }

  static const String featureKey = SyncFeatureKeys.sales;
  static const String cancellationFeatureKey =
      SyncFeatureKeys.saleCancellations;
  static const String financialEventFeatureKey =
      SyncFeatureKeys.financialEvents;

  final AppDatabase _appDatabase;
  final AppOperationalContext _operationalContext;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  late final SaleSyncStateSupport _syncStateSupport;

  @override
  Future<CompletedSale> completeCashSale({required CheckoutInput input}) async {
    final database = await _appDatabase.database;

    return database.transaction<CompletedSale>((txn) async {
      return completeCashSaleWithinTransaction(txn, input: input);
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

  Future<CompletedSale> completeCashSaleWithinTransaction(
    DatabaseExecutor txn, {
    required CheckoutInput input,
  }) {
    return _completeSale(txn, input: input, saleType: SaleType.cash);
  }

  Future<void> registerCashEventForSyncWithinTransaction(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) {
    return _registerCashMovementForSync(
      txn,
      movementId: movementId,
      movementUuid: movementUuid,
      createdAt: createdAt,
    );
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
      final affectedSupplyIds =
          await SupplyInventorySupport.reverseSaleConsumption(
            txn,
            saleUuid: saleRow['uuid'] as String,
            saleRemoteId: null,
            occurredAt: now,
          );
      await SupplySyncMutationSupport.markSuppliesForSync(
        txn,
        supplyIds: affectedSupplyIds,
        changedAt: now,
        syncMetadataRepository: _syncMetadataRepository,
        syncQueueRepository: _syncQueueRepository,
      );

      for (final itemRow in soldItems) {
        final productId = itemRow['produto_id'] as int;
        final variantId = itemRow['produto_variante_id'] as int?;
        final quantityMil = itemRow['quantidade_mil'] as int;
        if (variantId != null) {
          final variantRows = await txn.query(
            TableNames.produtoVariantes,
            columns: ['estoque_mil'],
            where: 'id = ?',
            whereArgs: [variantId],
            limit: 1,
          );
          if (variantRows.isNotEmpty) {
            final currentVariantStockMil =
                variantRows.first['estoque_mil'] as int? ?? 0;
            await txn.update(
              TableNames.produtoVariantes,
              {
                'estoque_mil': currentVariantStockMil + quantityMil,
                'atualizado_em': nowIso,
              },
              where: 'id = ?',
              whereArgs: [variantId],
            );

            await txn.rawUpdate(
              '''
              UPDATE ${TableNames.produtos}
              SET estoque_mil = COALESCE((
                SELECT SUM(CASE WHEN ativo = 1 THEN estoque_mil ELSE 0 END)
                FROM ${TableNames.produtoVariantes}
                WHERE produto_id = ?
              ), 0),
              atualizado_em = ?
              WHERE id = ?
              ''',
              [productId, nowIso, productId],
            );
          }
          continue;
        }

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
      final creditUsedCents = saleRow['haver_utilizado_centavos'] as int? ?? 0;
      final creditGeneratedCents =
          saleRow['haver_gerado_centavos'] as int? ?? 0;
      final immediateReceivedCents =
          saleRow['valor_recebido_imediato_centavos'] as int? ?? finalCents;
      final receiptNumber = saleRow['numero_cupom'] as String;
      final clientId = saleRow['cliente_id'] as int?;

      if (saleType == SaleType.cash) {
        if (immediateReceivedCents > 0) {
          final cashMovement =
              await SaleCashEffectsSupport.registerSaleCancellation(
                txn,
                timestamp: now,
                userId: _operationalContext.currentLocalUserId,
                saleId: saleId,
                amountCents: immediateReceivedCents,
                receiptNumber: receiptNumber,
                reason: reason,
                paymentMethod: paymentMethod,
              );
          await _registerCashMovementForSync(
            txn,
            movementId: cashMovement.id,
            movementUuid: cashMovement.uuid,
            createdAt: now,
          );
        }
        if (clientId != null && creditUsedCents > 0) {
          await _reverseOrCompensateCreditUsage(
            txn,
            saleId: saleId,
            customerId: clientId,
            fallbackAmountCents: creditUsedCents,
            description:
                'Estorno do haver usado na venda $receiptNumber cancelada.',
          );
        }
        if (clientId != null && creditGeneratedCents > 0) {
          await _reverseCreditGeneration(
            txn,
            saleId: saleId,
            description:
                'Reversao do haver gerado na venda $receiptNumber cancelada.',
          );
        }
      } else {
        final fiadoId = saleRow['fiado_id'] as int?;
        final fiadoOriginalCents =
            saleRow['fiado_valor_original_centavos'] as int? ?? 0;
        final fiadoOpenCents =
            saleRow['fiado_valor_aberto_centavos'] as int? ?? 0;
        final totalPaidCents = fiadoOriginalCents - fiadoOpenCents;
        int? cashMovementId;

        if (totalPaidCents > 0) {
          final cashMovement =
              await SaleCashEffectsSupport.registerFiadoReceiptRefund(
                txn,
                timestamp: now,
                userId: _operationalContext.currentLocalUserId,
                fiadoId: fiadoId,
                amountCents: totalPaidCents,
                receiptNumber: receiptNumber,
                reason: reason,
              );
          cashMovementId = cashMovement.id;
          await _registerCashMovementForSync(
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
            'observacao': SaleCancellationSupport.buildCancellationMessage(
              receiptNumber: receiptNumber,
              reason: reason,
            ),
            'caixa_movimento_id': cashMovementId,
          });
        }
      }

      await SaleCancellationSupport.persistSaleCancellation(
        txn,
        saleId: saleId,
        nowIso: nowIso,
        existingNotes: saleRow['observacao'] as String?,
        reason: reason,
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

      await _syncStateSupport.registerCancellationForSync(
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
    final creditUsedCents = input.customerCreditUsedCents;
    final creditGeneratedCents = input.changeLeftAsCreditCents;
    final immediateReceivedCents = input.immediateReceivedCents;
    final saleUuid = IdGenerator.next();

    SaleValidationSupport.validateCompletionInput(
      input: input,
      saleType: saleType,
    );

    if (input.clientId != null) {
      await SaleValidationSupport.ensureClientExists(txn, input.clientId!);
    }

    if (input.operationalOrderId != null) {
      await SaleValidationSupport.ensureOperationalOrderCanBeConverted(
        txn,
        orderId: input.operationalOrderId!,
      );
    }

    final productSnapshots =
        await SaleItemPersistenceSupport.loadProductSnapshots(txn, input.items);
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
      'haver_utilizado_centavos': creditUsedCents,
      'haver_gerado_centavos': creditGeneratedCents,
      'valor_recebido_imediato_centavos': immediateReceivedCents,
      'numero_cupom': receiptNumber,
      'data_venda': nowIso,
      'usuario_id': _operationalContext.currentLocalUserId,
      'observacao': SaleValidationSupport.cleanNullable(input.notes),
      'cancelada_em': null,
      'venda_origem_id': null,
    });

    await SaleItemPersistenceSupport.persistItemsAndDecreaseStock(
      txn,
      soldAtIso: nowIso,
      saleId: saleId,
      items: input.items,
      snapshots: productSnapshots,
    );
    final supplyConsumption =
        await SupplyInventorySupport.recordSaleConsumption(
          txn,
          saleUuid: saleUuid,
          items: input.items,
          occurredAt: now,
        );
    await SupplySyncMutationSupport.markSuppliesForSync(
      txn,
      supplyIds: supplyConsumption.affectedSupplyIds,
      changedAt: now,
      syncMetadataRepository: _syncMetadataRepository,
      syncQueueRepository: _syncQueueRepository,
    );

    int? fiadoId;
    if (saleType == SaleType.cash) {
      if (creditUsedCents > 0) {
        await CustomerCreditDatabaseSupport.applyCreditToSale(
          txn,
          customerId: input.clientId!,
          saleId: saleId,
          amountCents: creditUsedCents,
          description: 'Haver usado na venda $receiptNumber.',
        );
      }

      if (immediateReceivedCents > 0) {
        final cashMovement =
            await SaleCashEffectsSupport.registerCashSaleReceipt(
              txn,
              timestamp: now,
              userId: _operationalContext.currentLocalUserId,
              saleId: saleId,
              amountCents: immediateReceivedCents,
              receiptNumber: receiptNumber,
              paymentMethod: input.paymentMethod,
            );
        await _registerCashMovementForSync(
          txn,
          movementId: cashMovement.id,
          movementUuid: cashMovement.uuid,
          createdAt: now,
        );
      }

      if (creditGeneratedCents > 0) {
        await CustomerCreditDatabaseSupport.createCreditFromOverpayment(
          txn,
          customerId: input.clientId!,
          amountCents: creditGeneratedCents,
          saleId: saleId,
          description:
              'Troco da venda $receiptNumber mantido como haver do cliente.',
          type: CustomerCreditTransactionType.changeLeftAsCredit,
        );
      }
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

    await _syncStateSupport.registerSaleForSync(
      txn,
      saleId: saleId,
      saleUuid: saleUuid,
      createdAt: now,
    );

    if (input.operationalOrderId != null) {
      await _linkOperationalOrderToSale(
        txn,
        orderId: input.operationalOrderId!,
        saleId: saleId,
        linkedAtIso: nowIso,
      );
    }

    return CompletedSale(
      saleId: saleId,
      receiptNumber: receiptNumber,
      totalCents: finalCents,
      itemsCount: input.items.length,
      soldAt: now,
      saleType: saleType,
      paymentMethod: input.paymentMethod,
      supplyConsumption: supplyConsumption,
      clientId: input.clientId,
      fiadoId: fiadoId,
    );
  }

  Future<void> _linkOperationalOrderToSale(
    DatabaseExecutor txn, {
    required int orderId,
    required int saleId,
    required String linkedAtIso,
  }) async {
    try {
      await txn.insert(
        TableNames.vendasPedidosOperacionais,
        {
          'uuid': IdGenerator.next(),
          'venda_id': saleId,
          'pedido_operacional_id': orderId,
          'criado_em': linkedAtIso,
          'atualizado_em': linkedAtIso,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (_) {
      throw ValidationException(
        'Pedido operacional #$orderId ja foi convertido em venda.',
      );
    }

    await txn.update(
      TableNames.pedidosOperacionais,
      {
        'status': 'delivered',
        'atualizado_em': linkedAtIso,
        'fechado_em': linkedAtIso,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<SaleSyncPayload?> findSaleForSync(int saleId) async {
    final database = await _appDatabase.database;
    return SaleSyncPayloadLoader.loadSale(
      database,
      saleId: saleId,
      featureKey: featureKey,
    );
  }

  Future<SaleCancellationSyncPayload?> findSaleCancellationForSync(
    int saleId,
  ) async {
    final database = await _appDatabase.database;
    return SaleSyncPayloadLoader.loadCancellation(
      database,
      saleId: saleId,
      featureKey: featureKey,
      cancellationFeatureKey: cancellationFeatureKey,
    );
  }

  Future<void> markSynced({
    required SaleSyncPayload sale,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncStateSupport.markSynced(
        txn,
        sale: sale,
        remoteId: remoteId,
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
      await _syncStateSupport.markSyncError(
        txn,
        sale: sale,
        message: message,
        errorType: errorType,
        updatedAt: now,
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
      await _syncStateSupport.markConflict(
        txn,
        sale: sale,
        message: message,
        detectedAt: detectedAt,
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
      await _syncStateSupport.markCancellationSynced(
        txn,
        sale: sale,
        remoteId: remoteId,
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
      await _syncStateSupport.markCancellationConflict(
        txn,
        sale: sale,
        message: message,
        detectedAt: detectedAt,
      );
    });
  }

  Future<void> _registerCashMovementForSync(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {
    await _syncStateSupport.registerCashEventForSync(
      txn,
      movementId: movementId,
      movementUuid: movementUuid,
      createdAt: createdAt,
    );
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

  Future<void> _reverseOrCompensateCreditUsage(
    DatabaseExecutor txn, {
    required int saleId,
    required int customerId,
    required int fallbackAmountCents,
    required String description,
  }) async {
    final rows = await txn.query(
      TableNames.customerCreditTransactions,
      columns: ['id'],
      where: 'sale_id = ? AND type = ?',
      whereArgs: [saleId, CustomerCreditTransactionType.creditUsedInSale],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await CustomerCreditDatabaseSupport.reverseCreditTransaction(
        txn,
        transactionId: rows.first['id'] as int,
        description: description,
      );
      return;
    }

    await CustomerCreditDatabaseSupport.createCreditFromSaleCancel(
      txn,
      customerId: customerId,
      saleId: saleId,
      amountCents: fallbackAmountCents,
      description: description,
    );
  }

  Future<void> _reverseCreditGeneration(
    DatabaseExecutor txn, {
    required int saleId,
    required String description,
  }) async {
    final rows = await txn.query(
      TableNames.customerCreditTransactions,
      columns: ['id'],
      where: 'sale_id = ? AND type = ?',
      whereArgs: [saleId, CustomerCreditTransactionType.changeLeftAsCredit],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }

    await CustomerCreditDatabaseSupport.reverseCreditTransaction(
      txn,
      transactionId: rows.first['id'] as int,
      description: description,
    );
  }
}
