import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../domain/entities/product.dart';
import '../../domain/services/product_cost_calculator.dart';

abstract final class ProductCostDatabaseSupport {
  static Future<ProductCostSummary> recalculateAndPersistForProduct(
    DatabaseExecutor txn, {
    required int productId,
    DateTime? changedAt,
  }) async {
    final productRows = await txn.query(
      TableNames.produtos,
      columns: const ['id', 'preco_venda_centavos', 'manual_cost_centavos'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (productRows.isEmpty) {
      return const ProductCostSummary.empty(salePriceCents: 0);
    }

    final salePriceCents =
        productRows.first['preco_venda_centavos'] as int? ?? 0;
    final recipeRows = await loadRecipeDetailRows(txn, productId: productId);
    if (recipeRows.isEmpty) {
      await txn.delete(
        TableNames.productCostSnapshot,
        where: 'product_id = ?',
        whereArgs: [productId],
      );
      await txn.update(
        TableNames.produtos,
        {
          'custo_centavos':
              productRows.first['manual_cost_centavos'] as int? ?? 0,
          'cost_source': ProductCostSource.manual.storageValue,
          'atualizado_em': (changedAt ?? DateTime.now()).toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [productId],
      );
      return ProductCostSummary.empty(salePriceCents: salePriceCents);
    }

    final summary = ProductCostCalculator.calculate(
      salePriceCents: salePriceCents,
      items: recipeRows.map(_mapComponentInput).toList(growable: false),
    );

    final nowIso = (changedAt ?? DateTime.now()).toIso8601String();
    final existingSnapshot = await txn.query(
      TableNames.productCostSnapshot,
      columns: const ['product_id', 'created_at'],
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );

    if (existingSnapshot.isEmpty) {
      await txn.insert(TableNames.productCostSnapshot, {
        'product_id': productId,
        'variable_cost_snapshot_cents': summary.variableCostSnapshotCents,
        'estimated_gross_margin_cents': summary.estimatedGrossMarginCents,
        'estimated_gross_margin_percent_basis_points':
            summary.estimatedGrossMarginPercentBasisPoints,
        'last_cost_updated_at': nowIso,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    } else {
      await txn.update(
        TableNames.productCostSnapshot,
        {
          'variable_cost_snapshot_cents': summary.variableCostSnapshotCents,
          'estimated_gross_margin_cents': summary.estimatedGrossMarginCents,
          'estimated_gross_margin_percent_basis_points':
              summary.estimatedGrossMarginPercentBasisPoints,
          'last_cost_updated_at': nowIso,
          'updated_at': nowIso,
        },
        where: 'product_id = ?',
        whereArgs: [productId],
      );
    }

    await txn.update(
      TableNames.produtos,
      {
        'custo_centavos': summary.variableCostSnapshotCents,
        'cost_source': ProductCostSource.recipeSnapshot.storageValue,
        'atualizado_em': nowIso,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );

    return summary;
  }

  static Future<List<Map<String, Object?>>> loadRecipeDetailRows(
    DatabaseExecutor txn, {
    required int productId,
  }) {
    return txn.rawQuery(
      '''
      SELECT
        pri.*,
        s.name AS supply_name,
        s.purchase_unit_type AS supply_purchase_unit_type,
        s.last_purchase_price_cents AS supply_last_purchase_price_cents,
        s.conversion_factor AS supply_conversion_factor
      FROM ${TableNames.productRecipeItems} pri
      INNER JOIN ${TableNames.supplies} s
        ON s.id = pri.supply_id
      WHERE pri.product_id = ?
      ORDER BY pri.id ASC
    ''',
      [productId],
    );
  }

  static ProductCostComponentInput _mapComponentInput(
    Map<String, Object?> row,
  ) {
    return ProductCostComponentInput(
      supplyId: row['supply_id'] as int,
      supplyName: row['supply_name'] as String? ?? 'Insumo',
      purchaseUnitType:
          row['supply_purchase_unit_type'] as String? ??
          row['unit_type'] as String? ??
          'un',
      unitType: row['unit_type'] as String? ?? 'un',
      conversionFactor: row['supply_conversion_factor'] as int? ?? 1,
      lastPurchasePriceCents:
          row['supply_last_purchase_price_cents'] as int? ?? 0,
      quantityUsedMil: row['quantity_used_mil'] as int? ?? 0,
      wasteBasisPoints: row['waste_basis_points'] as int? ?? 0,
      notes: row['notes'] as String?,
    );
  }
}
