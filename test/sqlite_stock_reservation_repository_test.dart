import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/migrations.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_stock_reservation_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('migration v35 cria tabela estoque_reservas', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AppMigrations.runCreate(db, 34),
      ),
    );
    addTearDown(database.close);

    await AppMigrations.runUpgrade(database, 34, 35);

    final columns = await database.rawQuery(
      'PRAGMA table_info(${TableNames.estoqueReservas})',
    );
    final columnNames = columns.map((row) => row['name']).toSet();

    expect(columnNames, contains('id'));
    expect(columnNames, contains('uuid'));
    expect(columnNames, contains('pedido_operacional_id'));
    expect(columnNames, contains('item_pedido_operacional_id'));
    expect(columnNames, contains('produto_id'));
    expect(columnNames, contains('produto_variante_id'));
    expect(columnNames, contains('quantidade_mil'));
    expect(columnNames, contains('status'));
    expect(columnNames, contains('venda_id'));
    expect(columnNames, contains('criado_em'));
    expect(columnNames, contains('atualizado_em'));
    expect(columnNames, contains('liberado_em'));
    expect(columnNames, contains('convertido_em_venda_em'));
  });

  test('migration v35 cria indices principais', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AppMigrations.runCreate(db, 34),
      ),
    );
    addTearDown(database.close);

    await AppMigrations.runUpgrade(database, 34, 35);

    final indexRows = await database.rawQuery(
      'PRAGMA index_list(${TableNames.estoqueReservas})',
    );
    final indexNames = indexRows.map((row) => row['name']).toSet();

    expect(indexNames, contains('idx_estoque_reservas_pedido'));
    expect(indexNames, contains('idx_estoque_reservas_item'));
    expect(indexNames, contains('idx_estoque_reservas_produto_status'));
    expect(indexNames, contains('idx_estoque_reservas_item_active_unique'));
  });

  test('cria reserva ativa e busca por pedido', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);

    final orderItemId = await fixture.insertOrderItem(productId: 1);

    await fixture.repository.createReservation(
      StockReservationInput(
        operationalOrderId: fixture.orderId,
        operationalOrderItemId: orderItemId,
        productId: 1,
        productVariantId: null,
        quantityMil: 1000,
      ),
    );

    final reservations = await fixture.repository.findActiveByOrderId(
      fixture.orderId,
    );

    expect(reservations, hasLength(1));
    expect(reservations.single.operationalOrderItemId, orderItemId);
    expect(reservations.single.status, StockReservationStatus.active);
    expect(reservations.single.quantityMil, 1000);
  });

  test('getReservedQuantityMil soma somente reservas active', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);

    final activeItemId = await fixture.insertOrderItem(productId: 1);
    final releasedItemId = await fixture.insertOrderItem(productId: 1);
    final convertedItemId = await fixture.insertOrderItem(productId: 1);

    await fixture.repository.createReservation(
      StockReservationInput(
        operationalOrderId: fixture.orderId,
        operationalOrderItemId: activeItemId,
        productId: 1,
        productVariantId: null,
        quantityMil: 1000,
      ),
    );
    final releasedReservationId = await fixture.repository.createReservation(
      StockReservationInput(
        operationalOrderId: fixture.orderId,
        operationalOrderItemId: releasedItemId,
        productId: 1,
        productVariantId: null,
        quantityMil: 2000,
      ),
    );
    final convertedReservationId = await fixture.repository.createReservation(
      StockReservationInput(
        operationalOrderId: fixture.orderId,
        operationalOrderItemId: convertedItemId,
        productId: 1,
        productVariantId: null,
        quantityMil: 3000,
      ),
    );
    await fixture.repository.releaseReservation(releasedReservationId);
    final saleId = await fixture.insertSale();
    await fixture.repository.markConverted(convertedReservationId, saleId);

    final reserved = await fixture.repository.getReservedQuantityMil(
      productId: 1,
      productVariantId: null,
    );

    expect(reserved, 1000);
  });

  test('nao permite duas reservas active para o mesmo item', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);

    final orderItemId = await fixture.insertOrderItem(productId: 1);
    final input = StockReservationInput(
      operationalOrderId: fixture.orderId,
      operationalOrderItemId: orderItemId,
      productId: 1,
      productVariantId: null,
      quantityMil: 1000,
    );

    await fixture.repository.createReservation(input);

    expect(
      () => fixture.repository.createReservation(input),
      throwsA(isA<ValidationException>()),
    );
  });

  test('nao permite reserva com quantidade menor ou igual a zero', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);

    final orderItemId = await fixture.insertOrderItem(productId: 1);

    expect(
      () => fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: orderItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 0,
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
    'releaseActiveByOrderId libera somente reservas active do pedido',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);

      final activeItemId = await fixture.insertOrderItem(productId: 1);
      final releasedItemId = await fixture.insertOrderItem(productId: 1);
      final convertedItemId = await fixture.insertOrderItem(productId: 1);
      await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: activeItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 1000,
        ),
      );
      final releasedReservationId = await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: releasedItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 2000,
        ),
      );
      final convertedReservationId = await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: convertedItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 3000,
        ),
      );
      await fixture.repository.releaseReservation(releasedReservationId);
      final saleId = await fixture.insertSale();
      await fixture.repository.markConverted(convertedReservationId, saleId);

      await fixture.repository.releaseActiveByOrderId(fixture.orderId);

      final rows = await fixture.allReservations();
      final activeRow = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == activeItemId,
      );
      final releasedRow = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == releasedItemId,
      );
      final convertedRow = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == convertedItemId,
      );

      expect(activeRow['status'], StockReservationStatus.released.storageValue);
      expect(activeRow['liberado_em'], isNotNull);
      expect(
        releasedRow['status'],
        StockReservationStatus.released.storageValue,
      );
      expect(
        convertedRow['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(convertedRow['convertido_em_venda_em'], isNotNull);
    },
  );

  test(
    'markActiveByOrderIdConverted converte somente reservas active do pedido',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);

      final activeItemId = await fixture.insertOrderItem(productId: 1);
      final releasedItemId = await fixture.insertOrderItem(productId: 1);
      final convertedItemId = await fixture.insertOrderItem(productId: 1);
      await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: activeItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 1000,
        ),
      );
      final releasedReservationId = await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: releasedItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 2000,
        ),
      );
      final convertedReservationId = await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: convertedItemId,
          productId: 1,
          productVariantId: null,
          quantityMil: 3000,
        ),
      );
      await fixture.repository.releaseReservation(releasedReservationId);
      final previousSaleId = await fixture.insertSale();
      await fixture.repository.markConverted(
        convertedReservationId,
        previousSaleId,
      );
      final saleId = await fixture.insertSale();

      await fixture.repository.markActiveByOrderIdConverted(
        fixture.orderId,
        saleId,
      );

      final rows = await fixture.allReservations();
      final activeRow = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == activeItemId,
      );
      final releasedRow = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == releasedItemId,
      );
      final convertedRow = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == convertedItemId,
      );

      expect(
        activeRow['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(activeRow['venda_id'], saleId);
      expect(activeRow['convertido_em_venda_em'], isNotNull);
      expect(
        releasedRow['status'],
        StockReservationStatus.released.storageValue,
      );
      expect(releasedRow['venda_id'], isNull);
      expect(
        convertedRow['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(convertedRow['venda_id'], previousSaleId);
    },
  );

  test('produto simples sem variante funciona', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);

    final orderItemId = await fixture.insertOrderItem(productId: 1);

    await fixture.repository.createReservation(
      StockReservationInput(
        operationalOrderId: fixture.orderId,
        operationalOrderItemId: orderItemId,
        productId: 1,
        productVariantId: null,
        quantityMil: 2000,
      ),
    );

    expect(
      await fixture.repository.getReservedQuantityMil(
        productId: 1,
        productVariantId: null,
      ),
      2000,
    );
    expect(
      await fixture.repository.findActiveByOrderItemId(orderItemId),
      isNotNull,
    );
  });

  test(
    'produto com variante diferencia productId e productVariantId',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);

      await fixture.insertVariant(id: 10, sku: 'CAM-PRE-P', size: 'P');
      await fixture.insertVariant(id: 11, sku: 'CAM-PRE-G', size: 'G');
      final firstItemId = await fixture.insertOrderItem(
        productId: 1,
        productVariantId: 10,
      );
      final secondItemId = await fixture.insertOrderItem(
        productId: 1,
        productVariantId: 11,
      );

      await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: firstItemId,
          productId: 1,
          productVariantId: 10,
          quantityMil: 1000,
        ),
      );
      await fixture.repository.createReservation(
        StockReservationInput(
          operationalOrderId: fixture.orderId,
          operationalOrderItemId: secondItemId,
          productId: 1,
          productVariantId: 11,
          quantityMil: 2000,
        ),
      );

      expect(
        await fixture.repository.getReservedQuantityMil(
          productId: 1,
          productVariantId: 10,
        ),
        1000,
      );
      expect(
        await fixture.repository.getReservedQuantityMil(
          productId: 1,
          productVariantId: 11,
        ),
        2000,
      );
      expect(
        await fixture.repository.getReservedQuantityByProductKeys(const [
          StockReservationProductKey(productId: 1, productVariantId: 10),
          StockReservationProductKey(productId: 1, productVariantId: 11),
        ]),
        equals({
          const StockReservationProductKey(productId: 1, productVariantId: 10):
              1000,
          const StockReservationProductKey(productId: 1, productVariantId: 11):
              2000,
        }),
      );
    },
  );
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_ReservationFixture> _openFixture() async {
  final isolationKey =
      'remote:stock-reservation-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  await _insertProduct(database);
  final orderId = await _insertOrder(database);
  return _ReservationFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
    repository: SqliteStockReservationRepository(appDatabase),
    orderId: orderId,
  );
}

