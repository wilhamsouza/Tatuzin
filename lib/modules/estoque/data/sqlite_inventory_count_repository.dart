import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/inventory_count_item.dart';
import '../domain/entities/inventory_count_item_input.dart';
import '../domain/entities/inventory_count_session.dart';
import '../domain/entities/inventory_count_session_detail.dart';
import '../domain/entities/inventory_count_summary.dart';
import 'support/inventory_balance_support.dart';
import 'support/inventory_movement_writer.dart';

class SqliteInventoryCountRepository {
  SqliteInventoryCountRepository(AppDatabase appDatabase)
    : _databaseLoader = (() => appDatabase.database);

  SqliteInventoryCountRepository.forDatabase({
    required Future<Database> Function() databaseLoader,
  }) : _databaseLoader = databaseLoader;

  final Future<Database> Function() _databaseLoader;

  Future<List<InventoryCountSession>> listSessions() async {
    final database = await _databaseLoader();
    final rows = await _loadSessionRows(database);
    return rows.map(_mapSession).toList(growable: false);
  }

  Future<InventoryCountSession> createSession({required String name}) async {
    final normalizedName = _cleanNullable(name);
    if (normalizedName == null) {
      throw const ValidationException(
        'Informe um nome para criar a sessao de inventario.',
      );
    }

    final database = await _databaseLoader();
    return database.transaction((txn) async {
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final sessionId = await txn.insert(TableNames.inventoryCountSessions, {
        'uuid': IdGenerator.next(),
        'name': normalizedName,
        'status': InventoryCountSessionStatus.open.storageValue,
        'created_at': nowIso,
        'updated_at': nowIso,
        'applied_at': null,
      });

      final rows = await _loadSessionRows(txn, sessionId: sessionId);
      return _mapSession(rows.single);
    });
  }

  Future<InventoryCountSessionDetail?> getSessionDetail(int sessionId) async {
    final database = await _databaseLoader();
    final sessionRows = await _loadSessionRows(database, sessionId: sessionId);
    if (sessionRows.isEmpty) {
      return null;
    }

    final itemRows = await _loadCountItemRows(database, sessionId: sessionId);
    final items = itemRows.map(_mapCountItem).toList(growable: false);
    return InventoryCountSessionDetail(
      session: _mapSession(sessionRows.single),
      items: items,
      summary: InventoryCountSummary.fromItems(items),
    );
  }

