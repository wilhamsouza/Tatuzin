import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/network/contracts/api_client_contract.dart';
import 'package:tatuzin/app/core/sync/operational_sync_event.dart';
import 'package:tatuzin/app/core/sync/sqlite_operational_sync_queue_repository.dart';
import 'package:tatuzin/modules/estoque/data/central_inventory_api.dart';
import 'package:tatuzin/modules/estoque/data/confirmed_inventory_mirror.dart';
import 'package:tatuzin/modules/estoque/data/sqlite_stock_availability_repository.dart';
import 'package:tatuzin/modules/estoque/data/support/central_stock_refresh_support.dart';
import 'package:tatuzin/modules/produtos/data/models/remote_product_record.dart';
import 'package:tatuzin/modules/produtos/data/sqlite_product_repository.dart';
import 'central_inventory_api_test.dart'
    show InventoryTestClient, InventoryTestTokens;

RemoteProductRecord _remote({bool variant = false}) =>
    RemoteProductRecord.fromJson({
      'id': 'remote-product',
      'localUuid': 'local-product',
      'name': 'Produto de teste',
      'catalogRevision': 1,
      'stockMil': 0,
      'salePriceCents': 500,
      'costPriceCents': 100,
      'niche': 'moda',
      'catalogType': variant ? 'variant' : 'simple',
      'modelName': variant ? 'Camisa' : null,
      'variantLabel': variant ? 'Cor/tamanho' : null,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
      'variants': variant
          ? [
              {
                'id': 'remote-variant',
                'sku': 'CAM-P',
                'colorLabel': 'Azul',
                'sizeLabel': 'P',
                'stockMil': 0,
                'isActive': true,
              },
            ]
          : [],
    });

