import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/sync/operational_sync_projection_applier.dart';
import 'package:tatuzin/app/core/sync/operational_sync_remote_datasource.dart';
import 'package:tatuzin/app/core/sync/sync_feature_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('device B aplica sale criada por device A via projection', () async {
    final appDatabase = _newIsolatedDatabase('sale');
    addTearDown(() => _disposeIsolatedDatabase(appDatabase));
    final db = await appDatabase.database;
    final applier = SqliteOperationalSyncProjectionApplier(
      appDatabase: appDatabase,
      companyRemoteId: 'company-1',
    );

    await applier.apply(
      _change(
        entity: 'sale',
        eventId: 'sale-created-device-a',
        serverVersion: '10',
        entityServerId: 'sale-server-1',
        projection: <String, dynamic>{
          'companyId': 'company-1',
          'entityServerId': 'sale-server-1',
          'id': 'sale-server-1',
          'localUuid': 'sale-local-a',
          'status': 'active',
          'total': <String, dynamic>{
            'totalAmountCents': 2400,
            'totalCostCents': 900,
          },
          'receiptNumber': 'R-001',
          'soldAt': '2026-05-05T10:00:00.000Z',
          'createdAt': '2026-05-05T10:00:00.000Z',
        },
      ),
    );

    final sales = await db.query(TableNames.vendas);
    expect(sales, hasLength(1));
    expect(sales.single['uuid'], 'sale-local-a');
    expect(sales.single['numero_cupom'], 'R-001');
    expect(sales.single['valor_final_centavos'], 2400);
  });

  test(
    'device B preserva subtotal, desconto e tipo da venda quando o payload operacional traz esses dados',
    () async {
      final appDatabase = _newIsolatedDatabase('sale-discount');
      addTearDown(() => _disposeIsolatedDatabase(appDatabase));
      final db = await appDatabase.database;
      final applier = SqliteOperationalSyncProjectionApplier(
        appDatabase: appDatabase,
        companyRemoteId: 'company-1',
      );

      await applier.apply(
        _change(
          entity: 'sale',
          eventId: 'sale-discount-device-a',
          serverVersion: '11',
          entityServerId: 'sale-server-2',
          payload: <String, dynamic>{
            'saleType': 'fiado',
            'paymentMethod': 'fiado',
            'subtotalCents': 10000,
            'discountCents': 1000,
            'totalCents': 9000,
          },
          projection: <String, dynamic>{
            'companyId': 'company-1',
            'entityServerId': 'sale-server-2',
            'id': 'sale-server-2',
            'localUuid': 'sale-local-b',
            'status': 'active',
            'total': <String, dynamic>{
              'totalAmountCents': 9000,
              'totalCostCents': 2500,
            },
            'receiptNumber': 'R-002',
            'soldAt': '2026-05-05T10:05:00.000Z',
            'createdAt': '2026-05-05T10:05:00.000Z',
          },
        ),
      );

      final sales = await db.query(TableNames.vendas);
      expect(sales, hasLength(1));
      expect(sales.single['tipo_venda'], 'fiado');
      expect(sales.single['forma_pagamento'], 'fiado');
      expect(sales.single['desconto_centavos'], 1000);
      expect(sales.single['valor_total_centavos'], 10000);
      expect(sales.single['valor_final_centavos'], 9000);
    },
  );

  test(
    'device B preserva o recebido imediato real quando o payload operacional traz immediateReceivedCents',
    () async {
      final appDatabase = _newIsolatedDatabase('sale-immediate-received');
      addTearDown(() => _disposeIsolatedDatabase(appDatabase));
      final db = await appDatabase.database;
      final applier = SqliteOperationalSyncProjectionApplier(
        appDatabase: appDatabase,
        companyRemoteId: 'company-1',
      );

      await applier.apply(
        _change(
          entity: 'sale',
          eventId: 'sale-immediate-device-a',
          serverVersion: '12',
          entityServerId: 'sale-server-3',
          payload: <String, dynamic>{
            'saleType': 'vista',
            'paymentMethod': 'dinheiro',
            'subtotalCents': 10000,
            'discountCents': 3000,
            'creditGeneratedCents': 3000,
            'immediateReceivedCents': 10000,
            'totalCents': 7000,
          },
          projection: <String, dynamic>{
            'companyId': 'company-1',
            'entityServerId': 'sale-server-3',
            'id': 'sale-server-3',
            'localUuid': 'sale-local-c',
            'status': 'active',
            'total': <String, dynamic>{'totalAmountCents': 7000},
            'receiptNumber': 'R-003',
            'soldAt': '2026-05-05T10:10:00.000Z',
            'createdAt': '2026-05-05T10:10:00.000Z',
          },
        ),
      );

      final sales = await db.query(TableNames.vendas);
      expect(sales, hasLength(1));
      expect(sales.single['valor_final_centavos'], 7000);
      expect(sales.single['valor_recebido_imediato_centavos'], 10000);
      expect(sales.single['haver_gerado_centavos'], 3000);
    },
  );

  test(
    'payment remoto atualiza o recebido imediato da venda mesmo sem sessao aberta localmente',
    () async {
      final appDatabase = _newIsolatedDatabase('payment-without-session');
      addTearDown(() => _disposeIsolatedDatabase(appDatabase));
      final db = await appDatabase.database;
      final applier = SqliteOperationalSyncProjectionApplier(
        appDatabase: appDatabase,
        companyRemoteId: 'company-1',
      );

      await applier.apply(
        _change(
          entity: 'sale',
          eventId: 'sale-before-payment',
          serverVersion: '13',
          entityServerId: 'sale-server-4',
          payload: <String, dynamic>{
            'saleType': 'vista',
            'paymentMethod': 'pix',
            'immediateReceivedCents': 0,
            'totalCents': 7000,
          },
          projection: <String, dynamic>{
            'companyId': 'company-1',
            'entityServerId': 'sale-server-4',
            'id': 'sale-server-4',
            'localUuid': 'sale-local-d',
            'status': 'active',
            'total': <String, dynamic>{'totalAmountCents': 7000},
            'receiptNumber': 'R-004',
            'soldAt': '2026-05-05T10:15:00.000Z',
            'createdAt': '2026-05-05T10:15:00.000Z',
          },
        ),
      );

      await applier.apply(
        _change(
          entity: 'payment',
          eventId: 'payment-without-open-session',
          serverVersion: '14',
          entityServerId: 'payment-server-1',
          payload: <String, dynamic>{'paymentMethod': 'pix', 'amountCents': 7000},
          projection: <String, dynamic>{
            'companyId': 'company-1',
            'entityServerId': 'payment-server-1',
            'id': 'payment-server-1',
            'saleId': 'sale-server-4',
            'amountCents': 7000,
            'paymentMethod': 'pix',
            'createdAt': '2026-05-05T10:16:00.000Z',
          },
        ),
      );

      final sales = await db.query(TableNames.vendas);
      final paymentRows = await db.query(
        TableNames.caixaMovimentos,
        where: 'uuid = ?',
        whereArgs: const ['payment:payment-server-1'],
      );
      expect(sales.single['valor_recebido_imediato_centavos'], 7000);
      expect(paymentRows, isEmpty);
    },
  );

  test('device B aplica operationalOrder criada por device A', () async {
    final appDatabase = _newIsolatedDatabase('order');
    addTearDown(() => _disposeIsolatedDatabase(appDatabase));
    final db = await appDatabase.database;
    final applier = SqliteOperationalSyncProjectionApplier(
      appDatabase: appDatabase,
    );

    await _seedProduct(db, productId: 1, remoteId: 'product-server-1');
    await applier.apply(
      _change(
        entity: 'operationalOrder',
        eventId: 'order-created-device-a',
        serverVersion: '20',
        entityServerId: 'order-server-1',
        projection: <String, dynamic>{
          'entityServerId': 'order-server-1',
          'id': 'order-server-1',
          'localUuid': 'order-local-a',
          'status': 'open',
          'totals': <String, dynamic>{'totalCents': 5000},
          'timestamps': <String, dynamic>{
            'createdAt': '2026-05-05T10:00:00.000Z',
            'updatedAt': '2026-05-05T10:01:00.000Z',
          },
        },
      ),
    );
    await applier.apply(
      _change(
        entity: 'operationalOrderItem',
        eventId: 'order-item-created-device-a',
        serverVersion: '21',
        entityServerId: 'order-item-server-1',
        projection: <String, dynamic>{
          'entityServerId': 'order-item-server-1',
          'id': 'order-item-server-1',
          'operationalOrderId': 'order-server-1',
          'productId': 'product-server-1',
          'description': 'Cafe',
          'quantityMil': 2000,
          'totals': <String, dynamic>{
            'unitPriceCents': 2500,
            'totalCents': 5000,
          },
        },
      ),
    );

    final orders = await db.query(TableNames.pedidosOperacionais);
    final items = await db.query(TableNames.pedidosOperacionaisItens);
    expect(orders, hasLength(1));
    expect(orders.single['uuid'], 'order-local-a');
    expect(orders.single['status'], 'open');
    expect(items, hasLength(1));
    expect(items.single['pedido_operacional_id'], orders.single['id']);
    expect(items.single['nome_produto_snapshot'], 'Cafe');
  });

  test('device B aplica cashSession e cashMovement', () async {
    final appDatabase = _newIsolatedDatabase('cash');
    addTearDown(() => _disposeIsolatedDatabase(appDatabase));
    final db = await appDatabase.database;
    final applier = SqliteOperationalSyncProjectionApplier(
      appDatabase: appDatabase,
    );

    await applier.apply(
      _change(
        entity: 'cashSession',
        eventId: 'cash-session-created-device-a',
        serverVersion: '30',
        entityServerId: 'cash-session-server-1',
        projection: <String, dynamic>{
          'entityServerId': 'cash-session-server-1',
          'id': 'cash-session-server-1',
          'localUuid': 'cash-session-local-a',
          'status': 'open',
          'openedAt': '2026-05-05T09:00:00.000Z',
          'totals': <String, dynamic>{'openingBalanceCents': 1000},
          'createdAt': '2026-05-05T09:00:00.000Z',
          'updatedAt': '2026-05-05T09:00:00.000Z',
        },
      ),
    );
    await applier.apply(
      _change(
        entity: 'cashMovement',
        eventId: 'cash-movement-created-device-a',
        serverVersion: '31',
        entityServerId: 'cash-movement-server-1',
        projection: <String, dynamic>{
          'entityServerId': 'cash-movement-server-1',
          'id': 'cash-movement-server-1',
          'cashSessionId': 'cash-session-server-1',
          'type': 'entrada',
          'amountCents': 1500,
          'reason': 'Entrada inicial',
          'createdAt': '2026-05-05T09:10:00.000Z',
        },
      ),
    );

    final sessions = await db.query(TableNames.caixaSessoes);
    final movements = await db.query(TableNames.caixaMovimentos);
    expect(sessions, hasLength(1));
    expect(movements, hasLength(1));
    expect(movements.single['sessao_id'], sessions.single['id']);
    expect(movements.single['valor_centavos'], 1500);
  });

  test('cashMovement sem cashSessionId remoto nao derruba a materializacao', () async {
    final appDatabase = _newIsolatedDatabase('cash-null-session');
    addTearDown(() => _disposeIsolatedDatabase(appDatabase));
    final db = await appDatabase.database;
    final applier = SqliteOperationalSyncProjectionApplier(
      appDatabase: appDatabase,
    );

    await applier.apply(
      _change(
        entity: 'cashMovement',
        eventId: 'cash-movement-without-session',
        serverVersion: '32',
        entityServerId: 'cash-movement-server-2',
        projection: <String, dynamic>{
          'entityServerId': 'cash-movement-server-2',
          'id': 'cash-movement-server-2',
          'cashSessionId': null,
          'type': 'venda',
          'amountCents': 2200,
          'reason': 'Movimento antigo sem sessao',
          'createdAt': '2026-05-05T09:20:00.000Z',
        },
      ),
    );

    final movements = await db.query(TableNames.caixaMovimentos);
    final syncRows = await db.query(
      TableNames.syncRegistros,
      where: 'feature_key = ? AND remote_id = ?',
      whereArgs: const <Object?>[
        SyncFeatureKeys.cashEvents,
        'cash-movement-server-2',
      ],
    );
    expect(movements, isEmpty);
    expect(syncRows, hasLength(1));
    expect(syncRows.single['local_id'], isNull);
  });

  test('stockDeduction altera estoque local e e idempotente', () async {
    final appDatabase = _newIsolatedDatabase('stock-deduction');
    addTearDown(() => _disposeIsolatedDatabase(appDatabase));
    final db = await appDatabase.database;
    final applier = SqliteOperationalSyncProjectionApplier(
      appDatabase: appDatabase,
    );
    await _seedProduct(
      db,
      productId: 1,
      remoteId: 'product-server-1',
      stockMil: 10000,
    );
    final change = _change(
      entity: 'stockDeduction',
      eventId: 'stock-deduction-device-a',
      serverVersion: '40',
      entityServerId: 'deduction-server-1',
      projection: <String, dynamic>{
        'entityServerId': 'deduction-server-1',
        'id': 'deduction-server-1',
        'saleId': 'sale-server-1',
        'productId': 'product-server-1',
        'quantityMil': 2000,
      },
    );

    await applier.apply(change);
    await applier.apply(change);

    final products = await db.query(TableNames.produtos, where: 'id = 1');
    final movements = await db.query(TableNames.inventoryMovements);
    expect(products.single['estoque_mil'], 8000);
    expect(movements, hasLength(1));
    expect(movements.single['quantity_delta_mil'], -2000);
  });
}

