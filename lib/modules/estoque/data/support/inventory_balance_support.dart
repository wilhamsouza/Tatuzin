import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';

class InventoryBalanceMutation {
  const InventoryBalanceMutation({
    required this.productId,
    required this.productVariantId,
    required this.quantityDeltaMil,
    required this.stockBeforeMil,
    required this.stockAfterMil,
  });

  final int productId;
  final int? productVariantId;
  final int quantityDeltaMil;
  final int stockBeforeMil;
  final int stockAfterMil;
}

abstract final class InventoryBalanceSupport {
  static Future<InventoryBalanceMutation> previewStockDelta(
    DatabaseExecutor db, {
    required int productId,
    required int? productVariantId,
    required int quantityDeltaMil,
    required bool allowNegativeStock,
    required String productNotFoundMessage,
    required String variantNotFoundMessage,
    required String insufficientProductStockMessage,
    required String insufficientVariantStockMessage,
  }) async {
    if (productVariantId != null) {
      final variantRows = await db.query(
        TableNames.produtoVariantes,
        columns: const ['produto_id', 'estoque_mil'],
        where: 'id = ?',
        whereArgs: [productVariantId],
        limit: 1,
      );
      if (variantRows.isEmpty) {
        throw ValidationException(variantNotFoundMessage);
      }

      final resolvedProductId =
          variantRows.first['produto_id'] as int? ?? productId;
      final currentStockMil = variantRows.first['estoque_mil'] as int? ?? 0;
      final nextStockMil = currentStockMil + quantityDeltaMil;
      if (!allowNegativeStock && nextStockMil < 0) {
        throw ValidationException(insufficientVariantStockMessage);
      }

      return InventoryBalanceMutation(
        productId: resolvedProductId,
        productVariantId: productVariantId,
        quantityDeltaMil: quantityDeltaMil,
        stockBeforeMil: currentStockMil,
        stockAfterMil: nextStockMil,
      );
    }

    final productRows = await db.query(
      TableNames.produtos,
      columns: const ['estoque_mil'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (productRows.isEmpty) {
      throw ValidationException(productNotFoundMessage);
    }

    final currentStockMil = productRows.first['estoque_mil'] as int? ?? 0;
    final nextStockMil = currentStockMil + quantityDeltaMil;
    if (!allowNegativeStock && nextStockMil < 0) {
      throw ValidationException(insufficientProductStockMessage);
    }

    return InventoryBalanceMutation(
      productId: productId,
      productVariantId: null,
      quantityDeltaMil: quantityDeltaMil,
      stockBeforeMil: currentStockMil,
      stockAfterMil: nextStockMil,
    );
  }

  static Future<InventoryBalanceMutation> applyStockDelta(
    DatabaseExecutor db, {
    required int productId,
    required int? productVariantId,
    required int quantityDeltaMil,
    required bool allowNegativeStock,
    required String productNotFoundMessage,
    required String variantNotFoundMessage,
    required String insufficientProductStockMessage,
    required String insufficientVariantStockMessage,
    DateTime? changedAt,
  }) async {
    final changedAtIso = (changedAt ?? DateTime.now()).toIso8601String();

    final preview = await previewStockDelta(
      db,
      productId: productId,
      productVariantId: productVariantId,
      quantityDeltaMil: quantityDeltaMil,
      allowNegativeStock: allowNegativeStock,
      productNotFoundMessage: productNotFoundMessage,
      variantNotFoundMessage: variantNotFoundMessage,
      insufficientProductStockMessage: insufficientProductStockMessage,
      insufficientVariantStockMessage: insufficientVariantStockMessage,
    );

    if (productVariantId != null) {
      await db.update(
        TableNames.produtoVariantes,
        {'estoque_mil': preview.stockAfterMil, 'atualizado_em': changedAtIso},
        where: 'id = ?',
        whereArgs: [productVariantId],
      );

      await rebuildParentProductStock(
        db,
        productId: preview.productId,
        changedAt: changedAt ?? DateTime.now(),
      );

      return preview;
    }

    await db.update(
      TableNames.produtos,
      {'estoque_mil': preview.stockAfterMil, 'atualizado_em': changedAtIso},
      where: 'id = ?',
      whereArgs: [productId],
    );

    return preview;
  }

  static Future<void> rebuildParentProductStock(
    DatabaseExecutor db, {
    required int productId,
    DateTime? changedAt,
  }) async {
    await db.rawUpdate(
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
      [productId, (changedAt ?? DateTime.now()).toIso8601String(), productId],
    );
  }
}
