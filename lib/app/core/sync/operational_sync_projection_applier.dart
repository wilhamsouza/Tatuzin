import 'package:sqflite/sqflite.dart';

import '../app_context/record_identity.dart';
import '../database/app_database.dart';
import '../database/table_names.dart';
import '../utils/app_logger.dart';
import 'operational_sync_policy.dart';
import 'operational_sync_remote_datasource.dart';
import 'sqlite_sync_metadata_repository.dart';
import 'sync_feature_keys.dart';
import 'sync_status.dart';

const operationalSyncPartialDataMessage = 'Dados parcialmente atualizados';

abstract interface class OperationalSyncProjectionApplier {
  Future<void> apply(OperationalSyncPulledEvent change);
}

class NoopOperationalSyncProjectionApplier
    implements OperationalSyncProjectionApplier {
  const NoopOperationalSyncProjectionApplier();

  @override
  Future<void> apply(OperationalSyncPulledEvent change) async {}
}

class SqliteOperationalSyncProjectionApplier
    implements OperationalSyncProjectionApplier {
  SqliteOperationalSyncProjectionApplier({
    required AppDatabase appDatabase,
    String? companyRemoteId,
  }) : _appDatabase = appDatabase,
       _companyRemoteId = _clean(companyRemoteId),
       _syncMetadataRepository = SqliteSyncMetadataRepository(appDatabase);

  final AppDatabase _appDatabase;
  final String? _companyRemoteId;
  final SqliteSyncMetadataRepository _syncMetadataRepository;

  @override
  Future<void> apply(OperationalSyncPulledEvent change) async {
    if (!_isPdvLocalFirstEntity(change.entity)) {
      AppLogger.warn(
        '[OperationalSync] pull_projection_ignored entity=${change.entity} '
        'eventId=${change.eventId} reason=not_local_first',
      );
      return;
    }

    final projection = change.projection;
    if (projection == null) {
      return;
    }
    _assertSameCompany(projection);

    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      switch (change.entity) {
        case 'cashSession':
          await _applyCashSession(txn, change, projection);
          break;
        case 'cashMovement':
          await _applyCashMovement(txn, change, projection);
          break;
        case 'operationalOrder':
          await _applyOperationalOrder(txn, change, projection);
          break;
        case 'operationalOrderItem':
          await _applyOperationalOrderItem(txn, change, projection);
          break;
        case 'sale':
          await _applySale(txn, change, projection);
          break;
        case 'saleItem':
          await _applySaleItem(txn, change, projection);
          break;
        case 'payment':
          await _applyPayment(txn, change, projection);
          break;
        case 'receipt':
          await _applyReceipt(txn, change, projection);
          break;
        case 'stockReservation':
          await _applyStockReservation(txn, change, projection);
          break;
        case 'stockDeduction':
          await _applyStockDeduction(txn, change, projection);
          break;
      }
    });
  }

  Future<void> _applyCashSession(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final localUuid = _localUuid(change, projection, 'cash-session:$remoteId');
    final openedAt = _iso(projection['openedAt']) ?? change.occurredAtIso;
    final updatedAt =
        _iso(projection['updatedAt']) ??
        _iso(projection['materializedAt']) ??
        change.materializedAt?.toIso8601String() ??
        openedAt;
    final totals = _map(projection['totals']);
    final status = _cashSessionStatus(_string(projection['status']));

    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('cashSession'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.caixaSessoes,
      values: <String, Object?>{
        'uuid': localUuid,
        'usuario_id': null,
        'aberta_em': openedAt,
        'fechada_em': _iso(projection['closedAt']),
        'troco_inicial_centavos': _int(totals['openingBalanceCents']) ?? 0,
        'aguardando_confirmacao_troco_inicial': 0,
        'total_entradas_dinheiro_centavos': 0,
        'total_suprimentos_centavos': 0,
        'total_sangrias_centavos': 0,
        'total_vendas_centavos': 0,
        'total_recebimentos_fiado_centavos': 0,
        'total_recebimentos_fiado_dinheiro_centavos': 0,
        'total_recebimentos_fiado_pix_centavos': 0,
        'total_recebimentos_fiado_cartao_centavos': 0,
        'saldo_esperado_centavos': _int(totals['expectedBalanceCents']) ?? 0,
        'saldo_contado_centavos': _int(totals['closingBalanceCents']),
        'diferenca_centavos': null,
        'saldo_final_centavos':
            _int(totals['closingBalanceCents']) ??
            _int(totals['expectedBalanceCents']) ??
            0,
        'status': status,
        'observacao': null,
      },
      updatedAt: updatedAt,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('cashSession'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: openedAt,
      updatedAtIso: updatedAt,
    );
  }

  Future<void> _applyCashMovement(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final localUuid = _localUuid(change, projection, 'cash-movement:$remoteId');
    final sessionRemoteId = _string(projection['cashSessionId']);
    final sessionId = sessionRemoteId == null
        ? await _findCurrentCashSessionId(db)
        : await _findLocalIdByRemote(
            db,
            _featureForEntity('cashSession'),
            sessionRemoteId,
          );
    if (sessionId == null) {
      throw StateError(
        'Sessao de caixa remota ainda nao existe localmente para movimento.',
      );
    }

    final createdAt = _iso(projection['createdAt']) ?? change.occurredAtIso;
    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('cashMovement'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.caixaMovimentos,
      values: <String, Object?>{
        'uuid': localUuid,
        'sessao_id': sessionId,
        'tipo_movimento': _cashMovementType(_string(projection['type'])),
        'referencia_tipo': null,
        'referencia_id': null,
        'valor_centavos': _int(projection['amountCents']) ?? 0,
        'descricao': _string(projection['reason']),
        'criado_em': createdAt,
      },
      updatedAt: createdAt,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('cashMovement'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: createdAt,
      updatedAtIso: createdAt,
    );
  }

  Future<void> _applyOperationalOrder(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final localUuid = _localUuid(change, projection, 'order:$remoteId');
    final timestamps = _map(projection['timestamps']);
    final createdAt =
        _iso(timestamps['createdAt']) ??
        _iso(projection['createdAt']) ??
        change.occurredAtIso;
    final updatedAt =
        _iso(timestamps['updatedAt']) ??
        _iso(projection['updatedAt']) ??
        change.materializedAt?.toIso8601String() ??
        createdAt;
    final status = _orderStatus(_string(projection['status']));
    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('operationalOrder'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.pedidosOperacionais,
      values: <String, Object?>{
        'uuid': localUuid,
        'status': status,
        'atendimento_tipo': 'counter',
        'cliente_identificador': null,
        'telefone_cliente': null,
        'observacao': null,
        'ticket_status': 'pending',
        'ticket_tentativas': 0,
        'ticket_ultimo_erro': null,
        'ticket_ultima_tentativa_em': null,
        'ticket_enviado_em': null,
        'enviado_cozinha_em': null,
        'em_preparo_em': status == 'in_preparation' ? updatedAt : null,
        'pronto_em': status == 'ready' ? updatedAt : null,
        'entregue_em': status == 'delivered' ? updatedAt : null,
        'cancelado_em': status == 'canceled'
            ? _iso(timestamps['cancelledAt']) ?? updatedAt
            : null,
        'criado_em': createdAt,
        'atualizado_em': updatedAt,
        'fechado_em': _iso(timestamps['closedAt']),
      },
      updatedAt: updatedAt,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('operationalOrder'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: createdAt,
      updatedAtIso: updatedAt,
    );
  }

  Future<void> _applyOperationalOrderItem(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final orderRemoteId = _requiredString(
      projection['operationalOrderId'],
      'operationalOrderId',
    );
    final orderId = await _requireLocalIdByRemote(
      db,
      _featureForEntity('operationalOrder'),
      orderRemoteId,
      'Pedido remoto ainda nao existe localmente para item.',
    );
    final productId = await _resolveProductLocalId(db, projection);
    final productVariantId = await _resolveVariantLocalId(db, projection);
    final localUuid = _localUuid(change, projection, 'order-item:$remoteId');
    final nowIso =
        change.materializedAt?.toIso8601String() ?? change.occurredAtIso;
    final totals = _map(projection['totals']);
    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('operationalOrderItem'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.pedidosOperacionaisItens,
      values: <String, Object?>{
        'uuid': localUuid,
        'pedido_operacional_id': orderId,
        'produto_id': productId,
        'produto_variante_id': productVariantId,
        'nome_produto_snapshot':
            _string(projection['description']) ?? 'Produto',
        'sku_variante_snapshot': null,
        'cor_variante_snapshot': null,
        'tamanho_variante_snapshot': null,
        'quantidade_mil': _int(projection['quantityMil']) ?? 0,
        'valor_unitario_centavos': _int(totals['unitPriceCents']) ?? 0,
        'subtotal_centavos': _int(totals['totalCents']) ?? 0,
        'observacao': null,
        'criado_em': nowIso,
        'atualizado_em': nowIso,
      },
      updatedAt: nowIso,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('operationalOrderItem'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: nowIso,
      updatedAtIso: nowIso,
    );
  }

  Future<void> _applySale(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final localUuid = _localUuid(change, projection, 'sale:$remoteId');
    final totals = _map(projection['total']);
    final soldAt = _iso(projection['soldAt']) ?? change.occurredAtIso;
    final createdAt = _iso(projection['createdAt']) ?? soldAt;
    final amountCents =
        _int(totals['totalAmountCents']) ?? _int(projection['totalCents']) ?? 0;
    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('sale'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.vendas,
      values: <String, Object?>{
        'uuid': localUuid,
        'cliente_id': null,
        'tipo_venda': _saleType(_string(change.payload['paymentType'])),
        'forma_pagamento': _paymentMethod(
          _string(change.payload['paymentMethod']),
        ),
        'status': _saleStatus(_string(projection['status'])),
        'desconto_centavos': 0,
        'acrescimo_centavos': 0,
        'valor_total_centavos': amountCents,
        'valor_final_centavos': amountCents,
        'haver_utilizado_centavos': 0,
        'haver_gerado_centavos': 0,
        'valor_recebido_imediato_centavos': amountCents,
        'numero_cupom':
            _string(projection['receiptNumber']) ??
            _string(change.payload['receiptNumber']) ??
            remoteId,
        'data_venda': soldAt,
        'usuario_id': null,
        'observacao': null,
        'cancelada_em':
            _saleStatus(_string(projection['status'])) == 'cancelada'
            ? (change.materializedAt?.toIso8601String() ?? createdAt)
            : null,
        'venda_origem_id': null,
      },
      updatedAt: createdAt,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('sale'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: createdAt,
      updatedAtIso: createdAt,
    );
  }

  Future<void> _applySaleItem(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final saleRemoteId = _requiredString(projection['saleId'], 'saleId');
    final saleId = await _requireLocalIdByRemote(
      db,
      _featureForEntity('sale'),
      saleRemoteId,
      'Venda remota ainda nao existe localmente para item.',
    );
    final productId = await _resolveProductLocalId(db, projection);
    final productVariantId = await _resolveVariantLocalId(db, projection);
    final localUuid = _localUuid(change, projection, 'sale-item:$remoteId');
    final totals = _map(projection['totals']);
    final nowIso =
        change.materializedAt?.toIso8601String() ?? change.occurredAtIso;
    final totalPriceCents =
        _int(totals['totalPriceCents']) ?? _int(totals['totalCents']) ?? 0;
    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('saleItem'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.itensVenda,
      values: <String, Object?>{
        'uuid': localUuid,
        'venda_id': saleId,
        'produto_id': productId,
        'produto_variante_id': productVariantId,
        'nome_produto_snapshot':
            _string(projection['description']) ?? 'Produto',
        'sku_variante_snapshot': null,
        'cor_variante_snapshot': null,
        'tamanho_variante_snapshot': null,
        'quantidade_mil': _int(projection['quantityMil']) ?? 0,
        'valor_unitario_centavos': _int(totals['unitPriceCents']) ?? 0,
        'subtotal_centavos': totalPriceCents,
        'custo_unitario_centavos': 0,
        'custo_total_centavos': _int(totals['totalCostCents']) ?? 0,
        'unidade_medida_snapshot': 'un',
        'tipo_produto_snapshot': 'unidade',
        'observacao_item_snapshot': null,
      },
      updatedAt: nowIso,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('saleItem'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: nowIso,
      updatedAtIso: nowIso,
    );
  }

  Future<void> _applyPayment(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final saleRemoteId = _string(projection['saleId']);
    final saleId = saleRemoteId == null
        ? null
        : await _findLocalIdByRemote(
            db,
            _featureForEntity('sale'),
            saleRemoteId,
          );
    final sessionId = await _findCurrentCashSessionId(db);
    final createdAt = _iso(projection['createdAt']) ?? change.occurredAtIso;
    if (sessionId == null) {
      await _markRemoteSynced(
        db,
        featureKey: _featureForEntity('payment'),
        localId: 0,
        localUuid: _localUuid(change, projection, 'payment:$remoteId'),
        remoteId: remoteId,
        createdAtIso: createdAt,
        updatedAtIso: createdAt,
      );
      return;
    }

    final localUuid = _localUuid(change, projection, 'payment:$remoteId');
    final localId = await _upsertByRemoteOrUuid(
      db,
      featureKey: _featureForEntity('payment'),
      remoteId: remoteId,
      localUuid: localUuid,
      tableName: TableNames.caixaMovimentos,
      values: <String, Object?>{
        'uuid': localUuid,
        'sessao_id': sessionId,
        'tipo_movimento': saleId == null ? 'recebimento_fiado' : 'venda',
        'referencia_tipo': saleId == null ? null : 'venda',
        'referencia_id': saleId,
        'valor_centavos': _int(projection['amountCents']) ?? 0,
        'descricao': _string(projection['method']),
        'criado_em': createdAt,
      },
      updatedAt: createdAt,
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('payment'),
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: createdAt,
      updatedAtIso: createdAt,
    );
  }

  Future<void> _applyReceipt(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final saleRemoteId = _requiredString(projection['saleId'], 'saleId');
    final saleId = await _requireLocalIdByRemote(
      db,
      _featureForEntity('sale'),
      saleRemoteId,
      'Venda remota ainda nao existe localmente para recibo.',
    );
    final emittedAt = _iso(projection['emittedAt']) ?? change.occurredAtIso;
    await db.update(
      TableNames.vendas,
      {'numero_cupom': _string(projection['receiptNumber']) ?? remoteId},
      where: 'id = ?',
      whereArgs: [saleId],
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('receipt'),
      localId: saleId,
      localUuid: _string(projection['receiptNumber']) ?? 'receipt:$remoteId',
      remoteId: remoteId,
      createdAtIso: emittedAt,
      updatedAtIso: emittedAt,
    );
  }

  Future<void> _applyStockReservation(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final localUuid = _localUuid(change, projection, 'reservation:$remoteId');
    final existingLocalId = await _findLocalIdByRemote(
      db,
      _featureForEntity('stockReservation'),
      remoteId,
    );
    if (existingLocalId != null) {
      await db.update(
        TableNames.estoqueReservas,
        {
          'status': _stockReservationStatus(_string(projection['status'])),
          'quantidade_mil': _int(projection['quantityMil']) ?? 0,
          'atualizado_em':
              change.materializedAt?.toIso8601String() ?? change.occurredAtIso,
        },
        where: 'id = ?',
        whereArgs: [existingLocalId],
      );
      return;
    }

    AppLogger.warn(
      '[OperationalSync] stock_reservation_projection_deferred '
      'eventId=${change.eventId} remoteId=$remoteId reason=missing_order_refs',
    );
    await _markRemoteSynced(
      db,
      featureKey: _featureForEntity('stockReservation'),
      localId: 0,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: change.occurredAtIso,
      updatedAtIso:
          change.materializedAt?.toIso8601String() ?? change.occurredAtIso,
    );
  }

  Future<void> _applyStockDeduction(
    DatabaseExecutor db,
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredRemoteId(change, projection);
    final featureKey = _featureForEntity('stockDeduction');
    final existing = await _findLocalIdByRemote(db, featureKey, remoteId);
    if (existing != null) {
      return;
    }

    final productId = await _resolveProductLocalId(db, projection);
    final productVariantId = await _resolveVariantLocalId(db, projection);
    final quantityMil = _int(projection['quantityMil']) ?? 0;
    if (quantityMil <= 0) {
      return;
    }

    final stockBeforeMil = await _readStockMil(
      db,
      productId: productId,
      productVariantId: productVariantId,
    );
    final stockAfterMil = stockBeforeMil - quantityMil;
    await _writeStockMil(
      db,
      productId: productId,
      productVariantId: productVariantId,
      stockMil: stockAfterMil,
    );

    final localUuid = _localUuid(change, projection, 'deduction:$remoteId');
    final nowIso =
        change.materializedAt?.toIso8601String() ?? change.occurredAtIso;
    await _insertInventoryMovementIfAvailable(
      db,
      uuid: localUuid,
      productId: productId,
      productVariantId: productVariantId,
      quantityDeltaMil: -quantityMil,
      stockBeforeMil: stockBeforeMil,
      stockAfterMil: stockAfterMil,
      remoteSaleId: _string(projection['saleId']),
      createdAt: nowIso,
    );
    await _markRemoteSynced(
      db,
      featureKey: featureKey,
      localId: productVariantId ?? productId,
      localUuid: localUuid,
      remoteId: remoteId,
      createdAtIso: nowIso,
      updatedAtIso: nowIso,
    );
  }

  Future<int> _upsertByRemoteOrUuid(
    DatabaseExecutor db, {
    required String featureKey,
    required String remoteId,
    required String localUuid,
    required String tableName,
    required Map<String, Object?> values,
    required String updatedAt,
  }) async {
    final localId =
        await _findLocalIdByRemote(db, featureKey, remoteId) ??
        await _findIdByUuid(db, tableName, localUuid);
    if (localId == null || localId <= 0) {
      return db.insert(
        tableName,
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    final updateValues = Map<String, Object?>.of(values)..remove('uuid');
    await db.update(
      tableName,
      updateValues,
      where: 'id = ?',
      whereArgs: [localId],
    );
    return localId;
  }

  Future<void> _markRemoteSynced(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String remoteId,
    required String createdAtIso,
    required String updatedAtIso,
  }) async {
    if (localId <= 0) {
      await _markRemoteOnlySynced(
        db,
        featureKey: featureKey,
        remoteId: remoteId,
        localUuid: localUuid,
        createdAtIso: createdAtIso,
        updatedAtIso: updatedAtIso,
      );
      return;
    }
    await _syncMetadataRepository.saveExplicit(
      db,
      featureKey: featureKey,
      localId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      status: SyncStatus.synced,
      origin: RecordOrigin.remote,
      createdAt: DateTime.tryParse(createdAtIso) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAtIso) ?? DateTime.now(),
      lastSyncedAt: DateTime.now(),
    );
  }

  Future<void> _markRemoteOnlySynced(
    DatabaseExecutor db, {
    required String featureKey,
    required String localUuid,
    required String remoteId,
    required String createdAtIso,
    required String updatedAtIso,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final existing = await _syncMetadataRepository.findByRemoteId(
      db,
      featureKey: featureKey,
      remoteId: remoteId,
    );
    final values = <String, Object?>{
      'feature_key': featureKey,
      'local_id': null,
      'local_uuid': localUuid,
      'remote_id': remoteId,
      'sync_status': SyncStatus.synced.storageValue,
      'origin': recordOriginToStorage(RecordOrigin.remote),
      'created_at': createdAtIso,
      'updated_at': updatedAtIso,
      'last_synced_at': nowIso,
      'last_error': null,
      'last_error_type': null,
      'last_error_at': null,
    };
    if (existing == null) {
      await db.insert(TableNames.syncRegistros, values);
      return;
    }
    await db.update(
      TableNames.syncRegistros,
      values,
      where: 'feature_key = ? AND remote_id = ?',
      whereArgs: [featureKey, remoteId],
    );
  }

  Future<int?> _findIdByUuid(
    DatabaseExecutor db,
    String tableName,
    String uuid,
  ) async {
    final rows = await db.query(
      tableName,
      columns: const ['id'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<int?> _findLocalIdByRemote(
    DatabaseExecutor db,
    String featureKey,
    String remoteId,
  ) async {
    final metadata = await _syncMetadataRepository.findByRemoteId(
      db,
      featureKey: featureKey,
      remoteId: remoteId,
    );
    return metadata?.identity.localId;
  }

  Future<int> _requireLocalIdByRemote(
    DatabaseExecutor db,
    String featureKey,
    String remoteId,
    String message,
  ) async {
    final localId = await _findLocalIdByRemote(db, featureKey, remoteId);
    if (localId == null || localId <= 0) {
      throw StateError(message);
    }
    return localId;
  }

  Future<int> _resolveProductLocalId(
    DatabaseExecutor db,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _requiredString(projection['productId'], 'productId');
    return _requireLocalIdByRemote(
      db,
      SyncFeatureKeys.products,
      remoteId,
      'Produto remoto ainda nao existe no catalogo local.',
    );
  }

  Future<int?> _resolveVariantLocalId(
    DatabaseExecutor db,
    Map<String, dynamic> projection,
  ) async {
    final remoteId = _string(projection['productVariantId']);
    if (remoteId == null) {
      return null;
    }
    final rows = await db.query(
      TableNames.produtoVariantes,
      columns: const ['id'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Variante remota ainda nao existe no catalogo local.');
    }
    return rows.first['id'] as int?;
  }

  Future<int?> _findCurrentCashSessionId(DatabaseExecutor db) async {
    final rows = await db.query(
      TableNames.caixaSessoes,
      columns: const ['id'],
      where: 'status = ?',
      whereArgs: const ['aberto'],
      orderBy: 'aberta_em DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<int> _readStockMil(
    DatabaseExecutor db, {
    required int productId,
    required int? productVariantId,
  }) async {
    final rows = productVariantId == null
        ? await db.query(
            TableNames.produtos,
            columns: const ['estoque_mil'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          )
        : await db.query(
            TableNames.produtoVariantes,
            columns: const ['estoque_mil'],
            where: 'id = ?',
            whereArgs: [productVariantId],
            limit: 1,
          );
    if (rows.isEmpty) {
      throw StateError('Produto de estoque nao encontrado localmente.');
    }
    return rows.first['estoque_mil'] as int? ?? 0;
  }

  Future<void> _writeStockMil(
    DatabaseExecutor db, {
    required int productId,
    required int? productVariantId,
    required int stockMil,
  }) {
    if (productVariantId == null) {
      return db.update(
        TableNames.produtos,
        {
          'estoque_mil': stockMil,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [productId],
      );
    }
    return db.update(
      TableNames.produtoVariantes,
      {
        'estoque_mil': stockMil,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productVariantId],
    );
  }

  Future<void> _insertInventoryMovementIfAvailable(
    DatabaseExecutor db, {
    required String uuid,
    required int productId,
    required int? productVariantId,
    required int quantityDeltaMil,
    required int stockBeforeMil,
    required int stockAfterMil,
    required String? remoteSaleId,
    required String createdAt,
  }) async {
    if (!await _tableExists(db, TableNames.inventoryMovements)) {
      return;
    }
    await db.insert(TableNames.inventoryMovements, {
      'uuid': uuid,
      'product_id': productId,
      'product_variant_id': productVariantId,
      'movement_type': 'sale_out',
      'quantity_delta_mil': quantityDeltaMil,
      'stock_before_mil': stockBeforeMil,
      'stock_after_mil': stockAfterMil,
      'reference_type': 'sale',
      'reference_id': remoteSaleId == null ? null : 0,
      'reason': null,
      'notes': 'Baixa aplicada pela sincronizacao operacional.',
      'created_at': createdAt,
      'updated_at': createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  void _assertSameCompany(Map<String, dynamic> projection) {
    final projectionCompanyId = _string(projection['companyId']);
    if (_companyRemoteId == null || projectionCompanyId == null) {
      return;
    }
    if (projectionCompanyId != _companyRemoteId) {
      throw StateError('Projection de outra empresa bloqueada.');
    }
  }

  bool _isPdvLocalFirstEntity(String entity) {
    return OperationalSyncPolicy.isLocalFirstEntity(entity) &&
        !OperationalSyncPolicy.blockedServerFirstEntities.contains(entity);
  }

  String _requiredRemoteId(
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
  ) {
    return _string(projection['entityServerId']) ??
        _string(projection['id']) ??
        change.entityServerId ??
        (throw StateError('Change sem entityServerId remoto.'));
  }

  String _localUuid(
    OperationalSyncPulledEvent change,
    Map<String, dynamic> projection,
    String fallback,
  ) {
    return _clean(_string(projection['localUuid'])) ??
        _clean(change.entityLocalId) ??
        _stableUuid(fallback);
  }

  String _requiredString(Object? value, String field) {
    final string = _string(value);
    if (string == null) {
      throw StateError('Projection sem $field remoto.');
    }
    return string;
  }

  String _stableUuid(String value) {
    return 'remote:${value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9:_-]+'), '_')}';
  }

  String _featureForEntity(String entity) {
    switch (entity) {
      case 'cashSession':
        return 'cash_sessions';
      case 'cashMovement':
        return SyncFeatureKeys.cashEvents;
      case 'operationalOrder':
        return 'operational_orders';
      case 'operationalOrderItem':
        return 'operational_order_items';
      case 'sale':
        return SyncFeatureKeys.sales;
      case 'saleItem':
        return 'sale_items';
      case 'payment':
        return SyncFeatureKeys.financialEvents;
      case 'receipt':
        return 'receipts';
      case 'stockReservation':
        return 'stock_reservations';
      case 'stockDeduction':
        return 'stock_deductions';
      default:
        return entity;
    }
  }

  String _cashSessionStatus(String? status) {
    return switch (status) {
      'closed' || 'fechado' => 'fechado',
      _ => 'aberto',
    };
  }

  String _cashMovementType(String? type) {
    return switch (type) {
      'saida' || 'retirada' || 'withdrawal' || 'sangria' => 'sangria',
      'fiado_pagamento' || 'recebimento_fiado' => 'recebimento_fiado',
      'venda' || 'sale' => 'venda',
      'cancelamento' || 'cancellation' => 'cancelamento',
      _ => 'suprimento',
    };
  }

  String _orderStatus(String? status) {
    return switch (status) {
      'open' => 'open',
      'in_preparation' => 'in_preparation',
      'ready' => 'ready',
      'delivered' => 'delivered',
      'canceled' || 'cancelled' => 'canceled',
      _ => 'draft',
    };
  }

  String _saleStatus(String? status) {
    return switch (status) {
      'canceled' || 'cancelled' || 'cancelada' => 'cancelada',
      _ => 'ativa',
    };
  }

  String _saleType(String? value) {
    return switch (value) {
      'fiado' => 'fiado',
      _ => 'vista',
    };
  }

  String _paymentMethod(String? value) {
    return switch (value) {
      'pix' => 'pix',
      'cartao' || 'card' => 'cartao',
      'fiado' => 'fiado',
      _ => 'dinheiro',
    };
  }

  String _stockReservationStatus(String? status) {
    return switch (status) {
      'released' => 'released',
      'converted' => 'converted',
      _ => 'active',
    };
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  String? _string(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return _clean(value);
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }

  int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String? _iso(Object? value) {
    final raw = _string(value);
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw)?.toIso8601String() ?? raw;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

extension on OperationalSyncPulledEvent {
  String get occurredAtIso => occurredAt.toIso8601String();
}
