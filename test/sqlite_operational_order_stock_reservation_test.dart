import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_stock_availability_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:erp_pdv_app/modules/pedidos/data/sqlite_operational_order_repository.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('pedido draft nao cria reserva antes do envio', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);

    final reservations = await fixture.activeReservationsByOrder(orderId);
    final order = await fixture.repository.findById(orderId);

    expect(order!.status, OperationalOrderStatus.draft);
    expect(reservations, isEmpty);
  });

  test('sendToKitchen cria reservas active para todos os itens', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    await fixture.insertVariant(id: 10, stockMil: 5000);
    final orderId = await fixture.createDraftOrder();
    final simpleItemId = await fixture.addSimpleItem(
      orderId,
      quantityMil: 1000,
    );
    final variantItemId = await fixture.addVariantItem(
      orderId,
      productVariantId: 10,
      quantityMil: 2000,
    );

    await fixture.repository.sendToKitchen(orderId);

    final reservations = await fixture.activeReservationsByOrder(orderId);
    final order = await fixture.repository.findById(orderId);

    expect(order!.status, OperationalOrderStatus.open);
    expect(reservations, hasLength(2));
    expect(
      reservations.map((row) => row['item_pedido_operacional_id']).toSet(),
      {simpleItemId, variantItemId},
    );
    expect(reservations.map((row) => row['status']).toSet(), {
      StockReservationStatus.active.storageValue,
    });
  });

  test(
    'sendToKitchen nao altera estoque fisico de produto nem variante',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      await fixture.insertVariant(id: 10, stockMil: 5000);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.addVariantItem(
        orderId,
        productVariantId: 10,
        quantityMil: 1000,
      );

      await fixture.repository.sendToKitchen(orderId);

      expect(await fixture.productStockMil(), 10000);
      expect(await fixture.variantStockMil(10), 5000);
    },
  );

  test('sendToKitchen chamado duas vezes nao duplica reserva', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);

    await fixture.repository.sendToKitchen(orderId);
    await fixture.repository.sendToKitchen(orderId);

    final reservations = await fixture.activeReservationsByOrder(orderId);
    expect(reservations, hasLength(1));
  });

  test('produto simples reserva com productVariantId null', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);

    await fixture.repository.sendToKitchen(orderId);

    final reservations = await fixture.activeReservationsByOrder(orderId);
    expect(reservations.single['produto_id'], 1);
    expect(reservations.single['produto_variante_id'], isNull);
    expect(reservations.single['quantidade_mil'], 1000);
  });

  test('produto com variante reserva com productVariantId correto', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    await fixture.insertVariant(id: 10, stockMil: 5000);
    final orderId = await fixture.createDraftOrder();
    await fixture.addVariantItem(
      orderId,
      productVariantId: 10,
      quantityMil: 1000,
    );

    await fixture.repository.sendToKitchen(orderId);

    final reservations = await fixture.activeReservationsByOrder(orderId);
    expect(reservations.single['produto_id'], 1);
    expect(reservations.single['produto_variante_id'], 10);
    expect(reservations.single['quantidade_mil'], 1000);
  });

  test('variante com estoque 1 nao e reservada por dois pedidos', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    await fixture.insertVariant(id: 10, stockMil: 1000);
    final firstOrderId = await fixture.createDraftOrder();
    await fixture.addVariantItem(
      firstOrderId,
      productVariantId: 10,
      quantityMil: 1000,
    );
    await fixture.repository.sendToKitchen(firstOrderId);

    final secondOrderId = await fixture.createDraftOrder();
    await fixture.addVariantItem(
      secondOrderId,
      productVariantId: 10,
      quantityMil: 1000,
    );

    expect(
      () => fixture.repository.sendToKitchen(secondOrderId),
      throwsA(isA<ValidationException>()),
    );
    expect(await fixture.activeReservationCountForVariant(10), 1);
    expect(
      (await fixture.repository.findById(secondOrderId))!.status,
      OperationalOrderStatus.draft,
    );
  });

  test(
    'estoque insuficiente nao cria reserva parcial nem muda status',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      await fixture.insertVariant(id: 10, stockMil: 1000);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.addVariantItem(
        orderId,
        productVariantId: 10,
        quantityMil: 2000,
        sku: 'CAM-PRE-P',
        color: 'Preta',
        size: 'P',
      );

      await expectLater(
        () => fixture.repository.sendToKitchen(orderId),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Estoque insuficiente'),
              contains('CAM-PRE-P'),
              contains('Preta'),
              contains('P'),
            ),
          ),
        ),
      );

      expect(await fixture.activeReservationsByOrder(orderId), isEmpty);
      expect(
        (await fixture.repository.findById(orderId))!.status,
        OperationalOrderStatus.draft,
      );
    },
  );

  test(
    'pedido antigo sem variante continua reservando produto simples',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);

      await fixture.repository.sendToKitchen(orderId);

      final reservations = await fixture.activeReservationsByOrder(orderId);
      expect(reservations, hasLength(1));
      expect(reservations.single['produto_variante_id'], isNull);
      expect(
        (await fixture.repository.findById(orderId))!.status,
        OperationalOrderStatus.open,
      );
    },
  );

  test(
    'item reservado nao pode ser alterado e mantem reserva original',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      final orderId = await fixture.createDraftOrder();
      final itemId = await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.repository.sendToKitchen(orderId);

      await expectLater(
        () => fixture.addSimpleItem(orderId, quantityMil: 1000),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        () => fixture.repository.updateItem(
          itemId,
          const OperationalOrderItemInput(
            productId: 1,
            productNameSnapshot: 'Camiseta Basic',
            quantityMil: 2000,
            unitPriceCents: 9900,
            subtotalCents: 19800,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        () => fixture.repository.removeItem(itemId),
        throwsA(isA<ValidationException>()),
      );

      final reservations = await fixture.activeReservationsByOrder(orderId);
      final items = await fixture.repository.listItems(orderId);
      expect(reservations, hasLength(1));
      expect(reservations.single['quantidade_mil'], 1000);
      expect(items.single.quantityMil, 1000);
      expect(await fixture.productStockMil(), 10000);
    },
  );

  test('pedido entregue sem faturamento mantem reserva active', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.repository.sendToKitchen(orderId);
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.inPreparation,
    );
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.ready,
    );
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.delivered,
    );

    final reservations = await fixture.reservationsByOrder(orderId);
    expect(
      reservations.single['status'],
      StockReservationStatus.active.storageValue,
    );
    expect(reservations.single['venda_id'], isNull);
    expect(reservations.single['convertido_em_venda_em'], isNull);
    expect(await fixture.productStockMil(), 10000);
  });

  test('cancelar pedido draft nao cria reserva', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);

    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );

    expect(await fixture.reservationsByOrder(orderId), isEmpty);
    expect(
      (await fixture.repository.findById(orderId))!.status,
      OperationalOrderStatus.canceled,
    );
  });

  test('cancelar pedido open libera reservas active', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.repository.sendToKitchen(orderId);

    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );

    final reservations = await fixture.reservationsByOrder(orderId);
    expect(reservations, hasLength(1));
    expect(
      reservations.single['status'],
      StockReservationStatus.released.storageValue,
    );
    expect(reservations.single['liberado_em'], isNotNull);
  });

  test('cancelar pedido em separacao libera reservas active', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.repository.sendToKitchen(orderId);
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.inPreparation,
    );

    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );

    expect(
      (await fixture.reservationsByOrder(orderId)).single['status'],
      StockReservationStatus.released.storageValue,
    );
  });

  test('cancelar pedido pronto libera reservas active', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.repository.sendToKitchen(orderId);
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.inPreparation,
    );
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.ready,
    );

    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );

    expect(
      (await fixture.reservationsByOrder(orderId)).single['status'],
      StockReservationStatus.released.storageValue,
    );
  });

  test(
    'cancelar pedido nao altera estoque fisico do produto simples nem variante',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      await fixture.insertVariant(id: 10, stockMil: 5000);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.addVariantItem(
        orderId,
        productVariantId: 10,
        quantityMil: 1000,
      );
      await fixture.repository.sendToKitchen(orderId);

      await fixture.repository.updateStatus(
        orderId,
        OperationalOrderStatus.canceled,
      );

      expect(await fixture.productStockMil(), 10000);
      expect(await fixture.variantStockMil(10), 5000);
    },
  );

  test('cancelar pedido com reserva already released nao falha', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.repository.sendToKitchen(orderId);
    await fixture.markReservationsReleased(orderId);

    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );

    expect(
      (await fixture.reservationsByOrder(orderId)).single['status'],
      StockReservationStatus.released.storageValue,
    );
    expect(
      (await fixture.repository.findById(orderId))!.status,
      OperationalOrderStatus.canceled,
    );
  });

  test(
    'cancelar pedido com reserva converted nao muda para released',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.repository.sendToKitchen(orderId);
      await fixture.markReservationsConverted(orderId);

      await fixture.repository.updateStatus(
        orderId,
        OperationalOrderStatus.canceled,
      );

      final reservation = (await fixture.reservationsByOrder(orderId)).single;
      expect(
        reservation['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(reservation['liberado_em'], isNull);
      expect(reservation['convertido_em_venda_em'], isNotNull);
    },
  );

  test('apos cancelar pedido disponibilidade real volta a aumentar', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 3000);
    await fixture.repository.sendToKitchen(orderId);

    final reservedAvailability = await fixture.availabilityRepository
        .getAvailability(productId: 1, productVariantId: null);
    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );
    final releasedAvailability = await fixture.availabilityRepository
        .getAvailability(productId: 1, productVariantId: null);

    expect(reservedAvailability.availableQuantityMil, 7000);
    expect(releasedAvailability.availableQuantityMil, 10000);
  });

  test('pedido antigo sem reserva cancela normalmente', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.markOrderStatus(orderId, OperationalOrderStatus.open);

    await fixture.repository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );

    expect(await fixture.reservationsByOrder(orderId), isEmpty);
    expect(
      (await fixture.repository.findById(orderId))!.status,
      OperationalOrderStatus.canceled,
    );
  });
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_OrderReservationFixture> _openFixture({
  required int productStockMil,
}) async {
  final isolationKey =
      'remote:order-reservation-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  await _insertProduct(database, stockMil: productStockMil);
  return _OrderReservationFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
    repository: SqliteOperationalOrderRepository(appDatabase),
    availabilityRepository: SqliteStockAvailabilityRepository(appDatabase),
  );
}