Future<void> _insertProduct(DatabaseExecutor db) {
  return db.insert(TableNames.produtos, {
    'id': 1,
    'uuid': 'product-1',
    'nome': 'Camiseta Basic',
    'descricao': null,
    'categoria_id': null,
    'foto_path': null,
    'codigo_barras': '789000000001',
    'tipo_produto': 'unidade',
    'unidade_medida': 'un',
    'custo_centavos': 4000,
    'preco_venda_centavos': 9900,
    'estoque_mil': 5000,
    'ativo': 1,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
    'deletado_em': null,
  });
}

Future<int> _insertOrder(DatabaseExecutor db) {
  return db.insert(TableNames.pedidosOperacionais, {
    'uuid': 'order-1',
    'status': 'open',
    'observacao': null,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
    'fechado_em': null,
  });
}

class _ReservationFixture {
  const _ReservationFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
    required this.repository,
    required this.orderId,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;
  final SqliteStockReservationRepository repository;
  final int orderId;

  Future<int> insertOrderItem({required int productId, int? productVariantId}) {
    return database.insert(TableNames.pedidosOperacionaisItens, {
      'uuid':
          'order-item-$productId-${productVariantId ?? 0}-${DateTime.now().microsecondsSinceEpoch}',
      'pedido_operacional_id': orderId,
      'produto_id': productId,
      'produto_variante_id': productVariantId,
      'nome_produto_snapshot': 'Camiseta Basic',
      'quantidade_mil': 1000,
      'valor_unitario_centavos': 9900,
      'subtotal_centavos': 9900,
      'observacao': null,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
    });
  }

