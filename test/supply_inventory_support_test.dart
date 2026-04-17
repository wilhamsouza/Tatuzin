import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/carrinho/domain/entities/cart_item.dart';
import 'package:erp_pdv_app/modules/compras/data/models/purchase_item_model.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_item.dart';
import 'package:erp_pdv_app/modules/insumos/data/support/supply_inventory_support.dart';
import 'package:erp_pdv_app/modules/insumos/domain/entities/supply_inventory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await _createSchema(db);
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('Baseline legado', () {
    test(
      'insumo sem movimentos e com saldo legado consistente recebe um baseline',
      () async {
        final supplyId = await _insertSupply(
          database,
          name: 'Farinha',
          unitType: 'g',
          purchaseUnitType: 'kg',
          conversionFactor: 1000,
        );

        final result = await SupplyInventorySupport.seedLegacyBaselineIfNeeded(
          database,
          supplyId: supplyId,
          supplyUuid: 'supply:Farinha',
          legacyStockMil: 250000,
          occurredAt: _now,
        );

        final movements = await _movementRows(database);
        expect(result.created, isTrue);
        expect(movements, hasLength(1));
        expect(movements.single['source_type'], 'migration_seed');
        expect(await _currentStock(database, supplyId), 250000);
      },
    );

    test('seed legado nao duplica baseline nem altera saldo final', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Acucar',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
      );

      final first = await SupplyInventorySupport.seedLegacyBaselineIfNeeded(
        database,
        supplyId: supplyId,
        supplyUuid: 'supply:Acucar',
        legacyStockMil: 300000,
        occurredAt: _now,
      );
      final second = await SupplyInventorySupport.seedLegacyBaselineIfNeeded(
        database,
        supplyId: supplyId,
        supplyUuid: 'supply:Acucar',
        legacyStockMil: 300000,
        occurredAt: _later,
      );

      final movements = await _movementRows(database);
      expect(first.status, SupplyInventoryBaselineSeedStatus.created);
      expect(
        second.status,
        SupplyInventoryBaselineSeedStatus.skippedAlreadyExists,
      );
      expect(
        movements
            .where((row) => row['source_type'] == 'migration_seed')
            .toList(),
        hasLength(1),
      );
      expect(await _currentStock(database, supplyId), 300000);
    });

    test('seed legado nao e aplicado sobre ledger existente', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Oleo',
        unitType: 'ml',
        purchaseUnitType: 'l',
        conversionFactor: 1000,
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 1000,
            unitMeasureSnapshot: 'l',
          ),
        ],
        occurredAt: _now,
      );

      final result = await SupplyInventorySupport.seedLegacyBaselineIfNeeded(
        database,
        supplyId: supplyId,
        supplyUuid: 'supply:Oleo',
        legacyStockMil: 999000,
        occurredAt: _later,
      );

      final movements = await _movementRows(database);
      expect(
        result.status,
        SupplyInventoryBaselineSeedStatus.skippedHasMovements,
      );
      expect(
        movements
            .where((row) => row['source_type'] == 'migration_seed')
            .toList(),
        isEmpty,
      );
      expect(await _currentStock(database, supplyId), 1000000);
    });
  });

  group('Compras / entrada', () {
    test('compra com item supply gera movimento de entrada', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Mussarela',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 1500,
            unitMeasureSnapshot: 'kg',
          ),
        ],
        occurredAt: _now,
      );

      final movements = await _movementRows(database);
      expect(movements, hasLength(1));
      expect(movements.single['movement_type'], 'in');
      expect(movements.single['source_type'], 'purchase');
      expect(movements.single['quantity_delta_mil'], 1500000);
      expect(await _currentStock(database, supplyId), 1500000);
    });

    test('compra so com product nao gera ledger de insumo', () async {
      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: const [
          PurchaseItemModel(
            id: 0,
            uuid: 'product-item',
            purchaseId: 0,
            itemType: PurchaseItemType.product,
            productId: 10,
            productVariantId: null,
            supplyId: null,
            itemNameSnapshot: 'Hamburguer',
            variantSkuSnapshot: null,
            variantColorLabelSnapshot: null,
            variantSizeLabelSnapshot: null,
            unitMeasureSnapshot: 'un',
            quantityMil: 1000,
            unitCostCents: 1200,
            subtotalCents: 1200,
          ),
        ],
        occurredAt: _now,
      );

      expect(await _movementRows(database), isEmpty);
    });

    test('compra mista gera entrada apenas para supply', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Molho',
        unitType: 'ml',
        purchaseUnitType: 'l',
        conversionFactor: 1000,
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          const PurchaseItemModel(
            id: 0,
            uuid: 'product-item',
            purchaseId: 0,
            itemType: PurchaseItemType.product,
            productId: 99,
            productVariantId: null,
            supplyId: null,
            itemNameSnapshot: 'Combo',
            variantSkuSnapshot: null,
            variantColorLabelSnapshot: null,
            variantSizeLabelSnapshot: null,
            unitMeasureSnapshot: 'un',
            quantityMil: 1000,
            unitCostCents: 1200,
            subtotalCents: 1200,
          ),
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 2000,
            unitMeasureSnapshot: 'l',
          ),
        ],
        occurredAt: _now,
      );

      final movements = await _movementRows(database);
      expect(movements, hasLength(1));
      expect(movements.single['supply_id'], supplyId);
      expect(movements.single['quantity_delta_mil'], 2000000);
    });

    test('edicao de compra recompõe corretamente os movimentos', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Carne',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 1000,
            unitMeasureSnapshot: 'kg',
          ),
        ],
        occurredAt: _now,
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 2500,
            unitMeasureSnapshot: 'kg',
          ),
        ],
        occurredAt: _later,
      );

      final movements = await _movementRows(database);
      expect(movements, hasLength(1));
      expect(movements.single['quantity_delta_mil'], 2500000);
      expect(await _currentStock(database, supplyId), 2500000);
    });

    test('cancelamento de compra estorna corretamente', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Queijo',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 1000,
            unitMeasureSnapshot: 'kg',
          ),
        ],
        occurredAt: _now,
      );
      await SupplyInventorySupport.cancelPurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        occurredAt: _later,
      );

      final movements = await _movementRows(database);
      expect(movements, hasLength(2));
      expect(movements.last['movement_type'], 'reversal');
      expect(movements.last['source_type'], 'purchase_cancel');
      expect(await _currentStock(database, supplyId), 0);
    });

    test(
      'cancelamento repetido de compra nao altera saldo pela segunda vez',
      () async {
        final supplyId = await _insertSupply(
          database,
          name: 'Presunto',
          unitType: 'g',
          purchaseUnitType: 'kg',
          conversionFactor: 1000,
        );

        await SupplyInventorySupport.replacePurchaseEntries(
          database,
          purchaseUuid: 'purchase-1',
          items: [
            _purchaseSupplyItem(
              supplyId: supplyId,
              quantityMil: 1000,
              unitMeasureSnapshot: 'kg',
            ),
          ],
          occurredAt: _now,
        );
        await SupplyInventorySupport.cancelPurchaseEntries(
          database,
          purchaseUuid: 'purchase-1',
          occurredAt: _later,
        );
        await SupplyInventorySupport.cancelPurchaseEntries(
          database,
          purchaseUuid: 'purchase-1',
          occurredAt: _muchLater,
        );

        final reversalRows = await database.query(
          TableNames.supplyInventoryMovements,
          where: 'source_type = ?',
          whereArgs: [SupplyInventorySourceType.purchaseCancel.storageValue],
        );
        expect(reversalRows, hasLength(1));
        expect(await _currentStock(database, supplyId), 0);
      },
    );
  });

  group('Vendas / saida', () {
    test('venda de produto com ficha gera consumo de insumos', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Mussarela',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
        currentStockMil: 1000000,
      );
      await _insertSeedMovement(
        database,
        supplyId: supplyId,
        quantityDeltaMil: 1000000,
      );
      await _insertRecipeItem(
        database,
        productId: 10,
        supplyId: supplyId,
        quantityUsedMil: 50000,
        unitType: 'g',
      );

      final result = await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'Pizza',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 3200,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _now,
      );

      final movements = await _movementRows(database);
      expect(result.affectedSupplyIds, [supplyId]);
      expect(result.appliedLines, hasLength(1));
      expect(result.appliedLines.single.productId, 10);
      expect(result.skippedWithoutRecipeLines, isEmpty);
      expect(movements, hasLength(2));
      expect(movements.last['movement_type'], 'out');
      expect(movements.last['source_type'], 'sale');
      expect(movements.last['quantity_delta_mil'], -50000);
      expect(await _currentStock(database, supplyId), 950000);
    });

    test('venda de produto sem ficha nao gera consumo', () async {
      final result = await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 11,
            productName: 'Refrigerante',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 700,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _now,
      );

      expect(result.affectedSupplyIds, isEmpty);
      expect(result.appliedLines, isEmpty);
      expect(result.hasSkippedWithoutRecipeLines, isTrue);
      expect(result.skippedWithoutRecipeLines, hasLength(1));
      expect(result.skippedWithoutRecipeLines.single.productId, 11);
      expect(await _movementRows(database), isEmpty);
    });

    test('venda mista resume itens com e sem ficha tecnica', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Molho especial',
        unitType: 'ml',
        purchaseUnitType: 'l',
        conversionFactor: 1000,
        currentStockMil: 1000000,
      );
      await _insertSeedMovement(
        database,
        supplyId: supplyId,
        quantityDeltaMil: 1000000,
      );
      await _insertRecipeItem(
        database,
        productId: 10,
        supplyId: supplyId,
        quantityUsedMil: 25000,
        unitType: 'ml',
      );

      final result = await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'Burger especial',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 3200,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
          CartItem(
            id: 'cart-2',
            productId: 11,
            productName: 'Suco',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 900,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _now,
      );

      expect(result.lines, hasLength(2));
      expect(result.appliedLines, hasLength(1));
      expect(result.appliedLines.single.productName, 'Burger especial');
      expect(result.skippedWithoutRecipeLines, hasLength(1));
      expect(result.skippedWithoutRecipeLines.single.productName, 'Suco');
      expect(result.affectedSupplyIds, [supplyId]);
      expect(await _currentStock(database, supplyId), 975000);
    });

    test(
      'venda com multiplas unidades multiplica corretamente a ficha',
      () async {
        final supplyId = await _insertSupply(
          database,
          name: 'Carne',
          unitType: 'g',
          purchaseUnitType: 'kg',
          conversionFactor: 1000,
        );
        await _insertRecipeItem(
          database,
          productId: 10,
          supplyId: supplyId,
          quantityUsedMil: 90000,
          unitType: 'g',
        );

        await SupplyInventorySupport.recordSaleConsumption(
          database,
          saleUuid: 'sale-1',
          items: const [
            CartItem(
              id: 'cart-1',
              productId: 10,
              productName: 'Burger',
              baseProductId: null,
              baseProductName: null,
              quantityMil: 2000,
              availableStockMil: 2000,
              unitPriceCents: 2800,
              unitMeasure: 'un',
              productType: 'unidade',
            ),
          ],
          occurredAt: _now,
        );

        final movements = await _movementRows(database);
        expect(movements.single['quantity_delta_mil'], -180000);
      },
    );

    test('cancelamento da venda reverte os movimentos', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Molho',
        unitType: 'ml',
        purchaseUnitType: 'l',
        conversionFactor: 1000,
        currentStockMil: 1000000,
      );
      await _insertSeedMovement(
        database,
        supplyId: supplyId,
        quantityDeltaMil: 1000000,
      );
      await _insertRecipeItem(
        database,
        productId: 10,
        supplyId: supplyId,
        quantityUsedMil: 30000,
        unitType: 'ml',
      );

      await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'Hot dog',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 1500,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _now,
      );
      await SupplyInventorySupport.reverseSaleConsumption(
        database,
        saleUuid: 'sale-1',
        occurredAt: _later,
      );

      final movements = await _movementRows(database);
      expect(movements, hasLength(3));
      expect(movements.last['source_type'], 'sale_cancel');
      expect(movements.last['quantity_delta_mil'], 30000);
      expect(await _currentStock(database, supplyId), 1000000);
    });

    test('cancelamento repetido nao duplica reversao', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Embalagem',
        unitType: 'un',
        purchaseUnitType: 'cx',
        conversionFactor: 100,
      );
      await _insertRecipeItem(
        database,
        productId: 10,
        supplyId: supplyId,
        quantityUsedMil: 1000,
        unitType: 'un',
      );

      await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'Combo',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 2900,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _now,
      );
      await SupplyInventorySupport.reverseSaleConsumption(
        database,
        saleUuid: 'sale-1',
        occurredAt: _later,
      );
      await SupplyInventorySupport.reverseSaleConsumption(
        database,
        saleUuid: 'sale-1',
        occurredAt: _muchLater,
      );

      final reversalRows = await database.query(
        TableNames.supplyInventoryMovements,
        where: 'source_type = ?',
        whereArgs: [SupplyInventorySourceType.saleCancel.storageValue],
      );
      expect(reversalRows, hasLength(1));
    });
  });

  group('Saldo / robustez', () {
    test('saldo derivado reflete corretamente entradas e saidas', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Bacon',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
      );
      await _insertRecipeItem(
        database,
        productId: 10,
        supplyId: supplyId,
        quantityUsedMil: 100000,
        unitType: 'g',
      );

      await SupplyInventorySupport.replacePurchaseEntries(
        database,
        purchaseUuid: 'purchase-1',
        items: [
          _purchaseSupplyItem(
            supplyId: supplyId,
            quantityMil: 2000,
            unitMeasureSnapshot: 'kg',
          ),
        ],
        occurredAt: _now,
      );
      await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'Burger',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 3000,
            availableStockMil: 3000,
            unitPriceCents: 2800,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _later,
      );

      expect(
        await SupplyInventorySupport.currentBalanceForSupply(
          database,
          supplyId: supplyId,
        ),
        1700000,
      );
      expect(await _currentStock(database, supplyId), 1700000);
    });

    test('retry operacional nao duplica movimento de venda', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Tomate',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
      );
      await _insertRecipeItem(
        database,
        productId: 10,
        supplyId: supplyId,
        quantityUsedMil: 20000,
        unitType: 'g',
      );

      await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'X-salada',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 2200,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _now,
      );
      await SupplyInventorySupport.recordSaleConsumption(
        database,
        saleUuid: 'sale-1',
        items: const [
          CartItem(
            id: 'cart-1',
            productId: 10,
            productName: 'X-salada',
            baseProductId: null,
            baseProductName: null,
            quantityMil: 1000,
            availableStockMil: 1000,
            unitPriceCents: 2200,
            unitMeasure: 'un',
            productType: 'unidade',
          ),
        ],
        occurredAt: _later,
      );

      final saleRows = await database.query(
        TableNames.supplyInventoryMovements,
        where: 'source_type = ?',
        whereArgs: [SupplyInventorySourceType.sale.storageValue],
      );
      expect(saleRows, hasLength(1));
    });

    test('recomputacao de saldo a partir do ledger continua integra', () async {
      final supplyId = await _insertSupply(
        database,
        name: 'Cebola',
        unitType: 'g',
        purchaseUnitType: 'kg',
        conversionFactor: 1000,
        currentStockMil: 999999,
      );

      await _insertSeedMovement(
        database,
        supplyId: supplyId,
        quantityDeltaMil: 500000,
      );
      await database.insert(TableNames.supplyInventoryMovements, {
        'uuid': 'sale:$supplyId',
        'remote_id': null,
        'supply_id': supplyId,
        'movement_type': 'out',
        'source_type': 'sale',
        'source_local_uuid': 'sale-1',
        'source_remote_id': null,
        'dedupe_key': 'sale:manual:$supplyId',
        'quantity_delta_mil': -125000,
        'unit_type': 'g',
        'balance_after_mil': null,
        'notes': 'Consumo manual para teste.',
        'occurred_at': _later.toIso8601String(),
        'created_at': _later.toIso8601String(),
        'updated_at': _later.toIso8601String(),
      });

      await SupplyInventorySupport.rebuildSupplyStockCache(
        database,
        supplyIds: [supplyId],
        changedAt: _muchLater,
      );

      expect(
        await SupplyInventorySupport.currentBalanceForSupply(
          database,
          supplyId: supplyId,
        ),
        375000,
      );
      expect(await _currentStock(database, supplyId), 375000);
    });

    test(
      'verificacao de consistencia corrige drift entre ledger e cache',
      () async {
        final supplyId = await _insertSupply(
          database,
          name: 'Alface',
          unitType: 'g',
          purchaseUnitType: 'kg',
          conversionFactor: 1000,
          currentStockMil: 999999,
        );

        await _insertSeedMovement(
          database,
          supplyId: supplyId,
          quantityDeltaMil: 450000,
        );

        final report = await SupplyInventorySupport.verifyInventoryConsistency(
          database,
          supplyIds: [supplyId],
          checkedAt: _later,
        );

        expect(report.checkedSupplyCount, 1);
        expect(report.driftedSupplyCount, 1);
        expect(report.repairedSupplyCount, 1);
        expect(report.issues.single.cachedStockMil, 999999);
        expect(report.issues.single.ledgerStockMil, 450000);
        expect(await _currentStock(database, supplyId), 450000);
      },
    );

    test(
      'historico de custo e estoque operacional permanecem separados',
      () async {
        final supplyId = await _insertSupply(
          database,
          name: 'Maionese',
          unitType: 'ml',
          purchaseUnitType: 'l',
          conversionFactor: 1000,
        );

        await SupplyInventorySupport.replacePurchaseEntries(
          database,
          purchaseUuid: 'purchase-1',
          items: [
            _purchaseSupplyItem(
              supplyId: supplyId,
              quantityMil: 1000,
              unitMeasureSnapshot: 'l',
            ),
          ],
          occurredAt: _now,
        );

        final tables = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = '${TableNames.supplyInventoryMovements}'
        ''');
        expect(tables, hasLength(1));
        expect(await _movementRows(database), isNotEmpty);
      },
    );
  });
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE ${TableNames.supplies} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      sku TEXT,
      unit_type TEXT NOT NULL,
      purchase_unit_type TEXT NOT NULL,
      conversion_factor INTEGER NOT NULL,
      last_purchase_price_cents INTEGER NOT NULL DEFAULT 0,
      average_purchase_price_cents INTEGER,
      current_stock_mil INTEGER,
      minimum_stock_mil INTEGER,
      default_supplier_id INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.productRecipeItems} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      product_id INTEGER NOT NULL,
      supply_id INTEGER NOT NULL,
      quantity_used_mil INTEGER NOT NULL,
      unit_type TEXT NOT NULL,
      waste_basis_points INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.supplyInventoryMovements} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      remote_id TEXT,
      supply_id INTEGER NOT NULL,
      movement_type TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_local_uuid TEXT,
      source_remote_id TEXT,
      dedupe_key TEXT NOT NULL UNIQUE,
      quantity_delta_mil INTEGER NOT NULL,
      unit_type TEXT NOT NULL,
      balance_after_mil INTEGER,
      notes TEXT,
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
}

Future<int> _insertSupply(
  Database db, {
  required String name,
  required String unitType,
  required String purchaseUnitType,
  required int conversionFactor,
  int? currentStockMil,
  int? minimumStockMil,
}) {
  return db.insert(TableNames.supplies, {
    'uuid': 'supply:$name',
    'name': name,
    'sku': null,
    'unit_type': unitType,
    'purchase_unit_type': purchaseUnitType,
    'conversion_factor': conversionFactor,
    'last_purchase_price_cents': 0,
    'average_purchase_price_cents': null,
    'current_stock_mil': currentStockMil,
    'minimum_stock_mil': minimumStockMil,
    'default_supplier_id': null,
    'is_active': 1,
    'created_at': _now.toIso8601String(),
    'updated_at': _now.toIso8601String(),
  });
}

Future<void> _insertRecipeItem(
  Database db, {
  required int productId,
  required int supplyId,
  required int quantityUsedMil,
  required String unitType,
  int wasteBasisPoints = 0,
}) async {
  await db.insert(TableNames.productRecipeItems, {
    'uuid': 'recipe:$productId:$supplyId',
    'product_id': productId,
    'supply_id': supplyId,
    'quantity_used_mil': quantityUsedMil,
    'unit_type': unitType,
    'waste_basis_points': wasteBasisPoints,
    'notes': null,
    'created_at': _now.toIso8601String(),
    'updated_at': _now.toIso8601String(),
  });
}

Future<void> _insertSeedMovement(
  Database db, {
  required int supplyId,
  required int quantityDeltaMil,
}) async {
  await db.insert(TableNames.supplyInventoryMovements, {
    'uuid': 'seed:$supplyId',
    'remote_id': null,
    'supply_id': supplyId,
    'movement_type': 'adjustment',
    'source_type': 'migration_seed',
    'source_local_uuid': 'seed:$supplyId',
    'source_remote_id': null,
    'dedupe_key': 'seed:$supplyId',
    'quantity_delta_mil': quantityDeltaMil,
    'unit_type': 'g',
    'balance_after_mil': quantityDeltaMil,
    'notes': 'Baseline',
    'occurred_at': _now.toIso8601String(),
    'created_at': _now.toIso8601String(),
    'updated_at': _now.toIso8601String(),
  });
}

PurchaseItemModel _purchaseSupplyItem({
  required int supplyId,
  required int quantityMil,
  required String unitMeasureSnapshot,
}) {
  return PurchaseItemModel(
    id: 0,
    uuid: 'supply-item:$supplyId:$quantityMil',
    purchaseId: 0,
    itemType: PurchaseItemType.supply,
    productId: null,
    productVariantId: null,
    supplyId: supplyId,
    itemNameSnapshot: 'Supply #$supplyId',
    variantSkuSnapshot: null,
    variantColorLabelSnapshot: null,
    variantSizeLabelSnapshot: null,
    unitMeasureSnapshot: unitMeasureSnapshot,
    quantityMil: quantityMil,
    unitCostCents: 1000,
    subtotalCents: 1000,
  );
}

Future<List<Map<String, Object?>>> _movementRows(Database db) {
  return db.query(TableNames.supplyInventoryMovements, orderBy: 'id ASC');
}

Future<int?> _currentStock(Database db, int supplyId) async {
  final rows = await db.query(
    TableNames.supplies,
    columns: const ['current_stock_mil'],
    where: 'id = ?',
    whereArgs: [supplyId],
    limit: 1,
  );
  return rows.first['current_stock_mil'] as int?;
}

final _now = DateTime.parse('2026-04-15T12:00:00Z');
final _later = DateTime.parse('2026-04-15T12:10:00Z');
final _muchLater = DateTime.parse('2026-04-15T12:20:00Z');
