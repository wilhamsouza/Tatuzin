import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/migrations.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/carrinho/domain/entities/cart_item.dart';
import 'package:erp_pdv_app/modules/carrinho/presentation/pages/cart_page.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_availability.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:erp_pdv_app/modules/estoque/domain/repositories/stock_availability_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/repositories/stock_reservation_repository.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/insumos/domain/entities/supply_inventory.dart';
import 'package:erp_pdv_app/modules/pedidos/data/services/default_order_ticket_builder.dart';
import 'package:erp_pdv_app/modules/pedidos/data/sqlite_operational_order_repository.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/order_ticket_document.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_detail.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item_modifier.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_summary.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/repositories/operational_order_repository.dart';
import 'package:erp_pdv_app/modules/pedidos/presentation/mappers/order_ticket_mapper.dart';
import 'package:erp_pdv_app/modules/pedidos/presentation/providers/order_providers.dart';
import 'package:erp_pdv_app/modules/pedidos/presentation/support/order_ui_support.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/checkout_input.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/completed_sale.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:erp_pdv_app/modules/vendas/domain/repositories/sale_repository.dart';
import 'package:erp_pdv_app/modules/vendas/presentation/providers/sales_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sale_inventory_test_support.dart'
    show createSaleRepository, loadProductStock, loadVariantStock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'migration v34 adiciona campos de variante sem alterar pedidos antigos',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => AppMigrations.runCreate(db, 33),
        ),
      );
      addTearDown(database.close);

      await _insertProduct(database);
      final orderId = await _insertLegacyOrder(database);
      await database.insert(TableNames.pedidosOperacionaisItens, {
        'uuid': 'legacy-order-item',
        'pedido_operacional_id': orderId,
        'produto_id': 1,
        'nome_produto_snapshot': 'Camiseta Basic',
        'quantidade_mil': 1000,
        'valor_unitario_centavos': 9900,
        'subtotal_centavos': 9900,
        'observacao': null,
        'criado_em': _fixedNowIso,
        'atualizado_em': _fixedNowIso,
      });

      await AppMigrations.runUpgrade(database, 33, 34);

      final columns = await database.rawQuery(
        'PRAGMA table_info(${TableNames.pedidosOperacionaisItens})',
      );
      final columnNames = columns.map((row) => row['name']).toSet();
      expect(columnNames, contains('produto_variante_id'));
      expect(columnNames, contains('sku_variante_snapshot'));
      expect(columnNames, contains('cor_variante_snapshot'));
      expect(columnNames, contains('tamanho_variante_snapshot'));

      final itemRows = await database.query(
        TableNames.pedidosOperacionaisItens,
        where: 'uuid = ?',
        whereArgs: ['legacy-order-item'],
      );
      expect(itemRows.single['produto_variante_id'], isNull);
      expect(itemRows.single['sku_variante_snapshot'], isNull);
      expect(itemRows.single['cor_variante_snapshot'], isNull);
      expect(itemRows.single['tamanho_variante_snapshot'], isNull);

      final indexRows = await database.rawQuery(
        'PRAGMA index_list(${TableNames.pedidosOperacionaisItens})',
      );
      expect(
        indexRows.map((row) => row['name']),
        contains('idx_pedidos_operacionais_itens_produto_variante'),
      );
    },
  );

  test('repository preserva variante em item de pedido', () async {
    final fixture = await _openRepositoryFixture();
    addTearDown(fixture.dispose);

    await _insertProduct(fixture.database);
    await _insertProductVariant(fixture.database);

    final orderId = await fixture.repository.create(
      const OperationalOrderInput(),
    );
    await fixture.repository.addItem(
      orderId,
      const OperationalOrderItemInput(
        productId: 1,
        productVariantId: 10,
        variantSkuSnapshot: 'CAM-BASIC-PRETA-P',
        variantColorSnapshot: 'Preta',
        variantSizeSnapshot: 'P',
        productNameSnapshot: 'Camiseta Basic - P / Preta',
        quantityMil: 2000,
        unitPriceCents: 9900,
        subtotalCents: 19800,
      ),
    );

    final items = await fixture.repository.listItems(orderId);

    expect(items, hasLength(1));
    expect(items.single.productVariantId, 10);
    expect(items.single.variantSkuSnapshot, 'CAM-BASIC-PRETA-P');
    expect(items.single.variantColorSnapshot, 'Preta');
    expect(items.single.variantSizeSnapshot, 'P');
  });

  test('repository continua salvando item antigo sem variante', () async {
    final fixture = await _openRepositoryFixture();
    addTearDown(fixture.dispose);

    await _insertProduct(fixture.database);

    final orderId = await fixture.repository.create(
      const OperationalOrderInput(),
    );
    await fixture.repository.addItem(
      orderId,
      const OperationalOrderItemInput(
        productId: 1,
        productNameSnapshot: 'Camiseta Basic',
        quantityMil: 1000,
        unitPriceCents: 9900,
        subtotalCents: 9900,
      ),
    );

    final items = await fixture.repository.listItems(orderId);

    expect(items, hasLength(1));
    expect(items.single.productVariantId, isNull);
    expect(items.single.variantSkuSnapshot, isNull);
    expect(items.single.variantColorSnapshot, isNull);
    expect(items.single.variantSizeSnapshot, isNull);
  });

  test('carrinho cria input de pedido preservando variante', () {
    const item = CartItem(
      id: 'cart-1-10',
      productId: 1,
      productVariantId: 10,
      productName: 'Camiseta Basic - G / Preta',
      baseProductId: 1,
      baseProductName: 'Camiseta Basic',
      variantSku: 'CAM-BASIC-PRETA-G',
      variantColorLabel: 'Preta',
      variantSizeLabel: 'G',
      quantityMil: 2000,
      availableStockMil: 3000,
      unitPriceCents: 9900,
      unitMeasure: 'un',
      productType: 'grade',
    );

    final input = operationalOrderItemInputFromCartItem(item);

    expect(input.productVariantId, 10);
    expect(input.variantSkuSnapshot, 'CAM-BASIC-PRETA-G');
    expect(input.variantColorSnapshot, 'Preta');
    expect(input.variantSizeSnapshot, 'G');
  });

  test('controller de item manual preserva variante selecionada', () async {
    final repository = _RecordingOperationalOrderRepository();
    final container = ProviderContainer(
      overrides: [
        operationalOrderRepositoryProvider.overrideWithValue(repository),
        stockAvailabilityRepositoryProvider.overrideWithValue(
          const _AlwaysAvailableStockAvailabilityRepository(),
        ),
        stockReservationRepositoryProvider.overrideWithValue(
          const _NoActiveStockReservationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(operationalOrderItemControllerProvider.notifier)
        .addItemWithModifiers(
          orderId: 1,
          productId: 1,
          baseProductId: 1,
          productVariantId: 10,
          variantSkuSnapshot: 'CAM-BASIC-PRETA-G',
          variantColorSnapshot: 'Preta',
          variantSizeSnapshot: 'G',
          productName: 'Camiseta Basic - G / Preta',
          unitPriceCents: 9900,
          quantityUnits: 2,
          modifiers: const <OperationalOrderItemModifierInput>[],
          notes: null,
        );

    final input = repository.lastAddedInput;
    expect(input, isNotNull);
    expect(input!.productVariantId, 10);
    expect(input.variantSkuSnapshot, 'CAM-BASIC-PRETA-G');
    expect(input.variantColorSnapshot, 'Preta');
    expect(input.variantSizeSnapshot, 'G');
  });

  test('faturamento recebe CartItem com variante do pedido', () async {
    final saleRepository = _RecordingSaleRepository();
    final container = ProviderContainer(
      overrides: [saleRepositoryProvider.overrideWithValue(saleRepository)],
    );
    addTearDown(container.dispose);

    final detail = _buildOrderDetail(
      item: _buildOrderItem(
        productVariantId: 10,
        variantSkuSnapshot: 'CAM-BASIC-PRETA-G',
        variantColorSnapshot: 'Preta',
        variantSizeSnapshot: 'G',
      ),
    );

    await container
        .read(operationalOrderBillingControllerProvider.notifier)
        .invoice(detail: detail, paymentMethod: PaymentMethod.pix);

    final cartItem = saleRepository.lastCashInput!.items.single;
    expect(cartItem.productVariantId, 10);
    expect(cartItem.variantSku, 'CAM-BASIC-PRETA-G');
    expect(cartItem.variantColorLabel, 'Preta');
    expect(cartItem.variantSizeLabel, 'G');
  });

  test(
    'faturamento de pedido antigo sem variante continua funcionando',
    () async {
      final saleRepository = _RecordingSaleRepository();
      final container = ProviderContainer(
        overrides: [saleRepositoryProvider.overrideWithValue(saleRepository)],
      );
      addTearDown(container.dispose);

      final detail = _buildOrderDetail(item: _buildOrderItem());

      await container
          .read(operationalOrderBillingControllerProvider.notifier)
          .invoice(detail: detail, paymentMethod: PaymentMethod.cash);

      final cartItem = saleRepository.lastCashInput!.items.single;
      expect(cartItem.productVariantId, isNull);
      expect(cartItem.variantSku, isNull);
      expect(cartItem.variantColorLabel, isNull);
      expect(cartItem.variantSizeLabel, isNull);
    },
  );

  test(
    'faturar pedido com variante baixa estoque da variante correta',
    () async {
      final fixture = await _openRepositoryFixture();
      addTearDown(fixture.dispose);

      await _insertProduct(fixture.database, stockMil: 7000);
      await _insertProductVariant(fixture.database);
      await _insertProductVariant(
        fixture.database,
        id: 11,
        uuid: 'variant-11',
        sku: 'CAM-BASIC-PRETA-M',
        size: 'M',
        stockMil: 4000,
        sortOrder: 1,
      );

      final orderId = await fixture.repository.create(
        const OperationalOrderInput(),
      );
      await fixture.repository.addItem(
        orderId,
        const OperationalOrderItemInput(
          productId: 1,
          productVariantId: 10,
          variantSkuSnapshot: 'CAM-BASIC-PRETA-P',
          variantColorSnapshot: 'Preta',
          variantSizeSnapshot: 'P',
          productNameSnapshot: 'Camiseta Basic - P / Preta',
          quantityMil: 2000,
          unitPriceCents: 9900,
          subtotalCents: 19800,
        ),
      );
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
      final order = await fixture.repository.findById(orderId);
      final items = await fixture.repository.listItems(orderId);
      final detail = OperationalOrderDetail(
        order: order!,
        items: [
          OperationalOrderItemDetail(
            item: items.single,
            modifiers: const <OperationalOrderItemModifier>[],
          ),
        ],
        linkedSaleId: null,
      );
      final container = ProviderContainer(
        overrides: [
          saleRepositoryProvider.overrideWithValue(
            createSaleRepository(fixture.database),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(operationalOrderBillingControllerProvider.notifier)
          .invoice(detail: detail, paymentMethod: PaymentMethod.pix);

      expect(await loadVariantStock(fixture.database, 10), 1000);
      expect(await loadVariantStock(fixture.database, 11), 4000);
      expect(await loadProductStock(fixture.database, 1), 5000);
    },
  );

  test(
    'fluxo completo preserva variante do produto ate item de venda e estoque',
    () async {
      final fixture = await _openRepositoryFixture();
      addTearDown(fixture.dispose);

      await _insertProduct(fixture.database, stockMil: 7000);
      await _insertProductVariant(fixture.database);
      await _insertProductVariant(
        fixture.database,
        id: 11,
        uuid: 'variant-11',
        sku: 'CAM-BASIC-PRETA-G',
        size: 'G',
        stockMil: 4000,
        sortOrder: 1,
      );

      final product = _buildProduct(sellableVariantId: 10, size: 'P');
      final cartItem = CartItem.fromProduct(
        product,
      ).copyWith(quantityMil: 2000);

      expect(cartItem.productVariantId, 10);
      expect(cartItem.variantSku, 'CAM-BASIC-PRETA-P');
      expect(cartItem.variantColorLabel, 'Preta');
      expect(cartItem.variantSizeLabel, 'P');

      final orderInput = operationalOrderItemInputFromCartItem(cartItem);
      expect(orderInput.productVariantId, 10);
      expect(orderInput.variantSkuSnapshot, 'CAM-BASIC-PRETA-P');
      expect(orderInput.variantColorSnapshot, 'Preta');
      expect(orderInput.variantSizeSnapshot, 'P');

      final orderId = await fixture.repository.create(
        const OperationalOrderInput(),
      );
      await fixture.repository.addItem(orderId, orderInput);

      final savedItems = await fixture.repository.listItems(orderId);
      expect(savedItems, hasLength(1));
      expect(savedItems.single.productVariantId, 10);
      expect(savedItems.single.variantSkuSnapshot, 'CAM-BASIC-PRETA-P');
      expect(savedItems.single.variantColorSnapshot, 'Preta');
      expect(savedItems.single.variantSizeSnapshot, 'P');

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

      final deliveredOrder = await fixture.repository.findById(orderId);
      final deliveredItems = await fixture.repository.listItems(orderId);
      final detail = OperationalOrderDetail(
        order: deliveredOrder!,
        items: [
          OperationalOrderItemDetail(
            item: deliveredItems.single,
            modifiers: const <OperationalOrderItemModifier>[],
          ),
        ],
        linkedSaleId: null,
      );
      final saleRepository = createSaleRepository(fixture.database);
      final container = ProviderContainer(
        overrides: [saleRepositoryProvider.overrideWithValue(saleRepository)],
      );
      addTearDown(container.dispose);

      final sale = await container
          .read(operationalOrderBillingControllerProvider.notifier)
          .invoice(detail: detail, paymentMethod: PaymentMethod.pix);

      final saleItems = await fixture.database.query(
        TableNames.itensVenda,
        where: 'venda_id = ?',
        whereArgs: [sale.saleId],
      );
      expect(saleItems, hasLength(1));
      expect(saleItems.single['produto_variante_id'], 10);
      expect(saleItems.single['sku_variante_snapshot'], 'CAM-BASIC-PRETA-P');
      expect(saleItems.single['cor_variante_snapshot'], 'Preta');
      expect(saleItems.single['tamanho_variante_snapshot'], 'P');
      expect(await loadVariantStock(fixture.database, 10), 1000);
      expect(await loadVariantStock(fixture.database, 11), 4000);
      expect(await loadProductStock(fixture.database, 1), 5000);
    },
  );

  test('romaneio exibe SKU, cor e tamanho quando disponiveis', () {
    final detail = _buildOrderDetail(
      item: _buildOrderItem(
        productVariantId: 10,
        variantSkuSnapshot: 'CAM-BASIC-PRETA-G',
        variantColorSnapshot: 'Preta',
        variantSizeSnapshot: 'G',
      ),
    );

    final document = const DefaultOrderTicketBuilder().build(
      detail: detail,
      profile: OrderTicketProfile.kitchen,
    );
    final viewModel = OrderTicketMapper.fromDocument(document);

    expect(
      viewModel.lines.single.variantLabel,
      contains('SKU: CAM-BASIC-PRETA-G'),
    );
    expect(viewModel.lines.single.variantLabel, contains('Cor: Preta'));
    expect(viewModel.lines.single.variantLabel, contains('Tam: G'));
  });

  test('selecao visual diferencia variantes do mesmo produto', () {
    final selected = _buildProduct(sellableVariantId: 10, size: 'P');
    final sameVariant = _buildProduct(sellableVariantId: 10, size: 'P');
    final otherVariant = _buildProduct(sellableVariantId: 11, size: 'G');

    expect(
      operationalOrderIsSameSellableProduct(selected, sameVariant),
      isTrue,
    );
    expect(
      operationalOrderIsSameSellableProduct(selected, otherVariant),
      isFalse,
    );
  });
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_RepositoryFixture> _openRepositoryFixture() async {
  final isolationKey =
      'remote:order-variant-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  return _RepositoryFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
    repository: SqliteOperationalOrderRepository(appDatabase),
  );
}

Future<void> _insertProduct(DatabaseExecutor db, {int stockMil = 3000}) {
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

Future<void> _insertProductVariant(
  DatabaseExecutor db, {
  int id = 10,
  String uuid = 'variant-10',
  String sku = 'CAM-BASIC-PRETA-P',
  String color = 'Preta',
  String size = 'P',
  int stockMil = 3000,
  int sortOrder = 0,
}) {
  return db.insert(TableNames.produtoVariantes, {
    'id': id,
    'uuid': uuid,
    'produto_id': 1,
    'sku': sku,
    'cor': color,
    'tamanho': size,
    'preco_adicional_centavos': 0,
    'estoque_mil': stockMil,
    'ordem': sortOrder,
    'ativo': 1,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
  });
}

Future<int> _insertLegacyOrder(DatabaseExecutor db) {
  return db.insert(TableNames.pedidosOperacionais, {
    'uuid': 'legacy-order',
    'status': 'open',
    'observacao': null,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
    'fechado_em': null,
  });
}

class _RepositoryFixture {
  const _RepositoryFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
    required this.repository,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;
  final SqliteOperationalOrderRepository repository;

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}

OperationalOrderDetail _buildOrderDetail({required OperationalOrderItem item}) {
  return OperationalOrderDetail(
    order: OperationalOrder(
      id: 1,
      uuid: 'order-1',
      status: OperationalOrderStatus.delivered,
      serviceType: OperationalOrderServiceType.counter,
      customerIdentifier: null,
      customerPhone: null,
      notes: null,
      ticketMeta: const OperationalOrderTicketMeta(
        status: OrderTicketDispatchStatus.pending,
        dispatchAttempts: 0,
        lastAttemptAt: null,
        lastSentAt: null,
        lastFailureMessage: null,
      ),
      createdAt: _fixedNow,
      updatedAt: _fixedNow,
      sentToKitchenAt: null,
      preparationStartedAt: null,
      readyAt: null,
      deliveredAt: _fixedNow,
      canceledAt: null,
      closedAt: null,
    ),
    items: [
      OperationalOrderItemDetail(
        item: item,
        modifiers: const <OperationalOrderItemModifier>[],
      ),
    ],
    linkedSaleId: null,
  );
}

OperationalOrderItem _buildOrderItem({
  int? productVariantId,
  String? variantSkuSnapshot,
  String? variantColorSnapshot,
  String? variantSizeSnapshot,
}) {
  return OperationalOrderItem(
    id: 1,
    uuid: 'order-item-1',
    orderId: 1,
    productId: 1,
    baseProductId: 1,
    productVariantId: productVariantId,
    variantSkuSnapshot: variantSkuSnapshot,
    variantColorSnapshot: variantColorSnapshot,
    variantSizeSnapshot: variantSizeSnapshot,
    productNameSnapshot: 'Camiseta Basic',
    quantityMil: 1000,
    unitPriceCents: 9900,
    subtotalCents: 9900,
    notes: null,
    createdAt: _fixedNow,
    updatedAt: _fixedNow,
  );
}

Product _buildProduct({required int sellableVariantId, required String size}) {
  return Product(
    id: 1,
    uuid: 'product-1',
    name: 'Camiseta Basic',
    description: null,
    categoryId: null,
    categoryName: null,
    barcode: null,
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.fashion,
    catalogType: ProductCatalogTypes.variant,
    modelName: null,
    variantLabel: null,
    baseProductId: 1,
    baseProductName: 'Camiseta Basic',
    sellableVariantId: sellableVariantId,
    sellableVariantSku: 'CAM-BASIC-PRETA-$size',
    sellableVariantColorLabel: 'Preta',
    sellableVariantSizeLabel: size,
    unitMeasure: 'un',
    costCents: 4000,
    manualCostCents: 4000,
    costSource: ProductCostSource.manual,
    salePriceCents: 9900,
    stockMil: 3000,
    isActive: true,
    createdAt: _fixedNow,
    updatedAt: _fixedNow,
    deletedAt: null,
  );
}

class _RecordingOperationalOrderRepository
    implements OperationalOrderRepository {
  OperationalOrderItemInput? lastAddedInput;

  @override
  Future<int> addItem(int orderId, OperationalOrderItemInput input) async {
    lastAddedInput = input;
    return 1;
  }

  @override
  Future<void> replaceItemModifiers(
    int orderItemId,
    List<OperationalOrderItemModifierInput> modifiers,
  ) async {}

  @override
  Future<List<OperationalOrderSummary>> listSummaries({
    String query = '',
    OperationalOrderStatus? status,
  }) async {
    return const <OperationalOrderSummary>[];
  }

  @override
  Future<OperationalOrder?> findById(int orderId) async {
    return null;
  }

  @override
  Future<List<OperationalOrderItem>> listItems(int orderId) async {
    return const <OperationalOrderItem>[];
  }

  @override
  Future<List<OperationalOrderItemModifier>> listItemModifiers(
    int orderItemId,
  ) async {
    return const <OperationalOrderItemModifier>[];
  }

  @override
  Future<int?> findLinkedSaleId(int orderId) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysAvailableStockAvailabilityRepository
    implements StockAvailabilityRepository {
  const _AlwaysAvailableStockAvailabilityRepository();

  @override
  Future<StockAvailability> getAvailability({
    required int productId,
    required int? productVariantId,
  }) async {
    return StockAvailability(
      productId: productId,
      productVariantId: productVariantId,
      physicalQuantityMil: 999000,
      reservedQuantityMil: 0,
    );
  }

  @override
  Future<Map<StockReservationProductKey, StockAvailability>>
  getAvailabilityByProductKeys(
    Iterable<StockReservationProductKey> keys,
  ) async {
    return <StockReservationProductKey, StockAvailability>{
      for (final key in keys)
        key: StockAvailability(
          productId: key.productId,
          productVariantId: key.productVariantId,
          physicalQuantityMil: 999000,
          reservedQuantityMil: 0,
        ),
    };
  }
}

class _NoActiveStockReservationRepository
    implements StockReservationRepository {
  const _NoActiveStockReservationRepository();

  @override
  Future<StockReservation?> findActiveByOrderItemId(int orderItemId) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSaleRepository implements SaleRepository {
  CheckoutInput? lastCashInput;

  @override
  Future<CompletedSale> completeCashSale({required CheckoutInput input}) async {
    lastCashInput = input;
    return CompletedSale(
      saleId: 1,
      receiptNumber: '1',
      totalCents: input.finalTotalCents,
      itemsCount: input.items.length,
      soldAt: _fixedNow,
      saleType: input.saleType,
      paymentMethod: input.paymentMethod,
      supplyConsumption: const SupplySaleConsumptionResult.empty(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _fixedNow = DateTime.parse(_fixedNowIso);
