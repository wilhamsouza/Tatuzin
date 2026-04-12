import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/operational_order.dart';
import '../domain/entities/operational_order_item.dart';
import '../domain/entities/operational_order_item_modifier.dart';
import '../domain/entities/operational_order_summary.dart';
import '../domain/repositories/operational_order_repository.dart';

class SqliteOperationalOrderRepository implements OperationalOrderRepository {
  const SqliteOperationalOrderRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<int> create(OperationalOrderInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    return database.insert(TableNames.pedidosOperacionais, {
      'uuid': IdGenerator.next(),
      'status': input.status.dbValue,
      'observacao': _cleanNullable(input.notes),
      'criado_em': now,
      'atualizado_em': now,
      'fechado_em': null,
    });
  }

  @override
  Future<List<OperationalOrder>> list({String query = ''}) async {
    final database = await _appDatabase.database;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final rows = await database.query(
        TableNames.pedidosOperacionais,
        orderBy: 'atualizado_em DESC, id DESC',
      );
      return rows.map(_mapOrder).toList();
    }

    final rows = await database.query(
      TableNames.pedidosOperacionais,
      where: 'COALESCE(observacao, \'\') LIKE ? COLLATE NOCASE',
      whereArgs: ['%$trimmed%'],
      orderBy: 'atualizado_em DESC, id DESC',
    );
    return rows.map(_mapOrder).toList();
  }

  @override
  Future<List<OperationalOrderSummary>> listSummaries({
    String query = '',
    OperationalOrderStatus? status,
  }) async {
    final database = await _appDatabase.database;
    final trimmed = query.trim();
    final normalizedLike = '%$trimmed%';
    final args = <Object?>[];
    final where = <String>[];

    if (trimmed.isNotEmpty) {
      where.add(
        '('
        'CAST(p.id AS TEXT) LIKE ? '
        'OR COALESCE(p.observacao, \'\') LIKE ? COLLATE NOCASE '
        'OR EXISTS ('
        '  SELECT 1'
        '  FROM ${TableNames.pedidosOperacionaisItens} i2'
        '  WHERE i2.pedido_operacional_id = p.id'
        '    AND ('
        '      COALESCE(i2.nome_produto_snapshot, \'\') LIKE ? COLLATE NOCASE'
        '      OR COALESCE(i2.observacao, \'\') LIKE ? COLLATE NOCASE'
        '    )'
        ')'
        ')',
      );
      args.addAll(<Object?>[
        normalizedLike,
        normalizedLike,
        normalizedLike,
        normalizedLike,
      ]);
    }

    if (status != null) {
      where.add('p.status = ?');
      args.add(status.dbValue);
    }

    final rows = await database.rawQuery('''
      SELECT
        p.*,
        COALESCE(item_agg.line_items_count, 0) AS line_items_count,
        COALESCE(item_agg.total_units, 0) AS total_units,
        COALESCE(item_agg.total_cents, 0) AS total_cents
      FROM ${TableNames.pedidosOperacionais} p
      LEFT JOIN (
        SELECT
          i.pedido_operacional_id AS order_id,
          COUNT(*) AS line_items_count,
          COALESCE(SUM(CAST(i.quantidade_mil / 1000 AS INTEGER)), 0) AS total_units,
          COALESCE(
            SUM(
              i.subtotal_centavos +
              (
                COALESCE(mod_agg.total_modifier_delta_cents, 0) *
                CAST(i.quantidade_mil / 1000 AS INTEGER)
              )
            ),
            0
          ) AS total_cents
        FROM ${TableNames.pedidosOperacionaisItens} i
        LEFT JOIN (
          SELECT
            pedido_operacional_item_id AS order_item_id,
            COALESCE(SUM(preco_delta_centavos * quantidade), 0) AS total_modifier_delta_cents
          FROM ${TableNames.pedidosOperacionaisItemModificadores}
          GROUP BY pedido_operacional_item_id
        ) mod_agg
          ON mod_agg.order_item_id = i.id
        GROUP BY i.pedido_operacional_id
      ) item_agg
        ON item_agg.order_id = p.id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY
        CASE p.status
          WHEN 'in_preparation' THEN 1
          WHEN 'open' THEN 2
          WHEN 'ready' THEN 3
          WHEN 'draft' THEN 4
          WHEN 'delivered' THEN 5
          WHEN 'canceled' THEN 6
          ELSE 7
        END ASC,
        CASE
          WHEN p.status IN ('in_preparation', 'open', 'ready', 'draft')
            THEN p.criado_em
        END ASC,
        CASE
          WHEN p.status IN ('delivered', 'canceled')
            THEN p.atualizado_em
        END DESC,
        p.id DESC
      ''', args);

    return rows.map(_mapSummary).toList(growable: false);
  }

  @override
  Future<OperationalOrder?> findById(int orderId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.pedidosOperacionais,
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return _mapOrder(rows.first);
  }

  @override
  Future<List<OperationalOrderItem>> listItems(int orderId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        i.*,
        pbv.produto_base_id AS produto_base_id
      FROM ${TableNames.pedidosOperacionaisItens} i
      LEFT JOIN ${TableNames.produtosBaseVariantes} pbv
        ON pbv.produto_id = i.produto_id
      WHERE i.pedido_operacional_id = ?
      ORDER BY i.id ASC
      ''',
      [orderId],
    );
    return rows.map(_mapItem).toList();
  }

  @override
  Future<List<OperationalOrderItemModifier>> listItemModifiers(
    int orderItemId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.pedidosOperacionaisItemModificadores,
      where: 'pedido_operacional_item_id = ?',
      whereArgs: [orderItemId],
      orderBy: 'id ASC',
    );
    return rows.map(_mapModifier).toList();
  }

  @override
  Future<int?> findLinkedSaleId(int orderId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.vendasPedidosOperacionais,
      columns: const ['venda_id'],
      where: 'pedido_operacional_id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['venda_id'] as int?;
  }

  @override
  Future<void> linkToSale({required int orderId, required int saleId}) async {
    final database = await _appDatabase.database;
    final currentOrder = await _requireOrder(database, orderId);
    if (currentOrder.status == OperationalOrderStatus.canceled) {
      throw const ValidationException(
        'Pedido cancelado nao pode ser vinculado a uma venda.',
      );
    }

    final now = DateTime.now().toIso8601String();

    await database.insert(
      TableNames.vendasPedidosOperacionais,
      {
        'uuid': IdGenerator.next(),
        'venda_id': saleId,
        'pedido_operacional_id': orderId,
        'criado_em': now,
        'atualizado_em': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await database.update(
      TableNames.pedidosOperacionais,
      {
        'status': OperationalOrderStatus.delivered.dbValue,
        'atualizado_em': now,
        'fechado_em': now,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  @override
  Future<void> updateStatus(int orderId, OperationalOrderStatus status) async {
    final database = await _appDatabase.database;
    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.status.canTransitionTo(status)) {
      throw ValidationException(
        'Transicao invalida: ${currentOrder.status.dbValue} -> ${status.dbValue}.',
      );
    }

    if (currentOrder.status == status) {
      return;
    }

    final now = DateTime.now();
    final closedAt = status.isTerminal ? now.toIso8601String() : null;

    await database.update(
      TableNames.pedidosOperacionais,
      {
        'status': status.dbValue,
        'atualizado_em': now.toIso8601String(),
        'fechado_em': closedAt,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  @override
  Future<int> addItem(int orderId, OperationalOrderItemInput input) async {
    final database = await _appDatabase.database;
    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.allowsItemChanges) {
      throw const ValidationException(
        'Nao e permitido adicionar itens em pedidos entregues ou cancelados.',
      );
    }

    final now = DateTime.now().toIso8601String();
    final itemId = await database.insert(TableNames.pedidosOperacionaisItens, {
      'uuid': IdGenerator.next(),
      'pedido_operacional_id': orderId,
      'produto_id': input.productId,
      'nome_produto_snapshot': input.productNameSnapshot.trim(),
      'quantidade_mil': input.quantityMil,
      'valor_unitario_centavos': input.unitPriceCents,
      'subtotal_centavos': input.subtotalCents,
      'observacao': _cleanNullable(input.notes),
      'criado_em': now,
      'atualizado_em': now,
    });
    await _touchOrder(database, orderId: orderId, nowIso: now);
    return itemId;
  }

  @override
  Future<int> addItemModifier(
    int orderItemId,
    OperationalOrderItemModifierInput input,
  ) async {
    final database = await _appDatabase.database;
    final orderId = await _findOrderIdByItem(database, orderItemId);
    if (orderId == null) {
      throw const ValidationException(
        'Item do pedido nao encontrado para adicionar modificador.',
      );
    }

    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.allowsItemChanges) {
      throw const ValidationException(
        'Nao e permitido alterar itens em pedidos entregues ou cancelados.',
      );
    }

    final now = DateTime.now().toIso8601String();
    final modifierId = await database
        .insert(TableNames.pedidosOperacionaisItemModificadores, {
          'uuid': IdGenerator.next(),
          'pedido_operacional_item_id': orderItemId,
          'grupo_modificador_id': input.modifierGroupId,
          'opcao_modificador_id': input.modifierOptionId,
          'nome_grupo_snapshot': _cleanNullable(input.groupNameSnapshot),
          'nome_opcao_snapshot': input.optionNameSnapshot.trim(),
          'tipo_ajuste_snapshot': input.adjustmentTypeSnapshot,
          'preco_delta_centavos': input.priceDeltaCents,
          'quantidade': input.quantity,
          'criado_em': now,
          'atualizado_em': now,
        });

    await _touchOrder(database, orderId: orderId, nowIso: now);
    return modifierId;
  }

  OperationalOrder _mapOrder(Map<String, Object?> row) {
    return OperationalOrder(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      status: OperationalOrderStatusX.fromDb(row['status'] as String),
      notes: row['observacao'] as String?,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      closedAt: row['fechado_em'] == null
          ? null
          : DateTime.parse(row['fechado_em'] as String),
    );
  }

  OperationalOrderSummary _mapSummary(Map<String, Object?> row) {
    return OperationalOrderSummary(
      order: _mapOrder(row),
      lineItemsCount: row['line_items_count'] as int? ?? 0,
      totalUnits: row['total_units'] as int? ?? 0,
      totalCents: row['total_cents'] as int? ?? 0,
    );
  }

  OperationalOrderItem _mapItem(Map<String, Object?> row) {
    return OperationalOrderItem(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      orderId: row['pedido_operacional_id'] as int,
      productId: row['produto_id'] as int,
      baseProductId: row['produto_base_id'] as int?,
      productNameSnapshot: row['nome_produto_snapshot'] as String,
      quantityMil: row['quantidade_mil'] as int,
      unitPriceCents: row['valor_unitario_centavos'] as int? ?? 0,
      subtotalCents: row['subtotal_centavos'] as int? ?? 0,
      notes: row['observacao'] as String?,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }

  OperationalOrderItemModifier _mapModifier(Map<String, Object?> row) {
    return OperationalOrderItemModifier(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      orderItemId: row['pedido_operacional_item_id'] as int,
      modifierGroupId: row['grupo_modificador_id'] as int?,
      modifierOptionId: row['opcao_modificador_id'] as int?,
      groupNameSnapshot: row['nome_grupo_snapshot'] as String?,
      optionNameSnapshot: row['nome_opcao_snapshot'] as String,
      adjustmentTypeSnapshot: row['tipo_ajuste_snapshot'] as String,
      priceDeltaCents: row['preco_delta_centavos'] as int? ?? 0,
      quantity: row['quantidade'] as int? ?? 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _touchOrder(
    DatabaseExecutor db, {
    required int orderId,
    required String nowIso,
  }) async {
    await db.update(
      TableNames.pedidosOperacionais,
      {'atualizado_em': nowIso},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<OperationalOrder> _requireOrder(
    DatabaseExecutor database,
    int orderId,
  ) async {
    final rows = await database.query(
      TableNames.pedidosOperacionais,
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ValidationException('Pedido #$orderId nao encontrado.');
    }
    return _mapOrder(rows.first);
  }

  Future<int?> _findOrderIdByItem(
    DatabaseExecutor database,
    int orderItemId,
  ) async {
    final rows = await database.query(
      TableNames.pedidosOperacionaisItens,
      columns: const ['pedido_operacional_id'],
      where: 'id = ?',
      whereArgs: [orderItemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['pedido_operacional_id'] as int?;
  }
}