  Future<InventoryCountItem> upsertItem(InventoryCountItemInput input) async {
    if (input.countedStockMil < 0) {
      throw const ValidationException(
        'A quantidade contada nao pode ser negativa.',
      );
    }

    final database = await _databaseLoader();
    return database.transaction((txn) async {
      final session = await _loadSessionForUpdate(
        txn,
        sessionId: input.sessionId,
        requireEditable: true,
      );
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final existingRow = await _findExistingCountItemRow(
        txn,
        sessionId: input.sessionId,
        productId: input.productId,
        productVariantId: input.productVariantId,
      );

      int countItemId;
      if (existingRow == null) {
        final currentItem = await _loadCurrentInventoryRow(
          txn,
          productId: input.productId,
          productVariantId: input.productVariantId,
        );
        if (currentItem == null) {
          throw const ValidationException(
            'Item de estoque nao encontrado para iniciar a contagem.',
          );
        }

        countItemId = await txn.insert(TableNames.inventoryCountItems, {
          'count_session_id': input.sessionId,
          'product_id': input.productId,
          'product_variant_id': input.productVariantId,
          'system_stock_mil': currentItem['current_stock_mil'] as int? ?? 0,
          'counted_stock_mil': input.countedStockMil,
          'difference_mil':
              input.countedStockMil -
              (currentItem['current_stock_mil'] as int? ?? 0),
          'stale_override': 0,
          'applied_from_system_stock_mil': null,
          'stale_at_apply': 0,
          'notes': _cleanNullable(input.notes),
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      } else {
        countItemId = existingRow['id'] as int;
        final systemStockMil = existingRow['system_stock_mil'] as int? ?? 0;
        await txn.update(
          TableNames.inventoryCountItems,
          {
            'counted_stock_mil': input.countedStockMil,
            'difference_mil': input.countedStockMil - systemStockMil,
            'stale_override': 0,
            'applied_from_system_stock_mil': null,
            'stale_at_apply': 0,
            'notes': _cleanNullable(input.notes),
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [countItemId],
        );
      }

      final nextStatus = switch (session.status) {
        InventoryCountSessionStatus.open =>
          InventoryCountSessionStatus.counting,
        InventoryCountSessionStatus.counting =>
          InventoryCountSessionStatus.counting,
        InventoryCountSessionStatus.reviewed =>
          InventoryCountSessionStatus.counting,
        InventoryCountSessionStatus.applied =>
          InventoryCountSessionStatus.applied,
        InventoryCountSessionStatus.canceled =>
          InventoryCountSessionStatus.canceled,
      };
      await txn.update(
        TableNames.inventoryCountSessions,
        {'status': nextStatus.storageValue, 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: [input.sessionId],
      );

      final rows = await _loadCountItemRows(
        txn,
        sessionId: input.sessionId,
        countItemId: countItemId,
      );
      return _mapCountItem(rows.single);
    });
  }

  Future<InventoryCountItem> recalculateItemFromCurrentStock(
    int countItemId,
  ) async {
    final database = await _databaseLoader();
    return database.transaction((txn) async {
      final row = await _loadCountItemRowById(txn, countItemId: countItemId);
      if (row == null) {
        throw const ValidationException(
          'Item da sessao de inventario nao encontrado.',
        );
      }
      final item = _mapCountItem(row);
      await _loadSessionForUpdate(
        txn,
        sessionId: item.countSessionId,
        requireEditable: true,
      );

      final currentItem = await _loadCurrentInventoryRow(
        txn,
        productId: item.productId,
        productVariantId: item.productVariantId,
      );
      if (currentItem == null) {
        throw ValidationException(
          'Item de estoque nao encontrado para revisar a contagem: ${item.displayName}.',
        );
      }

      final nowIso = DateTime.now().toIso8601String();
      final currentStockMil = currentItem['current_stock_mil'] as int? ?? 0;
      await txn.update(
        TableNames.inventoryCountItems,
        {
          'system_stock_mil': currentStockMil,
          'difference_mil': item.countedStockMil - currentStockMil,
          'stale_override': 0,
          'applied_from_system_stock_mil': null,
          'stale_at_apply': 0,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [countItemId],
      );

      final refreshedRows = await _loadCountItemRows(
        txn,
        sessionId: item.countSessionId,
        countItemId: countItemId,
      );
      return _mapCountItem(refreshedRows.single);
    });
  }

  Future<InventoryCountItem> keepRecordedDifference(int countItemId) async {
    final database = await _databaseLoader();
    return database.transaction((txn) async {
      final row = await _loadCountItemRowById(txn, countItemId: countItemId);
      if (row == null) {
        throw const ValidationException(
          'Item da sessao de inventario nao encontrado.',
        );
      }
      final item = _mapCountItem(row);
      await _loadSessionForUpdate(
        txn,
        sessionId: item.countSessionId,
        requireEditable: true,
      );
      if (!item.isStale) {
        return item;
      }

      final nowIso = DateTime.now().toIso8601String();
      await txn.update(
        TableNames.inventoryCountItems,
        {
          'stale_override': 1,
          'applied_from_system_stock_mil': null,
          'stale_at_apply': 0,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [countItemId],
      );

      final refreshedRows = await _loadCountItemRows(
        txn,
        sessionId: item.countSessionId,
        countItemId: countItemId,
      );
      return _mapCountItem(refreshedRows.single);
    });
  }

  Future<void> markSessionReviewed(int sessionId) async {
    final database = await _databaseLoader();
    await database.transaction((txn) async {
      final session = await _loadSessionForUpdate(
        txn,
        sessionId: sessionId,
        requireEditable: true,
      );
      final itemCount = await _loadItemCount(txn, sessionId: sessionId);
      if (itemCount <= 0) {
        throw const ValidationException(
          'Adicione ao menos um item antes de revisar a sessao.',
        );
      }

      final nowIso = DateTime.now().toIso8601String();
      await txn.update(
        TableNames.inventoryCountSessions,
        {
          'status': InventoryCountSessionStatus.reviewed.storageValue,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  Future<void> applySession(int sessionId) async {
    final database = await _databaseLoader();
    await database.transaction((txn) async {
      final session = await _loadSessionForUpdate(
        txn,
        sessionId: sessionId,
        requireEditable: false,
      );
      if (session.status == InventoryCountSessionStatus.applied) {
        throw const ValidationException(
          'Esta sessao de inventario ja foi aplicada.',
        );
      }
      if (session.status == InventoryCountSessionStatus.canceled) {
        throw const ValidationException(
          'Nao e possivel aplicar uma sessao cancelada.',
        );
      }

      final itemRows = await _loadCountItemRows(txn, sessionId: sessionId);
      if (itemRows.isEmpty) {
        throw const ValidationException(
          'Adicione ao menos um item antes de aplicar a sessao.',
        );
      }

      final items = itemRows.map(_mapCountItem).toList(growable: false);
      _throwIfSessionHasPendingStaleItems(items);

      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      for (final item in items) {
        await txn.update(
          TableNames.inventoryCountItems,
          {
            'applied_from_system_stock_mil': item.currentStockMil,
            'stale_at_apply': item.isStale ? 1 : 0,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
        if (!item.hasDifference) {
          continue;
        }

        final change = await InventoryBalanceSupport.applyStockDelta(
          txn,
          productId: item.productId,
          productVariantId: item.productVariantId,
          quantityDeltaMil: item.differenceMil,
          allowNegativeStock: false,
          productNotFoundMessage:
              'Produto nao encontrado para aplicar a contagem: ${item.displayName}.',
          variantNotFoundMessage:
              'Variante nao encontrada para aplicar a contagem: ${item.displayName}.',
          insufficientProductStockMessage:
              'A aplicacao da contagem deixaria ${item.displayName} com estoque negativo.',
          insufficientVariantStockMessage:
              'A aplicacao da contagem deixaria ${item.displayName} com estoque negativo.',
          changedAt: now,
        );

        final note = _buildMovementNote(session: session, item: item);
        if (item.differenceMil > 0) {
          await InventoryMovementWriter.writeCountAdjustmentIn(
            txn,
            changes: [change],
            referenceId: session.id,
            notes: note,
            createdAt: now,
          );
        } else {
          await InventoryMovementWriter.writeCountAdjustmentOut(
            txn,
            changes: [change],
            referenceId: session.id,
            notes: note,
            createdAt: now,
          );
        }
      }

      await txn.update(
        TableNames.inventoryCountSessions,
        {
          'status': InventoryCountSessionStatus.applied.storageValue,
          'updated_at': nowIso,
          'applied_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  Future<InventoryCountSession> _loadSessionForUpdate(
    DatabaseExecutor db, {
    required int sessionId,
    required bool requireEditable,
  }) async {
    final rows = await _loadSessionRows(db, sessionId: sessionId);
    if (rows.isEmpty) {
      throw const ValidationException('Sessao de inventario nao encontrada.');
    }
    final session = _mapSession(rows.single);
    if (requireEditable && !session.status.canEdit) {
      throw const ValidationException(
        'Esta sessao nao pode mais receber alteracoes.',
      );
    }
    return session;
  }

  Future<List<Map<String, Object?>>> _loadSessionRows(
    DatabaseExecutor db, {
    int? sessionId,
  }) {
    final args = <Object?>[];
    final buffer = StringBuffer(_sessionSelectSql);
    if (sessionId != null) {
      buffer.write(' WHERE s.id = ?');
      args.add(sessionId);
    }
    buffer.write('''
      GROUP BY s.id
      ORDER BY
        CASE s.status
          WHEN 'open' THEN 0
          WHEN 'counting' THEN 1
          WHEN 'reviewed' THEN 2
          WHEN 'applied' THEN 3
          ELSE 4
        END,
        s.updated_at DESC,
        s.id DESC
    ''');
    return db.rawQuery(buffer.toString(), args);
  }

  Future<int> _loadItemCount(
    DatabaseExecutor db, {
    required int sessionId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${TableNames.inventoryCountItems}
      WHERE count_session_id = ?
      ''',
      [sessionId],
    );
    return rows.first['total'] as int? ?? 0;
  }

  Future<Map<String, Object?>?> _findExistingCountItemRow(
    DatabaseExecutor db, {
    required int sessionId,
    required int productId,
    required int? productVariantId,
  }) async {
    final rows = await db.query(
      TableNames.inventoryCountItems,
      where: productVariantId == null
          ? 'count_session_id = ? AND product_id = ? AND product_variant_id IS NULL'
          : 'count_session_id = ? AND product_id = ? AND product_variant_id = ?',
      whereArgs: productVariantId == null
          ? [sessionId, productId]
          : [sessionId, productId, productVariantId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Map<String, Object?>?> _loadCountItemRowById(
    DatabaseExecutor db, {
    required int countItemId,
  }) async {
    final rows = await db.query(
      TableNames.inventoryCountItems,
      where: 'id = ?',
      whereArgs: [countItemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Map<String, Object?>?> _loadCurrentInventoryRow(
    DatabaseExecutor db, {
    required int productId,
    required int? productVariantId,
  }) async {
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT
        p.id AS product_id,
        pv.id AS product_variant_id,
        p.nome AS product_name,
        COALESCE(NULLIF(TRIM(pv.sku), ''), NULLIF(TRIM(p.codigo_barras), '')) AS sku,
        pv.cor AS variant_color,
        pv.tamanho AS variant_size,
        p.unidade_medida AS unit_measure,
        COALESCE(pv.estoque_mil, p.estoque_mil, 0) AS current_stock_mil
      FROM ${TableNames.produtos} p
      LEFT JOIN ${TableNames.produtoVariantes} pv
        ON pv.produto_id = p.id
      WHERE p.deletado_em IS NULL
        AND p.ativo = 1
    ''');

    if (productVariantId != null) {
      buffer.write(' AND p.id = ? AND pv.id = ? AND COALESCE(pv.ativo, 1) = 1');
      args.addAll([productId, productVariantId]);
    } else {
      buffer.write(' AND p.id = ? AND pv.id IS NULL');
      args.add(productId);
    }

    buffer.write(' LIMIT 1');
    final rows = await db.rawQuery(buffer.toString(), args);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<List<Map<String, Object?>>> _loadCountItemRows(
    DatabaseExecutor db, {
    required int sessionId,
    int? countItemId,
  }) async {
    final args = <Object?>[sessionId];
    final buffer = StringBuffer('''
      SELECT
        ci.*,
        p.nome AS product_name,
        COALESCE(NULLIF(TRIM(pv.sku), ''), NULLIF(TRIM(p.codigo_barras), '')) AS sku,
        pv.cor AS variant_color,
        pv.tamanho AS variant_size,
        p.unidade_medida AS unit_measure,
        COALESCE(pv.estoque_mil, p.estoque_mil, 0) AS current_stock_mil,
        COALESCE(ci.stale_override, 0) AS stale_override,
        ci.applied_from_system_stock_mil AS applied_from_system_stock_mil,
        COALESCE(ci.stale_at_apply, 0) AS stale_at_apply
      FROM ${TableNames.inventoryCountItems} ci
      INNER JOIN ${TableNames.produtos} p
        ON p.id = ci.product_id
      LEFT JOIN ${TableNames.produtoVariantes} pv
        ON pv.id = ci.product_variant_id
      WHERE ci.count_session_id = ?
    ''');
    if (countItemId != null) {
      buffer.write(' AND ci.id = ?');
      args.add(countItemId);
    }
    buffer.write('''
      ORDER BY p.nome COLLATE NOCASE ASC, COALESCE(pv.ordem, 0) ASC, ci.id ASC
    ''');
    return db.rawQuery(buffer.toString(), args);
  }

  InventoryCountSession _mapSession(Map<String, Object?> row) {
    return InventoryCountSession(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      name: row['name'] as String? ?? 'Inventario',
      status: inventoryCountSessionStatusFromStorage(row['status'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      appliedAt: row['applied_at'] == null
          ? null
          : DateTime.parse(row['applied_at'] as String),
      totalItems: row['total_items'] as int? ?? 0,
      itemsWithDifference: row['items_with_difference'] as int? ?? 0,
      surplusMil: row['surplus_mil'] as int? ?? 0,
      shortageMil: row['shortage_mil'] as int? ?? 0,
    );
  }

  InventoryCountItem _mapCountItem(Map<String, Object?> row) {
    return InventoryCountItem(
      id: row['id'] as int,
      countSessionId: row['count_session_id'] as int,
      productId: row['product_id'] as int,
      productVariantId: row['product_variant_id'] as int?,
      productName: row['product_name'] as String? ?? 'Produto',
      sku: _cleanNullable(row['sku'] as String?),
      variantColorLabel: _cleanNullable(row['variant_color'] as String?),
      variantSizeLabel: _cleanNullable(row['variant_size'] as String?),
      unitMeasure: row['unit_measure'] as String? ?? 'un',
      systemStockMil: row['system_stock_mil'] as int? ?? 0,
      currentStockMil: row['current_stock_mil'] as int? ?? 0,
      countedStockMil: row['counted_stock_mil'] as int? ?? 0,
      differenceMil: row['difference_mil'] as int? ?? 0,
      staleOverride: (row['stale_override'] as int? ?? 0) == 1,
      appliedFromSystemStockMil: row['applied_from_system_stock_mil'] as int?,
      staleAtApply: (row['stale_at_apply'] as int? ?? 0) == 1,
      notes: _cleanNullable(row['notes'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  void _throwIfSessionHasPendingStaleItems(List<InventoryCountItem> items) {
    final staleItems = items
        .where((item) => item.needsReview)
        .toList(growable: false);
    if (staleItems.isEmpty) {
      return;
    }

    final firstName = staleItems.first.displayName;
    if (staleItems.length == 1) {
      throw ValidationException(
        'A sessao possui 1 item desatualizado: $firstName. Revise a contagem antes de aplicar.',
      );
    }

    throw ValidationException(
      'A sessao possui ${staleItems.length} itens desatualizados. Revise-os antes de aplicar. Primeiro item: $firstName.',
    );
  }

  String _buildMovementNote({
    required InventoryCountSession session,
    required InventoryCountItem item,
  }) {
    final parts = <String>[
      'Sessao "${session.name}"',
      'Item da contagem #${item.id}',
    ];
    final itemNotes = _cleanNullable(item.notes);
    if (itemNotes != null) {
      parts.add(itemNotes);
    }
    return parts.join(' | ');
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static const String _sessionSelectSql =
      '''
    SELECT
      s.*,
      COUNT(ci.id) AS total_items,
      COALESCE(SUM(CASE WHEN ci.difference_mil != 0 THEN 1 ELSE 0 END), 0)
        AS items_with_difference,
      COALESCE(SUM(CASE WHEN ci.difference_mil > 0 THEN ci.difference_mil ELSE 0 END), 0)
        AS surplus_mil,
      COALESCE(SUM(CASE WHEN ci.difference_mil < 0 THEN ABS(ci.difference_mil) ELSE 0 END), 0)
        AS shortage_mil
    FROM ${TableNames.inventoryCountSessions} s
    LEFT JOIN ${TableNames.inventoryCountItems} ci
      ON ci.count_session_id = s.id
  ''';
}
