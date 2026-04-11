import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
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

      if (currentStockMil < item.quantityMil) {
        throw StockConflictException(
          'Estoque insuficiente para ${item.productName}. Disponivel: ${currentStockMil ~/ 1000}',
        );
      }

      snapshots[_snapshotKey(item)] = SaleProductSnapshot(
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

  static Future<void> persistItemsAndDecreaseStock(
    DatabaseExecutor txn, {
    required String soldAtIso,
    required int saleId,
    required List<CartItem> items,
    required Map<String, SaleProductSnapshot> snapshots,
  }) async {
    for (final item in items) {
      final snapshot = snapshots[_snapshotKey(item)]!;
      final newStockMil = snapshot.stockMil - item.quantityMil;

      if (snapshot.productVariantId != null) {
        await txn.update(
          TableNames.produtoVariantes,
          {'estoque_mil': newStockMil, 'atualizado_em': soldAtIso},
          where: 'id = ?',
          whereArgs: [snapshot.productVariantId],
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
          [item.productId, soldAtIso, item.productId],
        );
      } else {
        await txn.update(
          TableNames.produtos,
          {'estoque_mil': newStockMil, 'atualizado_em': soldAtIso},
          where: 'id = ?',
          whereArgs: [item.productId],
        );
      }

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
