import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../carrinho/domain/entities/cart_item.dart';
import '../../clientes/data/customer_credit_database_support.dart';
import '../../estoque/data/support/inventory_balance_support.dart';
import '../../estoque/data/support/inventory_movement_writer.dart';
import '../../estoque/domain/entities/inventory_movement.dart';
import '../../vendas/data/sqlite_sale_repository.dart';
import '../../vendas/data/support/sale_cash_effects_support.dart';
import '../../vendas/domain/entities/checkout_input.dart';
import '../../vendas/domain/entities/completed_sale.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/sale_return.dart';

class SqliteSaleReturnRepository {
  SqliteSaleReturnRepository(
    AppDatabase appDatabase,
    this._operationalContext,
    this._saleRepository,
  ) : _databaseLoader = (() => appDatabase.database);

  SqliteSaleReturnRepository.forDatabase({
    required Future<Database> Function() databaseLoader,
    required AppOperationalContext operationalContext,
    required SqliteSaleRepository saleRepository,
  }) : _databaseLoader = databaseLoader,
       _operationalContext = operationalContext,
       _saleRepository = saleRepository;

  final Future<Database> Function() _databaseLoader;
  final AppOperationalContext _operationalContext;
  final SqliteSaleRepository _saleRepository;

  Future<List<SaleReturnRecord>> listForSale(int saleId) async {
    final database = await _databaseLoader();
    final returnRows = await database.rawQuery(
      '''
      SELECT
        sr.*,
        rv.numero_cupom AS replacement_receipt_number
      FROM ${TableNames.saleReturns} sr
      LEFT JOIN ${TableNames.vendas} rv ON rv.id = sr.replacement_sale_id
      WHERE sr.sale_id = ?
      ORDER BY sr.created_at DESC, sr.id DESC
    ''',
      [saleId],
    );

    if (returnRows.isEmpty) {
      return const <SaleReturnRecord>[];
    }

    final ids = returnRows
        .map((row) => row['id'] as int)
        .toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');
    final itemRows = await database.query(
      TableNames.saleReturnItems,
      where: 'sale_return_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'id ASC',
    );

    final itemsByReturnId = <int, List<SaleReturnItemRecord>>{};
    for (final row in itemRows) {
      final item = SaleReturnItemRecord(
        id: row['id'] as int,
        saleReturnId: row['sale_return_id'] as int,
        saleItemId: row['sale_item_id'] as int,
        productId: row['product_id'] as int,
        productVariantId: row['product_variant_id'] as int?,
        productName: row['product_name_snapshot'] as String? ?? 'Produto',
        variantSkuSnapshot: row['variant_sku_snapshot'] as String?,
        variantColorSnapshot: row['variant_color_snapshot'] as String?,
        variantSizeSnapshot: row['variant_size_snapshot'] as String?,
        quantityMil: row['quantity_mil'] as int? ?? 0,
        unitPriceCents: row['unit_price_cents'] as int? ?? 0,
        subtotalCents: row['subtotal_cents'] as int? ?? 0,
        reason: row['reason'] as String?,
      );
      itemsByReturnId
          .putIfAbsent(item.saleReturnId, () => <SaleReturnItemRecord>[])
          .add(item);
    }

    return returnRows
        .map(
          (row) => SaleReturnRecord(
            id: row['id'] as int,
            uuid: row['uuid'] as String,
            saleId: row['sale_id'] as int,
            clientId: row['client_id'] as int?,
            mode: saleReturnModeFromStorage(row['exchange_mode'] as String),
            reason: row['reason'] as String?,
            refundAmountCents: row['refund_amount_cents'] as int? ?? 0,
            creditedAmountCents: row['credited_amount_cents'] as int? ?? 0,
            appliedDiscountCents: row['applied_discount_cents'] as int? ?? 0,
            replacementSaleId: row['replacement_sale_id'] as int?,
            replacementSaleReceiptNumber:
                row['replacement_receipt_number'] as String?,
            createdAt: DateTime.parse(row['created_at'] as String),
            items:
                itemsByReturnId[row['id'] as int] ??
                const <SaleReturnItemRecord>[],
          ),
        )
        .toList(growable: false);
  }

