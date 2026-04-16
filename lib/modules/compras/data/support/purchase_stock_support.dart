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
    final productEntries = _groupProductEntries(items, factor: factor);
    final touchedProductIds = <int>{};

    for (final entry in productEntries) {
      if (entry.productVariantId != null) {
        final variantRows = await db.query(
          TableNames.produtoVariantes,
          columns: ['estoque_mil', 'produto_id'],
          where: 'id = ?',
          whereArgs: [entry.productVariantId],
          limit: 1,
        );
        if (variantRows.isEmpty) {
          throw const ValidationException(
            'Nao foi possivel atualizar o estoque de uma das variacoes compradas.',
          );
        }

        final currentVariantStock = variantRows.first['estoque_mil'] as int? ?? 0;
        final nextVariantStock = currentVariantStock + entry.quantityMil;
        if (nextVariantStock < 0) {
          throw const ValidationException(
            'Nao ha estoque suficiente na variante para reverter esta compra.',
          );
        }

        final productId = variantRows.first['produto_id'] as int? ?? entry.productId;
        touchedProductIds.add(productId);
        await db.update(
          TableNames.produtoVariantes,
          {
            'estoque_mil': nextVariantStock,
            'atualizado_em': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [entry.productVariantId],
        );
        continue;
      }

      final productRows = await db.query(
        TableNames.produtos,
        columns: ['estoque_mil'],
        where: 'id = ?',
        whereArgs: [entry.productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw const ValidationException(
          'Nao foi possivel atualizar o estoque de um dos produtos.',
        );
      }

      final currentStock = productRows.first['estoque_mil'] as int? ?? 0;
      final nextStock = currentStock + entry.quantityMil;
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
        whereArgs: [entry.productId],
      );
    }

    for (final productId in touchedProductIds) {
      await _rebuildParentProductStock(db, productId: productId);
    }
  }

  static Future<void> validateStockReversal(
    DatabaseExecutor db,
    List<PurchaseItem> items,
  ) async {
    final productEntries = _groupProductEntries(items);

    for (final entry in productEntries) {
      if (entry.productVariantId != null) {
        final rows = await db.rawQuery(
          '''
          SELECT
            pv.estoque_mil,
            p.nome,
            pv.cor,
            pv.tamanho
          FROM ${TableNames.produtoVariantes} pv
          INNER JOIN ${TableNames.produtos} p
            ON p.id = pv.produto_id
          WHERE pv.id = ?
          LIMIT 1
          ''',
          [entry.productVariantId],
        );
        if (rows.isEmpty) {
          throw const ValidationException(
            'Nao foi possivel validar o estoque de uma das variacoes da compra.',
          );
        }

        final currentStock = rows.first['estoque_mil'] as int? ?? 0;
        if (currentStock < entry.quantityMil) {
          final color = rows.first['cor'] as String? ?? '';
          final size = rows.first['tamanho'] as String? ?? '';
          final variantLabel = [size, color]
              .where((value) => value.trim().isNotEmpty)
              .join(' / ');
          throw ValidationException(
            'Nao ha estoque suficiente para reverter a compra de ${rows.first['nome']}${variantLabel.isEmpty ? '' : ' ($variantLabel)'}.',
          );
        }
        continue;
      }

      final rows = await db.query(
        TableNames.produtos,
        columns: ['estoque_mil', 'nome'],
        where: 'id = ?',
        whereArgs: [entry.productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const ValidationException(
          'Nao foi possivel validar o estoque de um dos itens da compra.',
        );
      }
      final currentStock = rows.first['estoque_mil'] as int? ?? 0;
      if (currentStock < entry.quantityMil) {
        throw ValidationException(
          'Nao ha estoque suficiente para reverter a compra do produto ${rows.first['nome']}.',
        );
      }
    }
  }

  static List<_ProductStockEntry> _groupProductEntries(
    List<PurchaseItem> items, {
    int factor = 1,
  }) {
    final grouped = <String, _ProductStockEntry>{};
    for (final item in items) {
      if (!item.isProduct || item.productId == null) {
        continue;
      }

      final key = '${item.productId}:${item.productVariantId ?? 0}';
      grouped.update(
        key,
        (current) => current.copyWith(
          quantityMil: current.quantityMil + (item.quantityMil * factor),
        ),
        ifAbsent: () => _ProductStockEntry(
          productId: item.productId!,
          productVariantId: item.productVariantId,
          quantityMil: item.quantityMil * factor,
        ),
      );
    }

    grouped.removeWhere((_, value) => value.quantityMil == 0);
    return grouped.values.toList(growable: false);
  }

  static Future<void> _rebuildParentProductStock(
    DatabaseExecutor db, {
    required int productId,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
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
      [productId, nowIso, productId],
    );
  }
}

class _ProductStockEntry {
  const _ProductStockEntry({
    required this.productId,
    required this.productVariantId,
    required this.quantityMil,
  });

  final int productId;
  final int? productVariantId;
  final int quantityMil;

  _ProductStockEntry copyWith({int? quantityMil}) {
    return _ProductStockEntry(
      productId: productId,
      productVariantId: productVariantId,
      quantityMil: quantityMil ?? this.quantityMil,
    );
  }
}
