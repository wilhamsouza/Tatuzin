import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/carrinho/domain/entities/cart_item.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:erp_pdv_app/modules/pedidos/data/sqlite_operational_order_repository.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:erp_pdv_app/modules/vendas/data/sqlite_sale_repository.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/checkout_input.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sale_inventory_test_support.dart'
    show createSaleRepository, loadProductStock, loadVariantStock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'faturar pedido simples com reserva active converte reserva e baixa estoque uma vez',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertSimpleProduct(stockMil: 5000);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.prepareDeliveredOrder(orderId);

      final sale = await fixture.saleRepository.completeCashSale(
        input: fixture.checkoutInput(
          orderId: orderId,
          items: [_simpleCartItem(quantityMil: 1000, availableStockMil: 5000)],
        ),
      );

      final reservation = (await fixture.reservationsByOrder(orderId)).single;
      expect(
        reservation['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(reservation['venda_id'], sale.saleId);
      expect(reservation['convertido_em_venda_em'], isNotNull);
      expect(await loadProductStock(fixture.database, 1), 4000);
    },
  );

  test(
    'faturar pedido com variante reservada converte reserva e baixa a variante',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertVariantProduct(
        parentStockMil: 5000,
        firstVariantStockMil: 3000,
        secondVariantStockMil: 2000,
      );
      final orderId = await fixture.createDraftOrder();
      await fixture.addVariantItem(
        orderId,
        productVariantId: 10,
        quantityMil: 1000,
      );
      await fixture.prepareDeliveredOrder(orderId);

      final sale = await fixture.saleRepository.completeCashSale(
        input: fixture.checkoutInput(
          orderId: orderId,
          items: [
            _variantCartItem(
              variantId: 10,
              size: 'P',
              quantityMil: 1000,
              availableStockMil: 3000,
            ),
          ],
        ),
      );

      final reservation = (await fixture.reservationsByOrder(orderId)).single;
      expect(
        reservation['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(reservation['venda_id'], sale.saleId);
      expect(reservation['produto_variante_id'], 10);
      expect(await loadVariantStock(fixture.database, 10), 2000);
      expect(await loadVariantStock(fixture.database, 11), 2000);
      expect(await loadProductStock(fixture.database, 1), 4000);
    },
  );

  test('pedido antigo sem reserva continua faturando', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    await fixture.insertSimpleProduct(stockMil: 5000);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.markOrderDelivered(orderId);

    await fixture.saleRepository.completeCashSale(
      input: fixture.checkoutInput(
        orderId: orderId,
        items: [_simpleCartItem(quantityMil: 1000, availableStockMil: 5000)],
      ),
    );

    expect(await fixture.reservationsByOrder(orderId), isEmpty);
    expect(await loadProductStock(fixture.database, 1), 4000);
  });

  test(
    'reservas released e converted nao viram converted da nova venda',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertSimpleProduct(stockMil: 5000);
      final orderId = await fixture.createDraftOrder();
      final firstItemId = await fixture.addSimpleItem(
        orderId,
        quantityMil: 1000,
      );
      final secondItemId = await fixture.addSimpleItem(
        orderId,
        quantityMil: 1000,
      );
      await fixture.prepareDeliveredOrder(orderId);
      await fixture.markReservationReleased(orderId, firstItemId);
      final previousSaleId = await fixture.insertSale();
      await fixture.markReservationConverted(
        orderId,
        secondItemId,
        previousSaleId,
      );

      await fixture.saleRepository.completeCashSale(
        input: fixture.checkoutInput(
          orderId: orderId,
          items: [_simpleCartItem(quantityMil: 2000, availableStockMil: 5000)],
        ),
      );

      final rows = await fixture.reservationsByOrder(orderId);
      final released = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == firstItemId,
      );
      final converted = rows.singleWhere(
        (row) => row['item_pedido_operacional_id'] == secondItemId,
      );
      expect(released['status'], StockReservationStatus.released.storageValue);
      expect(released['venda_id'], isNull);
      expect(
        converted['status'],
        StockReservationStatus.converted.storageValue,
      );
      expect(converted['venda_id'], previousSaleId);
    },
  );

  test('faturamento duplicado nao baixa estoque duas vezes', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    await fixture.insertSimpleProduct(stockMil: 5000);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.prepareDeliveredOrder(orderId);
    final input = fixture.checkoutInput(
      orderId: orderId,
      items: [_simpleCartItem(quantityMil: 1000, availableStockMil: 5000)],
    );

    await fixture.saleRepository.completeCashSale(input: input);
    await expectLater(
      () => fixture.saleRepository.completeCashSale(input: input),
      throwsA(isA<ValidationException>()),
    );

    expect(await loadProductStock(fixture.database, 1), 4000);
    expect(await fixture.salesCount(), 1);
    expect(
      (await fixture.reservationsByOrder(orderId)).single['status'],
      StockReservationStatus.converted.storageValue,
    );
  });

  test('pedido cancelado nao pode ser faturado', () async {
    final fixture = await _openFixture();
    addTearDown(fixture.dispose);
    await fixture.insertSimpleProduct(stockMil: 5000);
    final orderId = await fixture.createDraftOrder();
    await fixture.addSimpleItem(orderId, quantityMil: 1000);
    await fixture.prepareCanceledOrder(orderId);

    await expectLater(
      () => fixture.saleRepository.completeCashSale(
        input: fixture.checkoutInput(
          orderId: orderId,
          items: [_simpleCartItem(quantityMil: 1000, availableStockMil: 5000)],
        ),
      ),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          contains('esta cancelado'),
        ),
      ),
    );

    expect(await fixture.salesCount(), 0);
    expect(await loadProductStock(fixture.database, 1), 5000);
    expect(
      (await fixture.reservationsByOrder(orderId)).single['status'],
      StockReservationStatus.released.storageValue,
    );
  });

  test(
    'falha de venda por estoque insuficiente mantem reserva active e nao cria venda',
    () async {
      final fixture = await _openFixture();
      addTearDown(fixture.dispose);
      await fixture.insertSimpleProduct(stockMil: 1000);
      final orderId = await fixture.createDraftOrder();
      await fixture.addSimpleItem(orderId, quantityMil: 1000);
      await fixture.prepareDeliveredOrder(orderId);
      await fixture.setProductStock(0);

      await expectLater(
        () => fixture.saleRepository.completeCashSale(
          input: fixture.checkoutInput(
            orderId: orderId,
            items: [
              _simpleCartItem(quantityMil: 1000, availableStockMil: 1000),
            ],
          ),
        ),
        throwsA(isA<StockConflictException>()),
      );

      final reservation = (await fixture.reservationsByOrder(orderId)).single;
      expect(reservation['status'], StockReservationStatus.active.storageValue);
      expect(reservation['venda_id'], isNull);
      expect(await fixture.salesCount(), 0);
      expect(await loadProductStock(fixture.database, 1), 0);
    },
  );
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_BillingReservationFixture> _openFixture() async {
  final isolationKey =
      'remote:order-billing-reservation-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  return _BillingReservationFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
    orderRepository: SqliteOperationalOrderRepository(appDatabase),
    saleRepository: createSaleRepository(database),
  );
}

