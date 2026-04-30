import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order.dart';
import 'package:erp_pdv_app/modules/pedidos/presentation/providers/order_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'produto simples exibe disponibilidade real descontando reserva',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertSimpleProduct(stockMil: 10000);
      await fixture.insertReservation(
        productVariantId: null,
        quantityMil: 3000,
      );
      final container = fixture.createContainer();
      addTearDown(container.dispose);

      final options = await container.read(
        orderCatalogOptionsProvider('').future,
      );

      expect(options, hasLength(1));
      expect(options.single.physicalQuantityMil, 10000);
      expect(options.single.reservedQuantityMil, 3000);
      expect(options.single.availableQuantityMil, 7000);
    },
  );

  test('variante exibe disponibilidade real descontando reserva', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    await fixture.insertVariantProduct(
      parentStockMil: 5000,
      firstVariantStockMil: 5000,
    );
    await fixture.insertReservation(productVariantId: 10, quantityMil: 2000);
    final container = fixture.createContainer();
    addTearDown(container.dispose);

    final options = await container.read(
      orderCatalogOptionsProvider('').future,
    );

    expect(options, hasLength(1));
    expect(options.single.product.sellableVariantId, 10);
    expect(options.single.physicalQuantityMil, 5000);
    expect(options.single.reservedQuantityMil, 2000);
    expect(options.single.availableQuantityMil, 3000);
  });

  test(
    'variante totalmente reservada nao aparece e nao pode ser adicionada',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertVariantProduct(
        parentStockMil: 1000,
        firstVariantStockMil: 1000,
      );
      await fixture.insertReservation(productVariantId: 10, quantityMil: 1000);
      final container = fixture.createContainer();
      addTearDown(container.dispose);
      final orderId = await fixture.createDraftOrder();

      final options = await container.read(
        orderCatalogOptionsProvider('').future,
      );
      expect(options, isEmpty);
      await expectLater(
        () => container
            .read(operationalOrderItemControllerProvider.notifier)
            .addItemWithModifiers(
              orderId: orderId,
              productId: 1,
              baseProductId: 1,
              productVariantId: 10,
              variantSkuSnapshot: 'CAM-PRE-G',
              variantColorSnapshot: 'Preta',
              variantSizeSnapshot: 'G',
              productName: 'Camiseta Preta G',
              unitPriceCents: 9900,
              quantityUnits: 1,
            ),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test('quantidade maior que disponivel real e bloqueada', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    await fixture.insertSimpleProduct(stockMil: 10000);
    await fixture.insertReservation(productVariantId: null, quantityMil: 3000);
    final container = fixture.createContainer();
    addTearDown(container.dispose);
    final orderId = await fixture.createDraftOrder();

    await expectLater(
      () => container
          .read(operationalOrderItemControllerProvider.notifier)
          .addItemWithModifiers(
            orderId: orderId,
            productId: 1,
            baseProductId: null,
            productName: 'Camiseta Basic',
            unitPriceCents: 9900,
            quantityUnits: 8,
          ),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          contains('Disponivel: 7'),
        ),
      ),
    );
  });

  test('reservas released e converted nao reduzem disponibilidade', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    await fixture.insertSimpleProduct(stockMil: 10000);
    await fixture.insertReservation(
      productVariantId: null,
      quantityMil: 3000,
      status: StockReservationStatus.released,
    );
    await fixture.insertReservation(
      productVariantId: null,
      quantityMil: 4000,
      status: StockReservationStatus.converted,
    );
    final container = fixture.createContainer();
    addTearDown(container.dispose);

    final options = await container.read(
      orderCatalogOptionsProvider('').future,
    );

    expect(options, hasLength(1));
    expect(options.single.reservedQuantityMil, 0);
    expect(options.single.availableQuantityMil, 10000);
  });

  test(
    'reserva da variante A nao reduz disponibilidade da variante B',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertVariantProduct(
        parentStockMil: 10000,
        firstVariantStockMil: 5000,
        secondVariantStockMil: 5000,
      );
      await fixture.insertReservation(productVariantId: 10, quantityMil: 2000);
      final container = fixture.createContainer();
      addTearDown(container.dispose);

      final options = await container.read(
        orderCatalogOptionsProvider('').future,
      );
      final byVariantId = {
        for (final option in options) option.product.sellableVariantId: option,
      };

      expect(byVariantId[10]!.availableQuantityMil, 3000);
      expect(byVariantId[11]!.availableQuantityMil, 5000);
    },
  );
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_AvailabilityFixture> _openFixture() async {
  final isolationKey =
      'remote:order-catalog-availability-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  return _AvailabilityFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
  );
}

class _AvailabilityFixture {
  const _AvailabilityFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(appDatabase),
        appStartupProvider.overrideWith(
          (ref) async => const AppStartupState.success(),
        ),
      ],
    );
  }

  Future<void> insertSimpleProduct({required int stockMil}) {
    return database.insert(TableNames.produtos, {
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

  Future<void> insertVariantProduct({
    required int parentStockMil,
    required int firstVariantStockMil,
    int? secondVariantStockMil,
  }) async {
    await insertSimpleProduct(stockMil: parentStockMil);
    await _insertVariant(
      id: 10,
      sku: 'CAM-PRE-G',
      size: 'G',
      stockMil: firstVariantStockMil,
    );
    if (secondVariantStockMil != null) {
      await _insertVariant(
        id: 11,
        sku: 'CAM-PRE-P',
        size: 'P',
        stockMil: secondVariantStockMil,
      );
    }
  }

  Future<void> _insertVariant({
    required int id,
    required String sku,
    required String size,
    required int stockMil,
  }) {
    return database.insert(TableNames.produtoVariantes, {
      'id': id,
      'uuid': 'variant-$id',
      'produto_id': 1,
      'sku': sku,
      'cor': 'Preta',
      'tamanho': size,
      'preco_adicional_centavos': 0,
      'estoque_mil': stockMil,
      'ordem': id,
      'ativo': 1,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
    });
  }

  Future<int> createDraftOrder() {
    return database.insert(TableNames.pedidosOperacionais, {
      'uuid': 'draft-order-${DateTime.now().microsecondsSinceEpoch}',
      'status': OperationalOrderStatus.draft.dbValue,
      'atendimento_tipo': OperationalOrderServiceType.counter.dbValue,
      'cliente_identificador': null,
      'telefone_cliente': null,
      'observacao': null,
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
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
      'fechado_em': null,
    });
  }

  Future<void> insertReservation({
    required int? productVariantId,
    required int quantityMil,
    StockReservationStatus status = StockReservationStatus.active,
  }) async {
    final orderId = await createDraftOrder();
    final itemId = await database.insert(TableNames.pedidosOperacionaisItens, {
      'uuid': 'item-${DateTime.now().microsecondsSinceEpoch}',
      'pedido_operacional_id': orderId,
      'produto_id': 1,
      'produto_variante_id': productVariantId,
      'nome_produto_snapshot': 'Camiseta Basic',
      'quantidade_mil': quantityMil,
      'valor_unitario_centavos': 9900,
      'subtotal_centavos': 9900 * (quantityMil ~/ 1000),
      'observacao': null,
      'criado_em': _fixedNowIso,
      'atualizado_em': _fixedNowIso,
    });
    await database.insert(TableNames.estoqueReservas, {
      'uuid': 'reservation-${DateTime.now().microsecondsSinceEpoch}',
      'pedido_operacional_id': orderId,
      'item_pedido_operacional_id': itemId,
      'produto_id': 1,
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
