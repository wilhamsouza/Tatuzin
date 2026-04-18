import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../estoque/data/support/inventory_balance_support.dart';
import '../../../../app/core/utils/id_generator.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import 'sale_validation_support.dart';

class SaleItemPersistenceSupport {
  const SaleItemPersistenceSupport._();

  static Future<Map<String, SaleProductSnapshot>> loadProductSnapshots(
    DatabaseExecutor txn,
    List<CartItem> items,
  ) async {
    final snapshots = <String, SaleProductSnapshot>{};
    final reservedQuantityByKey = <String, int>{};

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
      var currentStockMil = row['estoque_mil'] as int? ?? 0;
      if (item.productVariantId != null) {
        final variantRows = await txn.query(
          TableNames.produtoVariantes,
          columns: ['estoque_mil', 'ativo'],
          where: 'id = ? AND produto_id = ?',
          whereArgs: [item.productVariantId, item.productId],
          limit: 1,
        );

        if (variantRows.isEmpty ||
            (variantRows.first['ativo'] as int? ?? 0) != 1) {
          throw ValidationException(
            'Variante indisponivel para venda: ${item.productName}',
          );
        }

        currentStockMil = variantRows.first['estoque_mil'] as int? ?? 0;
      }

      final snapshotKey = _snapshotKey(item);
      final reservedQuantityMil =
          (reservedQuantityByKey[snapshotKey] ?? 0) + item.quantityMil;
      if (currentStockMil < item.quantityMil) {
        throw StockConflictException(
          'Estoque insuficiente para ${_buildItemLabel(item)}. Disponivel: ${currentStockMil ~/ 1000}',
        );
      }
      if (currentStockMil < reservedQuantityMil) {
        throw StockConflictException(
          'Estoque insuficiente para ${_buildItemLabel(item)}. Disponivel: ${currentStockMil ~/ 1000}',
        );
      }

      reservedQuantityByKey[snapshotKey] = reservedQuantityMil;
      snapshots[snapshotKey] = SaleProductSnapshot(
        productId: item.productId,
        productVariantId: item.productVariantId,
        stockMil: currentStockMil,
        costCents: row['custo_centavos'] as int? ?? 0,
        unitMeasure: row['unidade_medida'] as String? ?? item.unitMeasure,
        productType: row['tipo_produto'] as String? ?? item.productType,
      );
    }

    return snapshots;
  }

  static Future<List<InventoryBalanceMutation>> persistItemsAndDecreaseStock(
    DatabaseExecutor txn, {
    required String soldAtIso,
    required int saleId,
    required List<CartItem> items,
    required Map<String, SaleProductSnapshot> snapshots,
  }) async {
    final stockChanges = <InventoryBalanceMutation>[];

    for (final item in items) {
      final snapshot = snapshots[_snapshotKey(item)]!;
      final changedAt = DateTime.parse(soldAtIso);
      final change = await InventoryBalanceSupport.applyStockDelta(
        txn,
        productId: item.productId,
        productVariantId: snapshot.productVariantId,
        quantityDeltaMil: -item.quantityMil,
        allowNegativeStock: false,
        productNotFoundMessage:
            'Produto nao encontrado durante a baixa da venda: ${item.productName}.',
        variantNotFoundMessage:
            'Variante nao encontrada durante a baixa da venda: ${_buildItemLabel(item)}.',
        insufficientProductStockMessage:
            'Estoque insuficiente para ${_buildItemLabel(item)}.',
        insufficientVariantStockMessage:
            'Estoque insuficiente para ${_buildItemLabel(item)}.',
        changedAt: changedAt,
      );
      stockChanges.add(change);

      final quantityUnits = item.quantityMil ~/ 1000;
      final costTotalCents = snapshot.costCents * quantityUnits;

      final itemVendaId = await txn.insert(TableNames.itensVenda, {
        'uuid': IdGenerator.next(),
        'venda_id': saleId,
        'produto_id': item.productId,
        'produto_variante_id': item.productVariantId,
        'nome_produto_snapshot': item.productName,
        'sku_variante_snapshot': SaleValidationSupport.cleanNullable(
          item.variantSku,
        ),
        'cor_variante_snapshot': SaleValidationSupport.cleanNullable(
          item.variantColorLabel,
        ),
        'tamanho_variante_snapshot': SaleValidationSupport.cleanNullable(
          item.variantSizeLabel,
        ),
        'quantidade_mil': item.quantityMil,
        'valor_unitario_centavos': item.unitPriceCents,
        'subtotal_centavos': item.subtotalCents,
        'custo_unitario_centavos': snapshot.costCents,
        'custo_total_centavos': costTotalCents,
        'unidade_medida_snapshot': snapshot.unitMeasure,
        'tipo_produto_snapshot': snapshot.productType,
        'observacao_item_snapshot': SaleValidationSupport.cleanNullable(
          item.notes,
        ),
      });

      await _persistSaleItemModifiers(
        txn,
        itemVendaId: itemVendaId,
        item: item,
        nowIso: soldAtIso,
      );
    }

    return stockChanges;
  }

  static Future<void> _persistSaleItemModifiers(
    DatabaseExecutor txn, {
    required int itemVendaId,
    required CartItem item,
    required String nowIso,
  }) async {
    if (item.modifiers.isEmpty) {
      return;
    }

    for (final modifier in item.modifiers) {
      await txn.insert(TableNames.itensVendaModificadores, {
        'uuid': IdGenerator.next(),
        'item_venda_id': itemVendaId,
        'grupo_modificador_id': modifier.modifierGroupId,
        'opcao_modificador_id': modifier.modifierOptionId,
        'nome_grupo_snapshot': SaleValidationSupport.cleanNullable(
          modifier.groupName,
        ),
        'nome_opcao_snapshot': modifier.optionName.trim(),
        'tipo_ajuste_snapshot': modifier.adjustmentType.trim(),
        'preco_delta_centavos': modifier.priceDeltaCents,
        'quantidade': modifier.quantity,
        'criado_em': nowIso,
        'atualizado_em': nowIso,
      });
    }
  }

  static String _snapshotKey(CartItem item) {
    return '${item.productId}:${item.productVariantId ?? 0}';
  }

  static String _buildItemLabel(CartItem item) {
    final variantParts = <String>[
      if ((item.variantColorLabel ?? '').trim().isNotEmpty)
        item.variantColorLabel!.trim(),
      if ((item.variantSizeLabel ?? '').trim().isNotEmpty)
        item.variantSizeLabel!.trim(),
    ];
    if (variantParts.isEmpty) {
      return item.productName;
    }
    return '${item.productName} (${variantParts.join(' / ')})';
  }
}

class SaleProductSnapshot {
  const SaleProductSnapshot({
    required this.productId,
    required this.productVariantId,
    required this.stockMil,
    required this.costCents,
    required this.unitMeasure,
    required this.productType,
  });

  final int productId;
  final int? productVariantId;
  final int stockMil;
  final int costCents;
  final String unitMeasure;
  final String productType;
}