CartItem _simpleCartItem({
  required int quantityMil,
  required int availableStockMil,
}) {
  return CartItem(
    id: 'cart-1-$quantityMil',
    productId: 1,
    productName: 'Camiseta Basic',
    baseProductId: null,
    baseProductName: null,
    quantityMil: quantityMil,
    availableStockMil: availableStockMil,
    unitPriceCents: 9900,
    unitMeasure: 'un',
    productType: 'unidade',
  );
}

CartItem _variantCartItem({
  required int variantId,
  required String size,
  required int quantityMil,
  required int availableStockMil,
}) {
  return CartItem(
    id: 'cart-1-$variantId-$quantityMil',
    productId: 1,
    productVariantId: variantId,
    productName: 'Camiseta Basic - $size / Preta',
    baseProductId: 1,
    baseProductName: 'Camiseta Basic',
    variantSku: 'CAM-PRE-$size',
    variantColorLabel: 'Preta',
    variantSizeLabel: size,
    quantityMil: quantityMil,
    availableStockMil: availableStockMil,
    unitPriceCents: 9900,
    unitMeasure: 'un',
    productType: 'grade',
  );
}

class _BillingReservationFixture {
  const _BillingReservationFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
    required this.orderRepository,
    required this.saleRepository,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;
  final SqliteOperationalOrderRepository orderRepository;
  final SqliteSaleRepository saleRepository;

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
    required int secondVariantStockMil,
  }) async {
    await insertSimpleProduct(stockMil: parentStockMil);
    await _insertVariant(
      id: 10,
      sku: 'CAM-PRE-P',
      size: 'P',
      stockMil: firstVariantStockMil,
    );
    await _insertVariant(
      id: 11,
      sku: 'CAM-PRE-G',
      size: 'G',
      stockMil: secondVariantStockMil,
    );
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
    return orderRepository.create(const OperationalOrderInput());
  }

  Future<int> addSimpleItem(int orderId, {required int quantityMil}) {
    return orderRepository.addItem(
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
  }) {
    return orderRepository.addItem(
      orderId,
      OperationalOrderItemInput(
        productId: 1,
        baseProductId: 1,
        productVariantId: productVariantId,
        variantSkuSnapshot: 'CAM-PRE-P',
        variantColorSnapshot: 'Preta',
        variantSizeSnapshot: 'P',
        productNameSnapshot: 'Camiseta Basic - P / Preta',
        quantityMil: quantityMil,
        unitPriceCents: 9900,
        subtotalCents: 9900 * (quantityMil ~/ 1000),
      ),
    );
  }

  Future<void> prepareDeliveredOrder(int orderId) async {
    await orderRepository.sendToKitchen(orderId);
    await orderRepository.updateStatus(
      orderId,
      OperationalOrderStatus.inPreparation,
    );
    await orderRepository.updateStatus(orderId, OperationalOrderStatus.ready);
    await orderRepository.updateStatus(
      orderId,
      OperationalOrderStatus.delivered,
    );
  }

  Future<void> prepareCanceledOrder(int orderId) async {
    await orderRepository.sendToKitchen(orderId);
    await orderRepository.updateStatus(
      orderId,
      OperationalOrderStatus.canceled,
    );
  }

  Future<void> markOrderDelivered(int orderId) {
    return database.update(
      TableNames.pedidosOperacionais,
      {
        'status': OperationalOrderStatus.delivered.dbValue,
        'atualizado_em': _fixedNowIso,
        'entregue_em': _fixedNowIso,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  CheckoutInput checkoutInput({
    required int orderId,
    required List<CartItem> items,
  }) {
    return CheckoutInput(
      items: items,
      saleType: SaleType.cash,
      paymentMethod: PaymentMethod.pix,
      operationalOrderId: orderId,
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

  Future<void> markReservationReleased(int orderId, int orderItemId) {
    return database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.released.storageValue,
        'atualizado_em': _fixedNowIso,
        'liberado_em': _fixedNowIso,
      },
      where: 'pedido_operacional_id = ? AND item_pedido_operacional_id = ?',
      whereArgs: [orderId, orderItemId],
    );
  }

  Future<void> markReservationConverted(
    int orderId,
    int orderItemId,
    int saleId,
  ) {
    return database.update(
      TableNames.estoqueReservas,
      {
        'status': StockReservationStatus.converted.storageValue,
        'venda_id': saleId,
        'atualizado_em': _fixedNowIso,
        'convertido_em_venda_em': _fixedNowIso,
      },
      where: 'pedido_operacional_id = ? AND item_pedido_operacional_id = ?',
      whereArgs: [orderId, orderItemId],
    );
  }

  Future<void> setProductStock(int stockMil) {
    return database.update(
      TableNames.produtos,
      {'estoque_mil': stockMil, 'atualizado_em': _fixedNowIso},
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<int> insertSale() {
    return database.insert(TableNames.vendas, {
      'uuid': 'sale-${DateTime.now().microsecondsSinceEpoch}',
      'cliente_id': null,
      'tipo_venda': SaleType.cash.dbValue,
      'forma_pagamento': PaymentMethod.pix.dbValue,
      'status': SaleStatus.active.dbValue,
      'desconto_centavos': 0,
      'acrescimo_centavos': 0,
      'valor_total_centavos': 9900,
      'valor_final_centavos': 9900,
      'haver_utilizado_centavos': 0,
      'haver_gerado_centavos': 0,
      'valor_recebido_imediato_centavos': 9900,
      'numero_cupom': DateTime.now().microsecondsSinceEpoch.toString(),
      'data_venda': _fixedNowIso,
      'usuario_id': null,
      'observacao': null,
      'cancelada_em': null,
      'venda_origem_id': null,
    });
  }

  Future<int> salesCount() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS total FROM ${TableNames.vendas}',
    );
    return rows.single['total'] as int? ?? 0;
  }

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}