  Future<SaleReturnResult> registerReturn(SaleReturnInput input) async {
    final database = await _databaseLoader();
    return database.transaction((txn) async {
      final saleRows = await txn.query(
        TableNames.vendas,
        columns: [
          'id',
          'uuid',
          'cliente_id',
          'status',
          'forma_pagamento',
          'numero_cupom',
        ],
        where: 'id = ?',
        whereArgs: [input.saleId],
        limit: 1,
      );
      if (saleRows.isEmpty) {
        throw const ValidationException('Venda nao encontrada para troca.');
      }

      final saleRow = saleRows.first;
      if ((saleRow['status'] as String?) == SaleStatus.cancelled.dbValue) {
        throw const ValidationException(
          'Nao e possivel registrar troca em venda cancelada.',
        );
      }

      final normalizedReturnedItems = _normalizeReturnedItems(
        input.returnedItems,
      );
      if (normalizedReturnedItems.isEmpty) {
        throw const ValidationException(
          'Selecione ao menos um item devolvido para continuar.',
        );
      }
      if (input.mode == SaleReturnMode.exchangeWithNewSale &&
          input.replacementItems.isEmpty) {
        throw const ValidationException(
          'Selecione o novo item para concluir a troca.',
        );
      }
      if (input.mode == SaleReturnMode.returnOnly &&
          input.replacementItems.isNotEmpty) {
        throw const ValidationException(
          'Nao misture devolucao simples com nova venda no mesmo fluxo.',
        );
      }

      final itemIds = normalizedReturnedItems
          .map((item) => item.saleItemId)
          .toList(growable: false);
      final placeholders = List.filled(itemIds.length, '?').join(',');
      final saleItemRows = await txn.query(
        TableNames.itensVenda,
        where: 'venda_id = ? AND id IN ($placeholders)',
        whereArgs: [input.saleId, ...itemIds],
      );
      if (saleItemRows.length != itemIds.length) {
        throw const ValidationException(
          'Um dos itens selecionados nao pertence mais a essa venda.',
        );
      }

      final saleItemsById = <int, Map<String, Object?>>{
        for (final row in saleItemRows) row['id'] as int: row,
      };
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final receiptNumber = saleRow['numero_cupom'] as String? ?? '';
      final clientId = saleRow['cliente_id'] as int?;
      final cleanedReason = _cleanNullable(input.reason);
      final resolvedItems = <_ResolvedSaleReturnItem>[];
      final returnChanges = <InventoryBalanceMutation>[];
      var totalReturnedCents = 0;

      _validateReplacementItems(input.replacementItems);

      final saleReturnId = await txn.insert(TableNames.saleReturns, {
        'uuid': IdGenerator.next(),
        'sale_id': input.saleId,
        'client_id': clientId,
        'exchange_mode': input.mode.storageValue,
        'reason': cleanedReason,
        'refund_amount_cents': 0,
        'credited_amount_cents': 0,
        'applied_discount_cents': 0,
        'replacement_sale_id': null,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      for (final returnedItem in normalizedReturnedItems) {
        final itemRow = saleItemsById[returnedItem.saleItemId];
        if (itemRow == null) {
          throw const ValidationException(
            'Um dos itens devolvidos nao foi localizado na venda.',
          );
        }

        final variantId = itemRow['produto_variante_id'] as int?;

        final quantityMil = returnedItem.quantityMil;
        if (quantityMil <= 0 || quantityMil % 1000 != 0) {
          throw const ValidationException(
            'A quantidade devolvida precisa ser um numero inteiro de pecas.',
          );
        }

        final soldQuantityMil = itemRow['quantidade_mil'] as int? ?? 0;
        final alreadyReturnedMil = await _loadReturnedQuantityMil(
          txn,
          saleItemId: returnedItem.saleItemId,
        );
        final remainingMil = soldQuantityMil - alreadyReturnedMil;
        if (remainingMil <= 0 || quantityMil > remainingMil) {
          throw const ValidationException(
            'A quantidade devolvida excede o saldo disponivel desse item.',
          );
        }

        final itemLabel = _buildSaleItemLabel(itemRow);
        final change = await InventoryBalanceSupport.applyStockDelta(
          txn,
          productId: itemRow['produto_id'] as int,
          productVariantId: variantId,
          quantityDeltaMil: quantityMil,
          allowNegativeStock: false,
          productNotFoundMessage:
              'Produto original nao foi encontrado para recompor o estoque: $itemLabel.',
          variantNotFoundMessage:
              'Variante original nao foi encontrada para recompor o estoque: $itemLabel.',
          insufficientProductStockMessage:
              'Nao foi possivel recompor o estoque de $itemLabel.',
          insufficientVariantStockMessage:
              'Nao foi possivel recompor o estoque de $itemLabel.',
          changedAt: now,
        );
        returnChanges.add(change);

        final subtotalCents = _calculateReturnedSubtotal(
          itemRow,
          quantityMil: quantityMil,
        );
        totalReturnedCents += subtotalCents;
        resolvedItems.add(
          _ResolvedSaleReturnItem(
            saleItemId: returnedItem.saleItemId,
            productId: itemRow['produto_id'] as int,
            productVariantId: variantId,
            productName:
                itemRow['nome_produto_snapshot'] as String? ?? 'Produto',
            variantSkuSnapshot: itemRow['sku_variante_snapshot'] as String?,
            variantColorSnapshot: itemRow['cor_variante_snapshot'] as String?,
            variantSizeSnapshot:
                itemRow['tamanho_variante_snapshot'] as String?,
            quantityMil: quantityMil,
            unitPriceCents: itemRow['valor_unitario_centavos'] as int? ?? 0,
            subtotalCents: subtotalCents,
            reason: _cleanNullable(returnedItem.reason) ?? cleanedReason,
          ),
        );
      }

      await InventoryMovementWriter.writeReturnIn(
        txn,
        changes: returnChanges,
        referenceId: saleReturnId,
        notes: cleanedReason,
        createdAt: now,
      );

      var refundAmountCents = 0;
      var creditedAmountCents = 0;
      var appliedDiscountCents = 0;
      CompletedSale? replacementSale;

      if (input.mode == SaleReturnMode.exchangeWithNewSale) {
        final replacementTotalCents = input.replacementItems.fold<int>(
          0,
          (total, item) => total + item.subtotalCents,
        );
        appliedDiscountCents = math.min(
          totalReturnedCents,
          replacementTotalCents,
        );
        final leftoverCents = totalReturnedCents - appliedDiscountCents;

        if (leftoverCents > 0) {
          if (clientId != null) {
            await CustomerCreditDatabaseSupport.createCreditFromSaleReturn(
              txn,
              customerId: clientId,
              saleId: input.saleId,
              amountCents: leftoverCents,
              description:
                  'Saldo restante da troca da venda $receiptNumber mantido como haver.',
            );
            creditedAmountCents = leftoverCents;
          } else {
            refundAmountCents = leftoverCents;
            await _registerRefundMovement(
              txn,
              saleId: input.saleId,
              amountCents: refundAmountCents,
              receiptNumber: receiptNumber,
              reason:
                  cleanedReason ?? 'Troca com diferenca devolvida ao cliente.',
              paymentMethod: _paymentMethodFromStorage(
                saleRow['forma_pagamento'] as String?,
              ),
              timestamp: now,
            );
          }
        }

        replacementSale = await _saleRepository
            .completeCashSaleWithinTransaction(
              txn,
              input: CheckoutInput(
                items: input.replacementItems,
                saleType: SaleType.cash,
                paymentMethod: input.replacementPaymentMethod,
                clientId: clientId,
                notes: _buildReplacementSaleNote(
                  receiptNumber: receiptNumber,
                  reason: input.reason,
                ),
                discountCents: appliedDiscountCents,
              ),
              inventoryMovementType: InventoryMovementType.exchangeOut,
              inventoryReferenceType: 'sale_return',
              inventoryReferenceId: saleReturnId,
              inventoryNotes: _buildReplacementSaleNote(
                receiptNumber: receiptNumber,
                reason: input.reason,
              ),
            );
        await txn.update(
          TableNames.vendas,
          {'venda_origem_id': input.saleId},
          where: 'id = ?',
          whereArgs: [replacementSale.saleId],
        );
      } else {
        if (clientId != null) {
          await CustomerCreditDatabaseSupport.createCreditFromSaleReturn(
            txn,
            customerId: clientId,
            saleId: input.saleId,
            amountCents: totalReturnedCents,
            description:
                'Devolucao da venda $receiptNumber convertida em haver.',
          );
          creditedAmountCents = totalReturnedCents;
        } else {
          refundAmountCents = totalReturnedCents;
          await _registerRefundMovement(
            txn,
            saleId: input.saleId,
            amountCents: refundAmountCents,
            receiptNumber: receiptNumber,
            reason: cleanedReason ?? 'Devolucao simples da venda.',
            paymentMethod: _paymentMethodFromStorage(
              saleRow['forma_pagamento'] as String?,
            ),
            timestamp: now,
          );
        }
      }

      await txn.update(
        TableNames.saleReturns,
        {
          'refund_amount_cents': refundAmountCents,
          'credited_amount_cents': creditedAmountCents,
          'applied_discount_cents': appliedDiscountCents,
          'replacement_sale_id': replacementSale?.saleId,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [saleReturnId],
      );

      for (final item in resolvedItems) {
        await txn.insert(TableNames.saleReturnItems, {
          'uuid': IdGenerator.next(),
          'sale_return_id': saleReturnId,
          'sale_item_id': item.saleItemId,
          'product_id': item.productId,
          'product_variant_id': item.productVariantId,
          'product_name_snapshot': item.productName,
          'variant_sku_snapshot': item.variantSkuSnapshot,
          'variant_color_snapshot': item.variantColorSnapshot,
          'variant_size_snapshot': item.variantSizeSnapshot,
          'quantity_mil': item.quantityMil,
          'unit_price_cents': item.unitPriceCents,
          'subtotal_cents': item.subtotalCents,
          'reason': item.reason,
          'created_at': nowIso,
        });
      }

      return SaleReturnResult(
        saleReturnId: saleReturnId,
        mode: input.mode,
        refundAmountCents: refundAmountCents,
        creditedAmountCents: creditedAmountCents,
        appliedDiscountCents: appliedDiscountCents,
        replacementSaleId: replacementSale?.saleId,
        replacementReceiptNumber: replacementSale?.receiptNumber,
      );
    });
  }

  List<SaleReturnItemInput> _normalizeReturnedItems(
    List<SaleReturnItemInput> items,
  ) {
    final aggregated = <int, SaleReturnItemInput>{};
    for (final item in items) {
      final existing = aggregated[item.saleItemId];
      if (existing == null) {
        aggregated[item.saleItemId] = item;
        continue;
      }

      aggregated[item.saleItemId] = SaleReturnItemInput(
        saleItemId: item.saleItemId,
        quantityMil: existing.quantityMil + item.quantityMil,
        reason: _cleanNullable(existing.reason) ?? _cleanNullable(item.reason),
      );
    }

    return aggregated.values.toList(growable: false);
  }

  Future<int> _loadReturnedQuantityMil(
    DatabaseExecutor txn, {
    required int saleItemId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(sri.quantity_mil), 0) AS total
      FROM ${TableNames.saleReturnItems} sri
      INNER JOIN ${TableNames.saleReturns} sr ON sr.id = sri.sale_return_id
      WHERE sri.sale_item_id = ?
    ''',
      [saleItemId],
    );
    return rows.first['total'] as int? ?? 0;
  }

  String _buildSaleItemLabel(Map<String, Object?> itemRow) {
    final productName =
        (itemRow['nome_produto_snapshot'] as String?)?.trim().isNotEmpty == true
        ? (itemRow['nome_produto_snapshot'] as String).trim()
        : 'Produto';
    final variantParts = <String>[
      if ((itemRow['cor_variante_snapshot'] as String?)?.trim().isNotEmpty ==
          true)
        (itemRow['cor_variante_snapshot'] as String).trim(),
      if ((itemRow['tamanho_variante_snapshot'] as String?)
              ?.trim()
              .isNotEmpty ==
          true)
        (itemRow['tamanho_variante_snapshot'] as String).trim(),
    ];
    if (variantParts.isEmpty) {
      return productName;
    }
    return '$productName (${variantParts.join(' / ')})';
  }

  int _calculateReturnedSubtotal(
    Map<String, Object?> row, {
    required int quantityMil,
  }) {
    final soldQuantityMil = row['quantidade_mil'] as int? ?? 0;
    final subtotalCents = row['subtotal_centavos'] as int? ?? 0;
    if (quantityMil == soldQuantityMil) {
      return subtotalCents;
    }

    final unitPriceCents = row['valor_unitario_centavos'] as int? ?? 0;
    return ((quantityMil * unitPriceCents) / 1000).round();
  }

  void _validateReplacementItems(List<CartItem> replacementItems) {
    for (final item in replacementItems) {
      if (item.quantityMil <= 0 || item.quantityMil % 1000 != 0) {
        throw const ValidationException(
          'A nova peca da troca precisa usar quantidade inteira em pecas.',
        );
      }
    }
  }

  Future<void> _registerRefundMovement(
    DatabaseExecutor txn, {
    required int saleId,
    required int amountCents,
    required String receiptNumber,
    required String reason,
    required PaymentMethod paymentMethod,
    required DateTime timestamp,
  }) async {
    if (amountCents <= 0) {
      return;
    }

    final movement = await SaleCashEffectsSupport.registerSaleReturnRefund(
      txn,
      timestamp: timestamp,
      userId: _operationalContext.currentLocalUserId,
      saleId: saleId,
      amountCents: amountCents,
      receiptNumber: receiptNumber,
      reason: reason,
      paymentMethod: paymentMethod,
    );
    await _saleRepository.registerCashEventForSyncWithinTransaction(
      txn,
      movementId: movement.id,
      movementUuid: movement.uuid,
      createdAt: timestamp,
    );
  }

  PaymentMethod _paymentMethodFromStorage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return PaymentMethod.cash;
    }
    return PaymentMethodX.fromDb(value);
  }

  String _buildReplacementSaleNote({
    required String receiptNumber,
    required String? reason,
  }) {
    final base = 'Troca vinculada a venda $receiptNumber.';
    final cleanedReason = _cleanNullable(reason);
    if (cleanedReason == null) {
      return base;
    }
    return '$base Motivo: $cleanedReason';
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _ResolvedSaleReturnItem {
  const _ResolvedSaleReturnItem({
    required this.saleItemId,
    required this.productId,
    required this.productVariantId,
    required this.productName,
    required this.variantSkuSnapshot,
    required this.variantColorSnapshot,
    required this.variantSizeSnapshot,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.reason,
  });

  final int saleItemId;
  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantSkuSnapshot;
  final String? variantColorSnapshot;
  final String? variantSizeSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int subtotalCents;
  final String? reason;
}