class _QuantityClient extends InventoryTestClient {
  int freshQuantity = 5000;
  bool loseNextResponse = false;
  final reads = <String>[];
  @override
  Future<ApiResponse<InventoryJson>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    reads.add(path);
    if (path.startsWith('/inventory/items/')) {
      return ApiResponse(
        statusCode: 200,
        data: {
          'item': {
            'productId': 'remote-product',
            'productVariantId': null,
            'currentStockMil': freshQuantity,
          },
        },
        headers: const {},
      );
    }
    return super.getJson(path, options: options);
  }

  @override
  Future<ApiResponse<InventoryJson>> postJson(
    String path, {
    InventoryJson? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    writes.add({'path': path, 'body': body});
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const NetworkRequestException('Conexão interrompida após o envio');
    }
    return const ApiResponse(
      statusCode: 200,
      data: {
        'item': {
          'productId': 'remote-product',
          'productVariantId': null,
          'currentStockMil': 5000,
        },
      },
      headers: {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late AppDatabase app;
  late SqliteProductRepository products;
  late ConfirmedInventoryMirror mirror;
  late String isolation;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    isolation = 'remote:mirror-${DateTime.now().microsecondsSinceEpoch}';
    app = AppDatabase.forIsolationKey(isolation);
    await app.database;
    products = SqliteProductRepository(app);
    mirror = ConfirmedInventoryMirror(app);
  });
  tearDown(() async {
    await app.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolation);
  });
  test(
    'resultado incerto bloqueia PDV e resolve com a mesma identidade após reiniciar',
    () async {
      await products.upsertFromRemote(_remote());
      final product = (await products.findByRemoteId('remote-product'))!;
      final client = _QuantityClient()..loseNextResponse = true;
      CentralInventoryApi createApi() => CentralInventoryApi(
        client: client,
        tokens: InventoryTestTokens(),
        namespace: isolation,
        userId: 'operator',
        canWrite: true,
        prepareWrite: () async {},
        ensureCurrent: () {},
        pendingLocalRefresh: () async => (await mirror.pending()).isNotEmpty,
        onQuantityPending: (_, body) => mirror.stageIntent(
          [
            {'productId': body['productId'], 'productVariantId': null},
          ],
          body['requestId'] as String,
          ensureCurrent: () {},
        ),
        onQuantityResolved: (id) =>
            mirror.resolveIntent(id, ensureCurrent: () {}),
        onQuantityCommitted: (response) async {
          if (response != null) {
            await mirror.stage([inventoryJson(response['item'])]);
          }
          return mirror.refreshPending(
            prepare: () async {},
            fetchCurrent: (target) async => inventoryJson(
              (await client.getJson(
                '/inventory/items/${target['productId']}',
              )).data['item'],
            ),
            ensureCurrent: () {},
          );
        },
      );
      final body = {
        'requestId': inventoryRequestId(),
        'productId': 'remote-product',
        'quantityDeltaMil': 5000,
      };
      await expectLater(
        createApi().write('POST', '/adjustments', body),
        throwsA(isA<NetworkRequestException>()),
      );
      expect(await mirror.applyPending(ensureCurrent: () {}), isFalse);
      await expectLater(
        SqliteStockAvailabilityRepository(
          app,
        ).getAvailability(productId: product.id, productVariantId: null),
        throwsA(isA<ValidationException>()),
      );
      client.freshQuantity = 4000; // The stored response still says 5000.
      final restarted = createApi();
      expect(await restarted.hasPendingLocalRefresh(), isTrue);
      expect(await restarted.refreshLocalStock(), isTrue);
      expect(client.writes, hasLength(2));
      expect(client.writes.first['body'], client.writes.last['body']);
      expect((await products.findByRemoteId('remote-product'))!.stockMil, 4000);
      expect(await restarted.hasPendingLocalRefresh(), isFalse);
    },
  );
  test(
    'saldo inicial confirmado fica disponível no SQLite do PDV sem depender de products.read',
    () async {
      await products.upsertFromRemote(_remote());
      final client = _QuantityClient();
      final api = CentralInventoryApi(
        client: client,
        tokens: InventoryTestTokens(),
        namespace: isolation,
        userId: 'operator',
        canWrite: true,
        prepareWrite: () async {},
        ensureCurrent: () {},
        onQuantityCommitted: (result) async {
          await mirror.stage([inventoryJson(result!['item'])]);
          return mirror.refreshPending(
            prepare: () async {},
            fetchCurrent: (target) async => inventoryJson(
              (await client.getJson(
                '/inventory/items/${target['productId']}',
              )).data['item'],
            ),
            ensureCurrent: () {},
          );
        },
      );
      final result = await api.write('POST', '/initial-balances', {
        'requestId': inventoryRequestId(),
        'quantityDeltaMil': 5000,
      });
      expect(result['localRefreshPending'], isFalse);
      final item = (await products.findByRemoteId('remote-product'))!;
      final availability = await SqliteStockAvailabilityRepository(
        app,
      ).getAvailability(productId: item.id, productVariantId: null);
      expect(availability.availableQuantityMil, 5000);
      expect(client.writes, hasLength(1));
      expect(await mirror.pending(), isEmpty);
    },
  );
  test(
    'retorno idempotente antigo nunca aumenta saldo sobre venda já sincronizada',
    () async {
      await products.upsertFromRemote(_remote());
      final client = _QuantityClient()..freshQuantity = 4000;
      final product = (await products.findByRemoteId('remote-product'))!;
      await (await app.database).update(
        TableNames.produtos,
        {'estoque_mil': 4000},
        where: 'id = ?',
        whereArgs: [product.id],
      );
      final api = CentralInventoryApi(
        client: client,
        tokens: InventoryTestTokens(),
        namespace: isolation,
        userId: 'operator',
        canWrite: true,
        prepareWrite: () async {},
        ensureCurrent: () {},
        onQuantityCommitted: (result) async {
          await mirror.stage([inventoryJson(result!['item'])]);
          return mirror.refreshPending(
            prepare: () async {},
            fetchCurrent: (target) async => inventoryJson(
              (await client.getJson(
                '/inventory/items/${target['productId']}',
              )).data['item'],
            ),
            ensureCurrent: () {},
          );
        },
      );
      final confirmed = await api.write('POST', '/adjustments', {
        'requestId': inventoryRequestId(),
      });
      expect(inventoryJson(confirmed['item'])['currentStockMil'], 5000);
      expect(confirmed['localRefreshPending'], isFalse);
      expect((await products.findByRemoteId('remote-product'))!.stockMil, 4000);
      expect(client.writes, hasLength(1));
      expect(client.reads, contains('/inventory/items/remote-product'));
    },
  );
  test(
    'espelhamento da variante preserva identidade e recompõe saldo do pai',
    () async {
      await products.upsertFromRemote(_remote(variant: true));
      final before = (await products.findByRemoteId('remote-product'))!;
      await mirror.stage([
        {
          'productId': 'remote-product',
          'productVariantId': 'remote-variant',
          'currentStockMil': 4000,
          'costCents': 9999,
          'actorName': 'não persistir',
        },
      ]);
      expect((await mirror.pending()).single.keys.toSet(), {
        'productId',
        'productVariantId',
        'currentStockMil',
      });
      expect(await mirror.applyPending(ensureCurrent: () {}), isTrue);
      final after = (await products.findByRemoteId('remote-product'))!;
      expect(after.variants.single.id, before.variants.single.id);
      expect(after.variants.single.stockMil, 4000);
      expect(after.stockMil, 4000);
    },
  );
  test(
    'retry após sincronizar usa saldo fresco e não reintroduz o recibo antigo',
    () async {
      await products.upsertFromRemote(_remote());
      final db = await app.database;
      final product = (await products.findByRemoteId('remote-product'))!;
      await db.update(
        TableNames.produtos,
        {'estoque_mil': 3000},
        where: 'id = ?',
        whereArgs: [product.id],
      );
      final queue = SqliteOperationalSyncQueueRepository(app);
      await queue.enqueue(
        db,
        event: OperationalSyncEvent(
          eventId: 'pending-sale',
          feature: 'pdv',
          entity: 'sale',
          operation: 'create',
          occurredAt: DateTime.now(),
          payload: const {},
        ),
      );
      await mirror.stage([
        {
          'productId': 'remote-product',
          'productVariantId': null,
          'currentStockMil': 5000,
        },
      ]);
      expect(await mirror.applyPending(ensureCurrent: () {}), isFalse);
      expect((await products.findByRemoteId('remote-product'))!.stockMil, 3000);
      final order = <String>[];
      final complete = await mirror.refreshPending(
        prepare: () async {
          order.add('sync');
          await queue.markAccepted(
            eventId: 'pending-sale',
            serverVersion: '1',
            processedAt: DateTime.now(),
          );
        },
        fetchCurrent: (target) async {
          order.add('fresh-get');
          return {...target, 'currentStockMil': 4000};
        },
        ensureCurrent: () {},
      );
      expect(complete, isTrue);
      expect(order, ['sync', 'fresh-get']);
      expect((await products.findByRemoteId('remote-product'))!.stockMil, 4000);
      expect(await mirror.pending(), isEmpty);
    },
  );
  test('falha de refresh mantém confirmação e retry não repete POST', () async {
    await products.upsertFromRemote(_remote());
    final client = _QuantityClient();
    var retry = false;
    final api = CentralInventoryApi(
      client: client,
      tokens: InventoryTestTokens(),
      namespace: isolation,
      userId: 'operator',
      canWrite: true,
      prepareWrite: () async {},
      ensureCurrent: () {},
      onQuantityCommitted: (result) async {
        if (result != null) {
          await mirror.stage([inventoryJson(result['item'])]);
          throw const NetworkRequestException('Refresh interrompido');
        }
        retry = true;
        return mirror.applyPending(ensureCurrent: () {});
      },
    );
    final confirmed = await api.write('POST', '/adjustments', {
      'requestId': inventoryRequestId(),
    });
    expect(confirmed['localRefreshPending'], isTrue);
    expect(client.writes, hasLength(1));
    expect(await api.refreshLocalStock(), isTrue);
    expect(retry, isTrue);
    expect(client.writes, hasLength(1));
  });
  test(
    'marcador é por banco da empresa e bloqueia leitura de disponibilidade até espelhar',
    () async {
      await products.upsertFromRemote(_remote());
      final product = (await products.findByRemoteId('remote-product'))!;
      await mirror.stage([
        {
          'productId': 'remote-product',
          'productVariantId': null,
          'currentStockMil': 5000,
        },
      ]);
      final sameCompanyOtherOperator = ConfirmedInventoryMirror(app);
      expect(await sameCompanyOtherOperator.pending(), hasLength(1));
      await expectLater(
        SqliteStockAvailabilityRepository(
          app,
        ).getAvailability(productId: product.id, productVariantId: null),
        throwsA(isA<ValidationException>()),
      );
      final other = AppDatabase.forIsolationKey('remote:other-$isolation');
      try {
        expect(await ConfirmedInventoryMirror(other).pending(), isEmpty);
      } finally {
        await other.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          'remote:other-$isolation',
        );
      }
      expect(await mirror.applyPending(ensureCurrent: () {}), isTrue);
      await CentralStockRefreshSupport.assertReady(await app.database);
    },
  );
  test('mudança de sessão impede gravar o snapshot em transação', () async {
    await products.upsertFromRemote(_remote());
    await mirror.stage([
      {
        'productId': 'remote-product',
        'productVariantId': null,
        'currentStockMil': 5000,
      },
    ]);
    await expectLater(
      mirror.applyPending(
        ensureCurrent: () {
          throw const ValidationException('Sessão mudou');
        },
      ),
      throwsA(isA<ValidationException>()),
    );
    expect((await products.findByRemoteId('remote-product'))!.stockMil, 0);
  });
}