Future<void> _insertProduct(DatabaseExecutor db, {required int stockMil}) {
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
    'estoque_mil': stockMil,
    'ativo': 1,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
    'deletado_em': null,
  });
}

class _OrderReservationFixture {
  const _OrderReservationFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
    required this.repository,
    required this.availabilityRepository,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;
  final SqliteOperationalOrderRepository repository;
  final SqliteStockAvailabilityRepository availabilityRepository;

  Future<int> createDraftOrder() {
    return repository.create(const OperationalOrderInput());
  }

  Future<int> addSimpleItem(int orderId, {required int quantityMil}) {
    return repository.addItem(
      orderId,
      OperationalOrderItemInput(
        productId: 1,
        productNameSnapshot: 'Camiseta Basic',
        quantityMil: quantityMil,
        unitPriceCents: 9900,
        subtotalCents: 9900 * (quantityMil ~/ 1000),
      ),
    );
  }

  Future<int> addVariantItem(
    int orderId, {
    required int productVariantId,
    required int quantityMil,
    String sku = 'CAM-PRE-P',
    String color = 'Preta',
    String size = 'P',
  }) {
    return repository.addItem(
      orderId,
      OperationalOrderItemInput(
        productId: 1,
        productVariantId: productVariantId,
        variantSkuSnapshot: sku,
        variantColorSnapshot: color,
        variantSizeSnapshot: size,
        productNameSnapshot: 'Camiseta Basic',
        quantityMil: quantityMil,
        unitPriceCents: 9900,
        subtotalCents: 9900 * (quantityMil ~/ 1000),
      ),
    );
  }

