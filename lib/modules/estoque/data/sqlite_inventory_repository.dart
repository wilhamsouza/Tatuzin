import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/inventory_adjustment_input.dart';
import '../domain/entities/inventory_item.dart';
import '../domain/entities/inventory_movement.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/services/inventory_alert_service.dart';
import 'support/inventory_balance_support.dart';
import 'support/inventory_movement_writer.dart';

class SqliteInventoryRepository implements InventoryRepository {
  SqliteInventoryRepository(AppDatabase appDatabase)
    : _databaseLoader = (() => appDatabase.database);

  SqliteInventoryRepository.forDatabase({
    required Future<Database> Function() databaseLoader,
  }) : _databaseLoader = databaseLoader;

  final Future<Database> Function() _databaseLoader;

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) async {
    if (input.quantityMil <= 0) {
      throw const ValidationException(
        'Informe uma quantidade maior que zero para ajustar o estoque.',
      );
    }

    final database = await _databaseLoader();
    await database.transaction((txn) async {
      final currentItem = await _findItemInDatabase(
        txn,
        productId: input.productId,
        productVariantId: input.productVariantId,
      );
      if (currentItem == null) {
        throw const ValidationException('Item de estoque nao encontrado.');
      }

      final now = DateTime.now();
      final change = await InventoryBalanceSupport.applyStockDelta(
        txn,
        productId: input.productId,
        productVariantId: input.productVariantId,
        quantityDeltaMil: input.direction.resolveDelta(input.quantityMil),
        allowNegativeStock: currentItem.allowNegativeStock,
        productNotFoundMessage: 'Produto nao encontrado para ajuste.',
        variantNotFoundMessage: 'Variacao nao encontrada para ajuste.',
        insufficientProductStockMessage:
            'O ajuste deixaria o produto com estoque negativo.',
        insufficientVariantStockMessage:
            'O ajuste deixaria a variacao com estoque negativo.',
        changedAt: now,
      );

      await InventoryMovementWriter.recordChanges(
        txn,
        changes: [change],
        movementType: input.direction.movementType,
        referenceType: 'manual_adjustment',
        reason: input.reason.storageValue,
        notes: input.notes,
        createdAt: now,
      );
    });
  }

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) async {
    final database = await _databaseLoader();
    return _findItemInDatabase(
      database,
      productId: productId,
      productVariantId: productVariantId,
    );
  }

  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) async {
    final database = await _databaseLoader();
    final rows = await _loadItemRows(database, query: query);
    final items = rows.map(_mapInventoryItem).toList(growable: false);
    return InventoryAlertService.applyFilter(items, filter: filter);
  }

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) async {
    final database = await _databaseLoader();
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        im.*,
        p.nome AS product_name,
        COALESCE(NULLIF(TRIM(pv.sku), ''), NULLIF(TRIM(p.codigo_barras), '')) AS sku,
        pv.cor AS variant_color,
        pv.tamanho AS variant_size
      FROM ${TableNames.inventoryMovements} im
      INNER JOIN ${TableNames.produtos} p
        ON p.id = im.product_id
      LEFT JOIN ${TableNames.produtoVariantes} pv
        ON pv.id = im.product_variant_id
      WHERE 1 = 1
    ''');

    if (productVariantId != null) {
      buffer.write(' AND im.product_variant_id = ?');
      args.add(productVariantId);
    } else if (productId != null) {
      buffer.write(' AND im.product_id = ?');
      if (!includeVariantsForProduct) {
        buffer.write(' AND im.product_variant_id IS NULL');
      }
      args.add(productId);
    }
    if (movementType != null) {
      buffer.write(' AND im.movement_type = ?');
      args.add(movementType.storageValue);
    }
    if (createdFrom != null) {
      buffer.write(' AND im.created_at >= ?');
      args.add(createdFrom.toIso8601String());
    }
    if (createdTo != null) {
      buffer.write(' AND im.created_at <= ?');
      args.add(createdTo.toIso8601String());
    }

    buffer.write(' ORDER BY im.created_at DESC, im.id DESC LIMIT ?');
    args.add(limit);

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapInventoryMovement).toList(growable: false);
  }

  Future<InventoryItem?> _findItemInDatabase(
    DatabaseExecutor db, {
    required int productId,
    int? productVariantId,
  }) async {
    final rows = await _loadItemRows(
      db,
      query: '',
      productId: productId,
      productVariantId: productVariantId,
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapInventoryItem(rows.first);
  }

  Future<List<Map<String, Object?>>> _loadItemRows(
    DatabaseExecutor db, {
    required String query,
    int? productId,
    int? productVariantId,
    int? limit,
  }) async {
    final args = <Object?>[];
    final buffer = StringBuffer(_inventoryItemsSelectSql);

    if (productVariantId != null) {
      buffer.write(' AND pv.id = ?');
      args.add(productVariantId);
    } else if (productId != null) {
      buffer.write(' AND p.id = ? AND pv.id IS NULL');
      args.add(productId);
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      final likeQuery = '%$trimmedQuery%';
      buffer.write('''
        AND (
          p.nome LIKE ? COLLATE NOCASE
          OR COALESCE(p.codigo_barras, '') LIKE ? COLLATE NOCASE
          OR COALESCE(pv.sku, '') LIKE ? COLLATE NOCASE
          OR COALESCE(pv.cor, '') LIKE ? COLLATE NOCASE
          OR COALESCE(pv.tamanho, '') LIKE ? COLLATE NOCASE
        )
      ''');
      args.addAll([likeQuery, likeQuery, likeQuery, likeQuery, likeQuery]);
    }

    buffer.write('''
      ORDER BY p.nome COLLATE NOCASE ASC, COALESCE(pv.ordem, 0) ASC, pv.id ASC
    ''');

    if (limit != null) {
      buffer.write(' LIMIT ?');
      args.add(limit);
    }

    return db.rawQuery(buffer.toString(), args);
  }

  InventoryItem _mapInventoryItem(Map<String, Object?> row) {
    return InventoryItem(
      productId: row['product_id'] as int,
      productVariantId: row['product_variant_id'] as int?,
      productName: row['product_name'] as String? ?? 'Produto',
      sku: _cleanNullable(row['sku'] as String?),
      variantColorLabel: _cleanNullable(row['variant_color'] as String?),
      variantSizeLabel: _cleanNullable(row['variant_size'] as String?),
      unitMeasure: row['unit_measure'] as String? ?? 'un',
      currentStockMil: row['current_stock_mil'] as int? ?? 0,
      minimumStockMil: row['minimum_stock_mil'] as int? ?? 0,
      reorderPointMil: row['reorder_point_mil'] as int?,
      allowNegativeStock: (row['allow_negative_stock'] as int? ?? 0) == 1,
      costCents: row['cost_cents'] as int? ?? 0,
      salePriceCents: row['sale_price_cents'] as int? ?? 0,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  InventoryMovement _mapInventoryMovement(Map<String, Object?> row) {
    return InventoryMovement(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      productId: row['product_id'] as int,
      productVariantId: row['product_variant_id'] as int?,
      productName: row['product_name'] as String? ?? 'Produto',
      sku: _cleanNullable(row['sku'] as String?),
      variantColorLabel: _cleanNullable(row['variant_color'] as String?),
      variantSizeLabel: _cleanNullable(row['variant_size'] as String?),
      movementType: inventoryMovementTypeFromStorage(
        row['movement_type'] as String?,
      ),
      quantityDeltaMil: row['quantity_delta_mil'] as int? ?? 0,
      stockBeforeMil: row['stock_before_mil'] as int? ?? 0,
      stockAfterMil: row['stock_after_mil'] as int? ?? 0,
      referenceType: row['reference_type'] as String? ?? 'manual_adjustment',
      referenceId: row['reference_id'] as int?,
      reason: _cleanNullable(row['reason'] as String?),
      notes: _cleanNullable(row['notes'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static const String _inventoryItemsSelectSql =
      '''
    SELECT
      p.id AS product_id,
      pv.id AS product_variant_id,
      p.nome AS product_name,
      COALESCE(NULLIF(TRIM(pv.sku), ''), NULLIF(TRIM(p.codigo_barras), '')) AS sku,
      pv.cor AS variant_color,
      pv.tamanho AS variant_size,
      p.unidade_medida AS unit_measure,
      COALESCE(pv.estoque_mil, p.estoque_mil, 0) AS current_stock_mil,
      COALESCE((
        SELECT s.minimum_stock_mil
        FROM ${TableNames.inventorySettings} s
        WHERE s.product_id = p.id
          AND (
            (pv.id IS NULL AND s.product_variant_id IS NULL)
            OR s.product_variant_id = pv.id
          )
        ORDER BY s.id DESC
        LIMIT 1
      ), 0) AS minimum_stock_mil,
      (
        SELECT s.reorder_point_mil
        FROM ${TableNames.inventorySettings} s
        WHERE s.product_id = p.id
          AND (
            (pv.id IS NULL AND s.product_variant_id IS NULL)
            OR s.product_variant_id = pv.id
          )
        ORDER BY s.id DESC
        LIMIT 1
      ) AS reorder_point_mil,
      COALESCE((
        SELECT s.allow_negative_stock
        FROM ${TableNames.inventorySettings} s
        WHERE s.product_id = p.id
          AND (
            (pv.id IS NULL AND s.product_variant_id IS NULL)
            OR s.product_variant_id = pv.id
          )
        ORDER BY s.id DESC
        LIMIT 1
      ), 0) AS allow_negative_stock,
      p.custo_centavos AS cost_cents,
      p.preco_venda_centavos + COALESCE(pv.preco_adicional_centavos, 0)
        AS sale_price_cents,
      CASE
        WHEN p.ativo = 1 AND COALESCE(pv.ativo, 1) = 1 THEN 1
        ELSE 0
      END AS is_active,
      COALESCE(pv.atualizado_em, p.atualizado_em) AS updated_at
    FROM ${TableNames.produtos} p
    LEFT JOIN ${TableNames.produtoVariantes} pv
      ON pv.produto_id = p.id
    WHERE p.deletado_em IS NULL
  ''';
}
