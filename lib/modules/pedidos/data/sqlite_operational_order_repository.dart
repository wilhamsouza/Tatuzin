import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../estoque/domain/entities/stock_reservation.dart';
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
    final nowIso = DateTime.now().toIso8601String();
    return database.insert(TableNames.pedidosOperacionais, {
      'uuid': IdGenerator.next(),
      'status': input.status.dbValue,
      'atendimento_tipo': input.serviceType.dbValue,
      'cliente_identificador': _cleanNullable(input.customerIdentifier),
      'telefone_cliente': _cleanNullable(input.customerPhone),
      'observacao': _cleanNullable(input.notes),
      'ticket_status': OrderTicketDispatchStatus.pending.dbValue,
      'ticket_tentativas': 0,
      'ticket_ultimo_erro': null,
      'ticket_ultima_tentativa_em': null,
      'ticket_enviado_em': null,
      'enviado_cozinha_em': null,
      'em_preparo_em': null,
      'pronto_em': null,
      'entregue_em': null,
      'cancelado_em': null,
      'criado_em': nowIso,
      'atualizado_em': nowIso,
      'fechado_em': null,
    });
  }

  @override
  Future<List<OperationalOrder>> list({String query = ''}) async {
    final summaries = await listSummaries(query: query);
    return summaries.map((summary) => summary.order).toList(growable: false);
  }

  @override
  Future<List<OperationalOrderSummary>> listSummaries({
    String query = '',
    OperationalOrderStatus? status,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info('[PedidosSQLite] listSummaries database started');
    final database = await _appDatabase.database;
    AppLogger.info(
      '[PedidosSQLite] listSummaries database finished | duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    final trimmed = query.trim();
    final like = '%$trimmed%';
    final args = <Object?>[];
    final where = <String>[];

    if (trimmed.isNotEmpty) {
      where.add(
        '('
        'CAST(p.id AS TEXT) LIKE ? '
        'OR COALESCE(p.cliente_identificador, "") LIKE ? COLLATE NOCASE '
        'OR COALESCE(p.telefone_cliente, "") LIKE ? COLLATE NOCASE '
        'OR COALESCE(p.atendimento_tipo, "") LIKE ? COLLATE NOCASE '
        'OR CASE p.atendimento_tipo '
        '    WHEN "counter" THEN "balcao" '
        '    WHEN "pickup" THEN "retirada" '
        '    WHEN "delivery" THEN "delivery" '
        '    WHEN "table" THEN "mesa" '
        '    ELSE "" '
        '  END LIKE ? COLLATE NOCASE '
        'OR EXISTS ('
        '  SELECT 1 '
        '  FROM ${TableNames.pedidosOperacionaisItens} i2 '
        '  WHERE i2.pedido_operacional_id = p.id '
        '    AND COALESCE(i2.nome_produto_snapshot, "") LIKE ? COLLATE NOCASE'
        ')'
        ')',
      );
      args.addAll(<Object?>[like, like, like, like, like, like]);
    }

    if (status != null) {
      where.add('p.status = ?');
      args.add(status.dbValue);
    }

    AppLogger.info('[PedidosSQLite] listSummaries rawQuery started');
    final rows = await database.rawQuery('''
      SELECT
        p.*,
        vpo.venda_id AS linked_sale_id,
        COALESCE(item_agg.line_items_count, 0) AS line_items_count,
        COALESCE(item_agg.total_units, 0) AS total_units,
        COALESCE(item_agg.total_cents, 0) AS total_cents
      FROM ${TableNames.pedidosOperacionais} p
      LEFT JOIN ${TableNames.vendasPedidosOperacionais} vpo
        ON vpo.pedido_operacional_id = p.id
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
            COALESCE(SUM(preco_delta_centavos * quantidade), 0)
              AS total_modifier_delta_cents
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
          WHEN 'open' THEN 1
          WHEN 'in_preparation' THEN 2
          WHEN 'ready' THEN 3
          WHEN 'draft' THEN 4
          WHEN 'delivered' THEN 5
          WHEN 'canceled' THEN 6
          ELSE 7
        END ASC,
        CASE
          WHEN p.status IN ('draft', 'open', 'in_preparation', 'ready')
            THEN p.criado_em
        END ASC,
        CASE
          WHEN p.status IN ('delivered', 'canceled')
            THEN p.atualizado_em
        END DESC,
        p.id DESC
    ''', args);
    AppLogger.info(
      '[PedidosSQLite] listSummaries rawQuery finished: ${rows.length} rows | duration_ms=${stopwatch.elapsedMilliseconds}',
    );

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
    return _listItems(database, orderId);
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
    return rows.map(_mapModifier).toList(growable: false);
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

    final nowIso = DateTime.now().toIso8601String();

    await database.insert(
      TableNames.vendasPedidosOperacionais,
      {
        'uuid': IdGenerator.next(),
        'venda_id': saleId,
        'pedido_operacional_id': orderId,
        'criado_em': nowIso,
        'atualizado_em': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await database.update(
      TableNames.pedidosOperacionais,
      {
        'status': OperationalOrderStatus.delivered.dbValue,
        'entregue_em': nowIso,
        'atualizado_em': nowIso,
        'fechado_em': nowIso,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  @override
  Future<void> updateDraft(
    int orderId,
    OperationalOrderDraftInput input,
  ) async {
    final database = await _appDatabase.database;
    final currentOrder = await _requireOrder(database, orderId);
    if (currentOrder.isTerminal) {
      throw const ValidationException(
        'Pedido encerrado nao pode ser alterado.',
      );
    }

    await database.update(
      TableNames.pedidosOperacionais,
      {
        'atendimento_tipo': input.serviceType.dbValue,
        'cliente_identificador': _cleanNullable(input.customerIdentifier),
        'telefone_cliente': _cleanNullable(input.customerPhone),
        'observacao': _cleanNullable(input.notes),
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  @override
  Future<void> sendToKitchen(int orderId) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final currentOrder = await _requireOrder(txn, orderId);
      if (currentOrder.status == OperationalOrderStatus.open) {
        return;
      }
      if (!currentOrder.status.canTransitionTo(OperationalOrderStatus.open)) {
        throw ValidationException(
          'Pedido #$orderId nao pode ser enviado para separacao neste status.',
        );
      }

      final items = await _listItems(txn, orderId);
      if (items.isEmpty) {
        throw const ValidationException(
          'Adicione pelo menos um item antes de enviar o pedido para a separacao.',
        );
      }

      final nowIso = DateTime.now().toIso8601String();
      await _createMissingStockReservations(
        txn,
        orderId: orderId,
        items: items,
        nowIso: nowIso,
      );

      await txn.update(
        TableNames.pedidosOperacionais,
        {
          'status': OperationalOrderStatus.open.dbValue,
          'enviado_cozinha_em': nowIso,
          'atualizado_em': nowIso,
          'fechado_em': null,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  @override
  Future<void> updateStatus(int orderId, OperationalOrderStatus status) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final currentOrder = await _requireOrder(txn, orderId);
      if (!currentOrder.status.canTransitionTo(status)) {
        throw ValidationException(
          'Transicao invalida: ${currentOrder.status.dbValue} -> ${status.dbValue}.',
        );
      }

      if (currentOrder.status == status) {
        return;
      }

      final nowIso = DateTime.now().toIso8601String();
      final payload = <String, Object?>{
        'status': status.dbValue,
        'atualizado_em': nowIso,
        'fechado_em': status.isTerminal ? nowIso : null,
      };

      switch (status) {
        case OperationalOrderStatus.draft:
          break;
        case OperationalOrderStatus.open:
          payload['enviado_cozinha_em'] =
              currentOrder.sentToKitchenAt?.toIso8601String() ?? nowIso;
          break;
        case OperationalOrderStatus.inPreparation:
          payload['em_preparo_em'] = nowIso;
          break;
        case OperationalOrderStatus.ready:
          payload['pronto_em'] = nowIso;
          break;
        case OperationalOrderStatus.delivered:
          payload['entregue_em'] = nowIso;
          break;
        case OperationalOrderStatus.canceled:
          payload['cancelado_em'] = nowIso;
          await _releaseActiveReservationsByOrderId(
            txn,
            orderId: orderId,
            nowIso: nowIso,
          );
          break;
      }

      await txn.update(
        TableNames.pedidosOperacionais,
        payload,
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  @override
  Future<void> updateTicketDispatchState({
    required int orderId,
    required OrderTicketDispatchStatus status,
    String? failureMessage,
  }) async {
    final database = await _appDatabase.database;
    await _requireOrder(database, orderId);
    final nowIso = DateTime.now().toIso8601String();

    await database.rawUpdate(
      '''
      UPDATE ${TableNames.pedidosOperacionais}
      SET
        ticket_status = ?,
        ticket_tentativas = COALESCE(ticket_tentativas, 0) + 1,
        ticket_ultima_tentativa_em = ?,
        ticket_enviado_em = CASE
          WHEN ? = 'sent' THEN ?
          ELSE ticket_enviado_em
        END,
        ticket_ultimo_erro = CASE
          WHEN ? = 'failed' THEN ?
          ELSE NULL
        END,
        atualizado_em = ?
      WHERE id = ?
      ''',
      <Object?>[
        status.dbValue,
        nowIso,
        status.dbValue,
        nowIso,
        status.dbValue,
        _cleanNullable(failureMessage),
        nowIso,
        orderId,
      ],
    );
  }

  @override
  Future<int> addItem(int orderId, OperationalOrderItemInput input) async {
    final database = await _appDatabase.database;
    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.allowsItemChanges) {
      throw const ValidationException(
        'Nao e permitido adicionar itens neste pedido.',
      );
    }

    final nowIso = DateTime.now().toIso8601String();
    final itemId = await database.insert(TableNames.pedidosOperacionaisItens, {
      'uuid': IdGenerator.next(),
      'pedido_operacional_id': orderId,
      'produto_id': input.productId,
      'produto_variante_id': input.productVariantId,
      'nome_produto_snapshot': input.productNameSnapshot.trim(),
      'sku_variante_snapshot': _cleanNullable(input.variantSkuSnapshot),
      'cor_variante_snapshot': _cleanNullable(input.variantColorSnapshot),
      'tamanho_variante_snapshot': _cleanNullable(input.variantSizeSnapshot),
      'quantidade_mil': input.quantityMil,
      'valor_unitario_centavos': input.unitPriceCents,
      'subtotal_centavos': input.subtotalCents,
      'observacao': _cleanNullable(input.notes),
      'criado_em': nowIso,
      'atualizado_em': nowIso,
    });
    await _touchOrder(database, orderId: orderId, nowIso: nowIso);
    return itemId;
  }

  @override
  Future<void> updateItem(
    int orderItemId,
    OperationalOrderItemInput input,
  ) async {
    final database = await _appDatabase.database;
    final orderId = await _findOrderIdByItem(database, orderItemId);
    if (orderId == null) {
      throw const ValidationException('Item do pedido nao encontrado.');
    }

    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.allowsItemChanges) {
      throw const ValidationException(
        'Nao e permitido editar itens neste pedido.',
      );
    }

    final nowIso = DateTime.now().toIso8601String();
    await database.update(
      TableNames.pedidosOperacionaisItens,
      {
        'produto_id': input.productId,
        'produto_variante_id': input.productVariantId,
        'nome_produto_snapshot': input.productNameSnapshot.trim(),
        'sku_variante_snapshot': _cleanNullable(input.variantSkuSnapshot),
        'cor_variante_snapshot': _cleanNullable(input.variantColorSnapshot),
        'tamanho_variante_snapshot': _cleanNullable(input.variantSizeSnapshot),
        'quantidade_mil': input.quantityMil,
        'valor_unitario_centavos': input.unitPriceCents,
        'subtotal_centavos': input.subtotalCents,
        'observacao': _cleanNullable(input.notes),
        'atualizado_em': nowIso,
      },
      where: 'id = ?',
      whereArgs: [orderItemId],
    );
    await _touchOrder(database, orderId: orderId, nowIso: nowIso);
  }

  @override
  Future<void> removeItem(int orderItemId) async {
    final database = await _appDatabase.database;
    final orderId = await _findOrderIdByItem(database, orderItemId);
    if (orderId == null) {
      throw const ValidationException('Item do pedido nao encontrado.');
    }

    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.allowsItemChanges) {
      throw const ValidationException(
        'Nao e permitido remover itens neste pedido.',
      );
    }

    final nowIso = DateTime.now().toIso8601String();
    await database.delete(
      TableNames.pedidosOperacionaisItens,
      where: 'id = ?',
      whereArgs: [orderItemId],
    );
    await _touchOrder(database, orderId: orderId, nowIso: nowIso);
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
        'Nao e permitido alterar itens neste pedido.',
      );
    }

    final nowIso = DateTime.now().toIso8601String();
    final modifierId = await _insertModifier(
      database,
      orderItemId: orderItemId,
      input: input,
      nowIso: nowIso,
    );
    await _touchOrder(database, orderId: orderId, nowIso: nowIso);
    return modifierId;
  }

  @override
  Future<void> replaceItemModifiers(
    int orderItemId,
    List<OperationalOrderItemModifierInput> modifiers,
  ) async {
    final database = await _appDatabase.database;
    final orderId = await _findOrderIdByItem(database, orderItemId);
    if (orderId == null) {
      throw const ValidationException('Item do pedido nao encontrado.');
    }

    final currentOrder = await _requireOrder(database, orderId);
    if (!currentOrder.allowsItemChanges) {
      throw const ValidationException(
        'Nao e permitido alterar itens neste pedido.',
      );
    }

    final nowIso = DateTime.now().toIso8601String();
    await database.transaction((txn) async {
      await txn.delete(
        TableNames.pedidosOperacionaisItemModificadores,
        where: 'pedido_operacional_item_id = ?',
        whereArgs: [orderItemId],
      );
      for (final modifier in modifiers) {
        await _insertModifier(
          txn,
          orderItemId: orderItemId,
          input: modifier,
          nowIso: nowIso,
        );
      }
      await _touchOrder(txn, orderId: orderId, nowIso: nowIso);
    });
  }

  OperationalOrder _mapOrder(Map<String, Object?> row) {
    return OperationalOrder(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      status: OperationalOrderStatusX.fromDb(row['status'] as String),
      serviceType: OperationalOrderServiceTypeX.fromDb(
        row['atendimento_tipo'] as String?,
      ),
      customerIdentifier: row['cliente_identificador'] as String?,
      customerPhone: row['telefone_cliente'] as String?,
      notes: row['observacao'] as String?,
      ticketMeta: OperationalOrderTicketMeta(
        status: OrderTicketDispatchStatusX.fromDb(
          row['ticket_status'] as String?,
        ),
        dispatchAttempts: row['ticket_tentativas'] as int? ?? 0,
        lastAttemptAt: _parseDateTime(row['ticket_ultima_tentativa_em']),
        lastSentAt: _parseDateTime(row['ticket_enviado_em']),
        lastFailureMessage: row['ticket_ultimo_erro'] as String?,
      ),
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      sentToKitchenAt: _parseDateTime(row['enviado_cozinha_em']),
      preparationStartedAt: _parseDateTime(row['em_preparo_em']),
      readyAt: _parseDateTime(row['pronto_em']),
      deliveredAt: _parseDateTime(row['entregue_em']),
      canceledAt: _parseDateTime(row['cancelado_em']),
      closedAt: _parseDateTime(row['fechado_em']),
    );
  }

  OperationalOrderSummary _mapSummary(Map<String, Object?> row) {
    return OperationalOrderSummary(
      order: _mapOrder(row),
      lineItemsCount: row['line_items_count'] as int? ?? 0,
      totalUnits: row['total_units'] as int? ?? 0,
      totalCents: row['total_cents'] as int? ?? 0,
      linkedSaleId: row['linked_sale_id'] as int?,
    );
  }

  OperationalOrderItem _mapItem(Map<String, Object?> row) {
    return OperationalOrderItem(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      orderId: row['pedido_operacional_id'] as int,
      productId: row['produto_id'] as int,
      baseProductId: row['produto_base_id'] as int?,
      productVariantId: row['produto_variante_id'] as int?,
      variantSkuSnapshot: row['sku_variante_snapshot'] as String?,
      variantColorSnapshot: row['cor_variante_snapshot'] as String?,
      variantSizeSnapshot: row['tamanho_variante_snapshot'] as String?,
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

  DateTime? _parseDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.parse(raw);
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

  Future<List<OperationalOrderItem>> _listItems(
    DatabaseExecutor database,
    int orderId,
  ) async {
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
    return rows.map(_mapItem).toList(growable: false);
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

  Future<void> _createMissingStockReservations(
    DatabaseExecutor database, {
    required int orderId,
    required List<OperationalOrderItem> items,
    required String nowIso,
  }) async {
    final activeReservationsByItemId =
        await _loadActiveReservationQuantityByItemId(
          database,
          items.map((item) => item.id),
        );
    final existingQuantityByKey = <_StockReservationKey, int>{};
    final quantityToReserveByKey = <_StockReservationKey, int>{};

    for (final item in items) {
      if (item.quantityMil <= 0) {
        throw ValidationException(
          'Quantidade invalida para reservar ${item.productNameSnapshot}.',
        );
      }

      final key = _StockReservationKey(
        productId: item.productId,
        productVariantId: item.productVariantId,
      );
      final existingQuantityMil = activeReservationsByItemId[item.id];
      if (existingQuantityMil != null) {
        existingQuantityByKey[key] =
            (existingQuantityByKey[key] ?? 0) + existingQuantityMil;
      } else {
        quantityToReserveByKey[key] =
            (quantityToReserveByKey[key] ?? 0) + item.quantityMil;
      }
    }

    for (final entry in quantityToReserveByKey.entries) {
      final key = entry.key;
      final quantityToReserveMil = entry.value;
      final physicalQuantityMil = await _loadPhysicalQuantityMil(database, key);
      final activeReservedQuantityMil = await _loadActiveReservedQuantityMil(
        database,
        key,
      );
      final alreadyReservedByThisOrderMil = existingQuantityByKey[key] ?? 0;
      final availableQuantityMil =
          physicalQuantityMil -
          (activeReservedQuantityMil - alreadyReservedByThisOrderMil);

      if (quantityToReserveMil > availableQuantityMil) {
        final sampleItem = items.firstWhere(
          (item) =>
              item.productId == key.productId &&
              item.productVariantId == key.productVariantId,
        );
        throw ValidationException(
          _buildInsufficientStockMessage(
            sampleItem,
            availableQuantityMil: availableQuantityMil < 0
                ? 0
                : availableQuantityMil,
            requestedQuantityMil: quantityToReserveMil,
          ),
        );
      }
    }

    for (final item in items) {
      if (activeReservationsByItemId.containsKey(item.id)) {
        continue;
      }
      await database.insert(TableNames.estoqueReservas, {
        'uuid': IdGenerator.next(),
        'pedido_operacional_id': orderId,
        'item_pedido_operacional_id': item.id,
        'produto_id': item.productId,
        'produto_variante_id': item.productVariantId,
        'quantidade_mil': item.quantityMil,
        'status': StockReservationStatus.active.storageValue,
        'venda_id': null,
        'criado_em': nowIso,
        'atualizado_em': nowIso,
        'liberado_em': null,
        'convertido_em_venda_em': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<Map<int, int>> _loadActiveReservationQuantityByItemId(
    DatabaseExecutor database,
    Iterable<int> itemIds,
  ) async {
    final ids = itemIds.toList(growable: false);
    if (ids.isEmpty) {
      return const {};
    }

    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await database.rawQuery(
      '''
      SELECT item_pedido_operacional_id, quantidade_mil
      FROM ${TableNames.estoqueReservas}
      WHERE status = ?
        AND item_pedido_operacional_id IN ($placeholders)
      ''',
      <Object?>[StockReservationStatus.active.storageValue, ...ids],
    );

    return {
      for (final row in rows)
        row['item_pedido_operacional_id'] as int:
            row['quantidade_mil'] as int? ?? 0,
    };
  }

  Future<void> _releaseActiveReservationsByOrderId(
    DatabaseExecutor database, {
    required int orderId,
    required String nowIso,
  }) async {
    await database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.released.storageValue,
        'atualizado_em': nowIso,
        'liberado_em': nowIso,
      },
      where: 'pedido_operacional_id = ? AND status = ?',
      whereArgs: [orderId, StockReservationStatus.active.storageValue],
    );
  }

  Future<int> _loadPhysicalQuantityMil(
    DatabaseExecutor database,
    _StockReservationKey key,
  ) async {
    if (key.productVariantId == null) {
      final rows = await database.query(
        TableNames.produtos,
        columns: const ['estoque_mil'],
        where: 'id = ?',
        whereArgs: [key.productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ValidationException('Produto #${key.productId} nao encontrado.');
      }
      return rows.first['estoque_mil'] as int? ?? 0;
    }

    final rows = await database.query(
      TableNames.produtoVariantes,
      columns: const ['estoque_mil'],
      where: 'id = ? AND produto_id = ?',
      whereArgs: [key.productVariantId, key.productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ValidationException(
        'Variante #${key.productVariantId} do produto #${key.productId} nao encontrada.',
      );
    }
    return rows.first['estoque_mil'] as int? ?? 0;
  }

  Future<int> _loadActiveReservedQuantityMil(
    DatabaseExecutor database,
    _StockReservationKey key,
  ) async {
    final rows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(quantidade_mil), 0) AS total
      FROM ${TableNames.estoqueReservas}
      WHERE produto_id = ?
        AND status = ?
        AND ${key.productVariantId == null ? 'produto_variante_id IS NULL' : 'produto_variante_id = ?'}
      ''',
      <Object?>[
        key.productId,
        StockReservationStatus.active.storageValue,
        if (key.productVariantId != null) key.productVariantId,
      ],
    );
    return rows.first['total'] as int? ?? 0;
  }

  String _buildInsufficientStockMessage(
    OperationalOrderItem item, {
    required int availableQuantityMil,
    required int requestedQuantityMil,
  }) {
    return 'Estoque insuficiente para ${_itemStockLabel(item)}. '
        'Disponivel: ${_formatQuantityMil(availableQuantityMil)}; '
        'solicitado: ${_formatQuantityMil(requestedQuantityMil)}.';
  }

  String _itemStockLabel(OperationalOrderItem item) {
    final details = <String>[
      if (_cleanNullable(item.variantSkuSnapshot) != null)
        'SKU: ${item.variantSkuSnapshot!.trim()}',
      if (_cleanNullable(item.variantColorSnapshot) != null)
        'Cor: ${item.variantColorSnapshot!.trim()}',
      if (_cleanNullable(item.variantSizeSnapshot) != null)
        'Tam: ${item.variantSizeSnapshot!.trim()}',
    ];
    if (details.isEmpty) {
      return item.productNameSnapshot;
    }
    return '${item.productNameSnapshot} (${details.join(' - ')})';
  }

  String _formatQuantityMil(int quantityMil) {
    if (quantityMil % 1000 == 0) {
      return (quantityMil ~/ 1000).toString();
    }
    return (quantityMil / 1000).toStringAsFixed(3);
  }

  Future<int> _insertModifier(
    DatabaseExecutor database, {
    required int orderItemId,
    required OperationalOrderItemModifierInput input,
    required String nowIso,
  }) {
    return database.insert(TableNames.pedidosOperacionaisItemModificadores, {
      'uuid': IdGenerator.next(),
      'pedido_operacional_item_id': orderItemId,
      'grupo_modificador_id': input.modifierGroupId,
      'opcao_modificador_id': input.modifierOptionId,
      'nome_grupo_snapshot': _cleanNullable(input.groupNameSnapshot),
      'nome_opcao_snapshot': input.optionNameSnapshot.trim(),
      'tipo_ajuste_snapshot': input.adjustmentTypeSnapshot,
      'preco_delta_centavos': input.priceDeltaCents,
      'quantidade': input.quantity,
      'criado_em': nowIso,
      'atualizado_em': nowIso,
    });
  }
}

class _StockReservationKey {
  const _StockReservationKey({
    required this.productId,
    required this.productVariantId,
  });

  final int productId;
  final int? productVariantId;

  @override
  bool operator ==(Object other) {
    return other is _StockReservationKey &&
        other.productId == productId &&
        other.productVariantId == productVariantId;
  }

  @override
  int get hashCode => Object.hash(productId, productVariantId);
}