  Future<void> insertVariant({required int id, required int stockMil}) {
    return database.insert(TableNames.produtoVariantes, {
      'id': id,
      'uuid': 'variant-$id',
      'produto_id': 1,
      'sku': 'CAM-PRE-P',
      'cor': 'Preta',
      'tamanho': 'P',
      'preco_adicional_centavos': 0,
      'estoque_mil': stockMil,
      'ordem': id,
      'ativo': 1,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
    });
  }

  Future<List<Map<String, Object?>>> activeReservationsByOrder(int orderId) {
    return database.query(
      TableNames.estoqueReservas,
      where: 'pedido_operacional_id = ? AND status = ?',
      whereArgs: [orderId, StockReservationStatus.active.storageValue],
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, Object?>>> reservationsByOrder(int orderId) {
    return database.query(
      TableNames.estoqueReservas,
      where: 'pedido_operacional_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
  }

  Future<void> markReservationsReleased(int orderId) async {
    await database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.released.storageValue,
        'atualizado_em': _fixedNowIso,
        'liberado_em': _fixedNowIso,
      },
      where: 'pedido_operacional_id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> markReservationsConverted(int orderId) async {
    await database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.converted.storageValue,
        'atualizado_em': _fixedNowIso,
        'convertido_em_venda_em': _fixedNowIso,
      },
      where: 'pedido_operacional_id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> markOrderStatus(
    int orderId,
    OperationalOrderStatus status,
  ) async {
    await database.update(
      TableNames.pedidosOperacionais,
      {
        'status': status.dbValue,
        'atualizado_em': _fixedNowIso,
        'enviado_cozinha_em': status == OperationalOrderStatus.open
            ? _fixedNowIso
            : null,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<int> activeReservationCountForVariant(int productVariantId) async {
    final rows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${TableNames.estoqueReservas}
      WHERE produto_id = ?
        AND produto_variante_id = ?
        AND status = ?
      ''',
      [1, productVariantId, StockReservationStatus.active.storageValue],
    );
    return rows.single['total'] as int? ?? 0;
  }

  Future<int> productStockMil() async {
    final rows = await database.query(
      TableNames.produtos,
      columns: const ['estoque_mil'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    return rows.single['estoque_mil'] as int? ?? 0;
  }

  Future<int> variantStockMil(int productVariantId) async {
    final rows = await database.query(
      TableNames.produtoVariantes,
      columns: const ['estoque_mil'],
      where: 'id = ?',
      whereArgs: [productVariantId],
      limit: 1,
    );
    return rows.single['estoque_mil'] as int? ?? 0;
  }

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}
