import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../domain/entities/purchase_item.dart';

class PurchaseStockSupport {
  const PurchaseStockSupport._();

  static Future<void> applyStockEntries(
    DatabaseExecutor db,
    List<PurchaseItem> items, {
    required int factor,
  }) async {
    final quantitiesByProduct = _groupQuantitiesByProduct(
      items,
      factor: factor,
    );

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

  static Future<void> validateStockReversal(
    DatabaseExecutor db,
    List<PurchaseItem> items,
  ) async {
    final quantitiesByProduct = _groupQuantitiesByProduct(items);

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

  static Map<int, int> _groupQuantitiesByProduct(
    List<PurchaseItem> items, {
    int factor = 1,
  }) {
    final quantitiesByProduct = <int, int>{};
    for (final item in items) {
      quantitiesByProduct.update(
        item.productId,
        (current) => current + (item.quantityMil * factor),
        ifAbsent: () => item.quantityMil * factor,
      );
    }
    return quantitiesByProduct;
  }
}
