import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_stock_availability_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'produto simples sem reserva retorna estoque fisico disponivel',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);

      final availability = await fixture.repository.getAvailability(
        productId: 1,
        productVariantId: null,
      );

      expect(availability.productId, 1);
      expect(availability.productVariantId, isNull);
      expect(availability.physicalQuantityMil, 10000);
      expect(availability.reservedQuantityMil, 0);
      expect(availability.availableQuantityMil, 10000);
    },
  );

  test('produto simples com reserva ativa desconta do disponivel', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final itemId = await fixture.insertOrderItem(productId: 1);
    await fixture.insertReservation(
      orderItemId: itemId,
      productId: 1,
      productVariantId: null,
      quantityMil: 3000,
      status: StockReservationStatus.active,
    );

    final availability = await fixture.repository.getAvailability(
      productId: 1,
      productVariantId: null,
    );

    expect(availability.physicalQuantityMil, 10000);
    expect(availability.reservedQuantityMil, 3000);
    expect(availability.availableQuantityMil, 7000);
  });

  test('produto simples ignora reservas released e converted', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    final releasedItemId = await fixture.insertOrderItem(productId: 1);
    final convertedItemId = await fixture.insertOrderItem(productId: 1);
    await fixture.insertReservation(
      orderItemId: releasedItemId,
      productId: 1,
      productVariantId: null,
      quantityMil: 3000,
      status: StockReservationStatus.released,
    );
    await fixture.insertReservation(
      orderItemId: convertedItemId,
      productId: 1,
      productVariantId: null,
      quantityMil: 4000,
      status: StockReservationStatus.converted,
    );

    final availability = await fixture.repository.getAvailability(
      productId: 1,
      productVariantId: null,
    );

    expect(availability.physicalQuantityMil, 10000);
    expect(availability.reservedQuantityMil, 0);
    expect(availability.availableQuantityMil, 10000);
  });

  test('variante sem reserva retorna estoque fisico da variante', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    await fixture.insertVariant(id: 10, stockMil: 5000);

    final availability = await fixture.repository.getAvailability(
      productId: 1,
      productVariantId: 10,
    );

    expect(availability.productId, 1);
    expect(availability.productVariantId, 10);
    expect(availability.physicalQuantityMil, 5000);
    expect(availability.reservedQuantityMil, 0);
    expect(availability.availableQuantityMil, 5000);
  });

  test('variante com reserva ativa desconta do disponivel', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    await fixture.insertVariant(id: 10, stockMil: 5000);
    final itemId = await fixture.insertOrderItem(
      productId: 1,
      productVariantId: 10,
    );
    await fixture.insertReservation(
      orderItemId: itemId,
      productId: 1,
      productVariantId: 10,
      quantityMil: 2000,
      status: StockReservationStatus.active,
    );

    final availability = await fixture.repository.getAvailability(
      productId: 1,
      productVariantId: 10,
    );

    expect(availability.physicalQuantityMil, 5000);
    expect(availability.reservedQuantityMil, 2000);
    expect(availability.availableQuantityMil, 3000);
  });

  test(
    'reserva da variante A nao reduz disponibilidade da variante B',
    () async {
      final fixture = await _openFixture(productStockMil: 10000);
      addTearDown(fixture.dispose);
      await fixture.insertVariant(id: 10, stockMil: 5000);
      await fixture.insertVariant(id: 11, stockMil: 5000, sku: 'CAM-PRE-G');
      final itemId = await fixture.insertOrderItem(
        productId: 1,
        productVariantId: 10,
      );
      await fixture.insertReservation(
        orderItemId: itemId,
        productId: 1,
        productVariantId: 10,
        quantityMil: 2000,
        status: StockReservationStatus.active,
      );

      final firstAvailability = await fixture.repository.getAvailability(
        productId: 1,
        productVariantId: 10,
      );
      final secondAvailability = await fixture.repository.getAvailability(
        productId: 1,
        productVariantId: 11,
      );

      expect(firstAvailability.reservedQuantityMil, 2000);
      expect(firstAvailability.availableQuantityMil, 3000);
      expect(secondAvailability.reservedQuantityMil, 0);
      expect(secondAvailability.availableQuantityMil, 5000);
    },
  );

  test('disponivel nao fica negativo quando reservado supera fisico', () async {
    final fixture = await _openFixture(productStockMil: 1000);
    addTearDown(fixture.dispose);
    final itemId = await fixture.insertOrderItem(productId: 1);
    await fixture.insertReservation(
      orderItemId: itemId,
      productId: 1,
      productVariantId: null,
      quantityMil: 2000,
      status: StockReservationStatus.active,
    );

    final availability = await fixture.repository.getAvailability(
      productId: 1,
      productVariantId: null,
    );

    expect(availability.physicalQuantityMil, 1000);
    expect(availability.reservedQuantityMil, 2000);
    expect(availability.rawAvailableQuantityMil, -1000);
    expect(availability.availableQuantityMil, 0);
  });

  test('consulta em lote retorna produto simples e variante', () async {
    final fixture = await _openFixture(productStockMil: 10000);
    addTearDown(fixture.dispose);
    await fixture.insertVariant(id: 10, stockMil: 5000);
    final simpleItemId = await fixture.insertOrderItem(productId: 1);
    final variantItemId = await fixture.insertOrderItem(
      productId: 1,
      productVariantId: 10,
    );
    await fixture.insertReservation(
      orderItemId: simpleItemId,
      productId: 1,
      productVariantId: null,
      quantityMil: 2000,
      status: StockReservationStatus.active,
    );
    await fixture.insertReservation(
      orderItemId: variantItemId,
      productId: 1,
      productVariantId: 10,
      quantityMil: 1000,
      status: StockReservationStatus.active,
    );

    final availabilityByKey = await fixture.repository
        .getAvailabilityByProductKeys(const [
          StockReservationProductKey(productId: 1, productVariantId: null),
          StockReservationProductKey(productId: 1, productVariantId: 10),
        ]);

    final simpleAvailability =
        availabilityByKey[const StockReservationProductKey(
          productId: 1,
          productVariantId: null,
        )]!;
    final variantAvailability =
        availabilityByKey[const StockReservationProductKey(
          productId: 1,
          productVariantId: 10,
        )]!;

    expect(simpleAvailability.physicalQuantityMil, 10000);
    expect(simpleAvailability.reservedQuantityMil, 2000);
    expect(simpleAvailability.availableQuantityMil, 8000);
    expect(variantAvailability.physicalQuantityMil, 5000);
    expect(variantAvailability.reservedQuantityMil, 1000);
    expect(variantAvailability.availableQuantityMil, 4000);
  });
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_AvailabilityFixture> _openFixture({
  required int productStockMil,
}) async {
  final isolationKey =
      'remote:stock-availability-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  await _insertProduct(database, stockMil: productStockMil);
  final orderId = await _insertOrder(database);
  return _AvailabilityFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
    repository: SqliteStockAvailabilityRepository(appDatabase),
    orderId: orderId,
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

class _AvailabilityFixture {
  const _AvailabilityFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
    required this.repository,
    required this.orderId,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;
  final SqliteStockAvailabilityRepository repository;
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
    required int stockMil,
    String sku = 'CAM-PRE-P',
  }) {
    return database.insert(TableNames.produtoVariantes, {
      'id': id,
      'uuid': 'variant-$id',
      'produto_id': 1,
      'sku': sku,
      'cor': 'Preta',
      'tamanho': id == 10 ? 'P' : 'G',
      'preco_adicional_centavos': 0,
      'estoque_mil': stockMil,
      'ordem': id,
      'ativo': 1,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
    });
  }

  Future<int> insertReservation({
    required int orderItemId,
    required int productId,
    required int? productVariantId,
    required int quantityMil,
    required StockReservationStatus status,
  }) {
    return database.insert(TableNames.estoqueReservas, {
      'uuid':
          'reservation-$orderItemId-${status.storageValue}-${DateTime.now().microsecondsSinceEpoch}',
      'pedido_operacional_id': orderId,
      'item_pedido_operacional_id': orderItemId,
      'produto_id': productId,
      'produto_variante_id': productVariantId,
      'quantidade_mil': quantityMil,
      'status': status.storageValue,
      'venda_id': null,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
      'liberado_em': status == StockReservationStatus.released
          ? _fixedNowIso
          : null,
      'convertido_em_venda_em': status == StockReservationStatus.converted
          ? _fixedNowIso
          : null,
    });
  }

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}