  Future<void> insertVariant({
    required int id,
    required String sku,
    required String size,
  }) {
    return database.insert(TableNames.produtoVariantes, {
      'id': id,
      'uuid': 'variant-$id',
      'produto_id': 1,
      'sku': sku,
      'cor': 'Preta',
      'tamanho': size,
      'preco_adicional_centavos': 0,
      'estoque_mil': 3000,
      'ordem': id,
      'ativo': 1,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
    });
  }

  Future<int> insertSale() {
    return database.insert(TableNames.vendas, {
      'uuid': 'sale-${DateTime.now().microsecondsSinceEpoch}',
      'cliente_id': null,
      'tipo_venda': 'vista',
      'forma_pagamento': 'pix',
      'status': 'ativa',
      'desconto_centavos': 0,
      'acrescimo_centavos': 0,
      'valor_total_centavos': 9900,
      'valor_final_centavos': 9900,
      'numero_cupom': DateTime.now().microsecondsSinceEpoch.toString(),
      'data_venda': _fixedNowIso,
      'usuario_id': null,
      'observacao': null,
      'cancelada_em': null,
      'venda_origem_id': null,
    });
  }

  Future<List<Map<String, Object?>>> allReservations() {
    return database.query(TableNames.estoqueReservas, orderBy: 'id ASC');
  }

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}