final _isolationKeys = <AppDatabase, String>{};

AppDatabase _newIsolatedDatabase(String label) {
  final isolationKey =
      'projection-$label-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  _isolationKeys[appDatabase] = isolationKey;
  return appDatabase;
}

Future<void> _disposeIsolatedDatabase(AppDatabase appDatabase) async {
  final isolationKey = _isolationKeys.remove(appDatabase);
  await appDatabase.close();
  if (isolationKey != null) {
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}

OperationalSyncPulledEvent _change({
  required String entity,
  required String eventId,
  required String serverVersion,
  required String entityServerId,
  required Map<String, dynamic> projection,
  Map<String, dynamic> payload = const <String, dynamic>{},
}) {
  return OperationalSyncPulledEvent(
    eventId: eventId,
    feature: 'pdv',
    entity: entity,
    operation: 'create',
    entityLocalId: '$eventId-local',
    entityServerId: entityServerId,
    occurredAt: DateTime(2026, 5, 5, 10),
    payload: payload,
    serverVersion: serverVersion,
    materializedAt: DateTime(2026, 5, 5, 10, 1),
    projection: projection,
  );
}

Future<void> _seedProduct(
  dynamic db, {
  required int productId,
  required String remoteId,
  int stockMil = 0,
}) async {
  const now = '2026-05-05T08:00:00.000Z';
  await db.insert(TableNames.produtos, {
    'id': productId,
    'uuid': 'product-$productId',
    'nome': 'Produto $productId',
    'descricao': null,
    'categoria_id': null,
    'foto_path': null,
    'codigo_barras': null,
    'tipo_produto': 'unidade',
    'unidade_medida': 'un',
    'custo_centavos': 100,
    'preco_venda_centavos': 1000,
    'estoque_mil': stockMil,
    'ativo': 1,
    'criado_em': now,
    'atualizado_em': now,
    'deletado_em': null,
  });
  await db.insert(TableNames.syncRegistros, {
    'feature_key': SyncFeatureKeys.products,
    'local_id': productId,
    'local_uuid': 'product-$productId',
    'remote_id': remoteId,
    'sync_status': 'synced',
    'origin': 'remote',
    'created_at': now,
    'updated_at': now,
    'last_synced_at': now,
    'last_error': null,
    'last_error_type': null,
    'last_error_at': null,
  });
}
