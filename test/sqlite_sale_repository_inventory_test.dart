import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tatuzin/app/core/app_context/app_operational_context.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/sync/operational_sync_event.dart';
import 'package:tatuzin/app/core/sync/operational_sync_queue_item.dart';
import 'package:tatuzin/app/core/sync/operational_sync_queue_repository.dart';
import 'package:tatuzin/app/core/sync/sync_feature_keys.dart';
import 'package:tatuzin/modules/vendas/data/sqlite_sale_repository.dart';
import 'package:tatuzin/modules/vendas/domain/entities/checkout_input.dart';
import 'package:tatuzin/modules/vendas/domain/entities/sale_enums.dart';

import 'support/sale_inventory_test_support.dart';

void main() {
  initializeSaleInventoryTestSupport();

  group('SqliteSaleRepository inventory integration', () {
    late Database database;

    tearDown(() async {
      await database.close();
    });

    test('venda simples baixa saldo e grava sale_out', () async {
      database = await openSaleInventoryTestDatabase();
      final repository = createSaleRepository(database);
      await insertSimpleProduct(
        database,
        productId: 1,
        name: 'Bone',
        stockMil: 5000,
        barcode: 'BON-001',
        salePriceCents: 7500,
      );

      final sale = await repository.completeCashSale(
        input: CheckoutInput(
          items: [
            buildSimpleCartItem(
              productId: 1,
              productName: 'Bone',
              quantityMil: 2000,
              availableStockMil: 5000,
              unitPriceCents: 7500,
              barcode: 'BON-001',
            ),
          ],
          saleType: SaleType.cash,
          paymentMethod: PaymentMethod.pix,
        ),
      );

      expect(await loadProductStock(database, 1), 3000);

      final movementRows = await loadInventoryMovementRows(database);
      expect(movementRows, hasLength(1));
      expect(movementRows.single['movement_type'], 'sale_out');
      expect(movementRows.single['product_id'], 1);
      expect(movementRows.single['product_variant_id'], isNull);
      expect(movementRows.single['quantity_delta_mil'], -2000);
      expect(movementRows.single['stock_before_mil'], 5000);
      expect(movementRows.single['stock_after_mil'], 3000);
      expect(movementRows.single['reference_type'], 'sale');
      expect(movementRows.single['reference_id'], sale.saleId);
    });

    test(
      'venda com variante baixa estoque da variante, recompõe pai e grava sale_out',
      () async {
        database = await openSaleInventoryTestDatabase();
        final repository = createSaleRepository(database);
        await insertVariantProduct(
          database,
          productId: 1,
          name: 'Camiseta Basic',
          parentStockMil: 7000,
          variants: const [
            VariantSeed(
              id: 10,
              sku: 'CAM-BASIC-PRETA-P',
              color: 'Preta',
              size: 'P',
              stockMil: 4000,
            ),
            VariantSeed(
              id: 11,
              sku: 'CAM-BASIC-PRETA-M',
              color: 'Preta',
              size: 'M',
              stockMil: 3000,
              order: 1,
            ),
          ],
        );

        final sale = await repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildVariantCartItem(
                productId: 1,
                variantId: 10,
                productName: 'Camiseta Basic',
                sku: 'CAM-BASIC-PRETA-P',
                color: 'Preta',
                size: 'P',
                quantityMil: 2000,
                availableStockMil: 4000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.pix,
          ),
        );

        expect(await loadVariantStock(database, 10), 2000);
        expect(await loadProductStock(database, 1), 5000);

        final movementRows = await loadInventoryMovementRows(database);
        expect(movementRows, hasLength(1));
        expect(movementRows.single['movement_type'], 'sale_out');
        expect(movementRows.single['reference_id'], sale.saleId);
        expect(movementRows.single['product_variant_id'], 10);
        expect(movementRows.single['quantity_delta_mil'], -2000);
        expect(movementRows.single['stock_before_mil'], 4000);
        expect(movementRows.single['stock_after_mil'], 2000);
      },
    );

    test('cancelamento recompõe saldo e grava sale_cancel_in', () async {
      database = await openSaleInventoryTestDatabase();
      final repository = createSaleRepository(database);
      await insertSimpleProduct(
        database,
        productId: 1,
        name: 'Bone',
        stockMil: 5000,
        barcode: 'BON-001',
        salePriceCents: 7500,
      );

      final sale = await repository.completeCashSale(
        input: CheckoutInput(
          items: [
            buildSimpleCartItem(
              productId: 1,
              productName: 'Bone',
              quantityMil: 2000,
              availableStockMil: 5000,
              unitPriceCents: 7500,
              barcode: 'BON-001',
            ),
          ],
          saleType: SaleType.cash,
          paymentMethod: PaymentMethod.pix,
        ),
      );

      await repository.cancelSale(
        saleId: sale.saleId,
        reason: 'Cliente desistiu antes da entrega',
      );

      expect(await loadProductStock(database, 1), 5000);

      final movementRows = await loadInventoryMovementRows(database);
      expect(movementRows, hasLength(2));
      expect(movementRows.last['movement_type'], 'sale_cancel_in');
      expect(movementRows.last['quantity_delta_mil'], 2000);
      expect(movementRows.last['stock_before_mil'], 3000);
      expect(movementRows.last['stock_after_mil'], 5000);
      expect(movementRows.last['notes'], 'Cliente desistiu antes da entrega');

      final saleRows = await database.query(
        TableNames.vendas,
        columns: const ['status'],
        where: 'id = ?',
        whereArgs: [sale.saleId],
        limit: 1,
      );
      expect(saleRows.single['status'], SaleStatus.cancelled.dbValue);
    });

    test('rollback transacional se falhar a gravacao do movimento', () async {
      database = await openSaleInventoryTestDatabase(
        includeInventoryMovements: false,
      );
      final repository = createSaleRepository(database);
      await insertSimpleProduct(
        database,
        productId: 1,
        name: 'Bone',
        stockMil: 5000,
      );

      await expectLater(
        () => repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.pix,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await loadProductStock(database, 1), 5000);
      expect(await countRows(database, TableNames.vendas), 0);
      expect(await countRows(database, TableNames.itensVenda), 0);
    });

    test(
      'checkout offline finaliza venda sem cliente e enfileira sync',
      () async {
        database = await openSaleInventoryTestDatabase();
        final syncMetadataRepository = RecordingSyncMetadataRepository();
        final syncQueueRepository = RecordingSyncQueueRepository();
        final repository = createSaleRepositoryWithRecordingSync(
          database,
          syncMetadataRepository: syncMetadataRepository,
          syncQueueRepository: syncQueueRepository,
        );
        await insertSimpleProduct(
          database,
          productId: 1,
          name: 'Bone',
          stockMil: 5000,
        );

        final sale = await repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.pix,
          ),
        );

        expect(sale.clientId, isNull);
        expect(await countRows(database, TableNames.vendas), 1);
        expect(
          syncQueueRepository.mutations.any(
            (mutation) =>
                mutation.featureKey == SyncFeatureKeys.sales &&
                mutation.localEntityId == sale.saleId,
          ),
          isTrue,
        );
      },
    );

    test('checkout offline finaliza venda com cliente local/cache', () async {
      database = await openSaleInventoryTestDatabase();
      final repository = createSaleRepository(database);
      await insertClient(database, customerId: 7);
      await insertSimpleProduct(
        database,
        productId: 1,
        name: 'Bone',
        stockMil: 5000,
      );

      final sale = await repository.completeCashSale(
        input: CheckoutInput(
          items: [
            buildSimpleCartItem(
              productId: 1,
              productName: 'Bone',
              quantityMil: 1000,
              availableStockMil: 5000,
            ),
          ],
          saleType: SaleType.cash,
          paymentMethod: PaymentMethod.pix,
          clientId: 7,
        ),
      );

      expect(sale.clientId, 7);
      final saleRows = await database.query(
        TableNames.vendas,
        columns: const ['cliente_id'],
        where: 'id = ?',
        whereArgs: [sale.saleId],
        limit: 1,
      );
      expect(saleRows.single['cliente_id'], 7);
    });

    test(
      'fiado offline grava local primeiro e permanece pendente para sync',
      () async {
        database = await openSaleInventoryTestDatabase();
        final syncMetadataRepository = RecordingSyncMetadataRepository();
        final syncQueueRepository = RecordingSyncQueueRepository();
        final repository = createSaleRepositoryWithRecordingSync(
          database,
          syncMetadataRepository: syncMetadataRepository,
          syncQueueRepository: syncQueueRepository,
        );
        await insertClient(database, customerId: 7);
        await insertSimpleProduct(
          database,
          productId: 1,
          name: 'Bone',
          stockMil: 5000,
        );

        final sale = await repository.completeCreditSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
              ),
            ],
            saleType: SaleType.fiado,
            paymentMethod: PaymentMethod.fiado,
            clientId: 7,
            dueDate: DateTime(2026, 5, 26),
          ),
        );

        expect(sale.clientId, 7);
        expect(sale.fiadoId, isNotNull);
        final fiadoRows = await database.query(
          TableNames.fiado,
          where: 'id = ?',
          whereArgs: [sale.fiadoId],
          limit: 1,
        );
        expect(fiadoRows.single['cliente_id'], 7);
        expect(fiadoRows.single['status'], 'pendente');
        expect(
          syncQueueRepository.mutations.any(
            (mutation) =>
                mutation.featureKey == SyncFeatureKeys.sales &&
                mutation.localEntityId == sale.saleId,
          ),
          isTrue,
        );
      },
    );

    test(
      'eventos operacionais de venda usam ids remotos de produto e variante',
      () async {
        database = await openSaleInventoryTestDatabase();
        final operationalQueue = _RecordingOperationalSyncQueueRepository();
        final repository = SqliteSaleRepository.forDatabase(
          databaseLoader: () async => database,
          operationalContext: AppOperationalContext(
            environment: const AppEnvironment.localDefault(),
            session: AppSession.localDefault(),
          ),
          syncMetadataRepository: RecordingSyncMetadataRepository(),
          syncQueueRepository: RecordingSyncQueueRepository(),
          operationalSyncQueueRepository: operationalQueue,
        );
        const productRemoteId = '11111111-1111-4111-8111-111111111111';
        const variantRemoteId = '22222222-2222-4222-8222-222222222222';
        await insertVariantProduct(
          database,
          productId: 1,
          name: 'Camiseta Basic',
          parentStockMil: 4000,
          variants: const [
            VariantSeed(
              id: 10,
              remoteId: variantRemoteId,
              sku: 'CAM-BASIC-PRETA-P',
              color: 'Preta',
              size: 'P',
              stockMil: 4000,
            ),
          ],
        );
        await insertProductRemoteIdentity(
          database,
          productId: 1,
          remoteId: productRemoteId,
        );

        await repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildVariantCartItem(
                productId: 1,
                variantId: 10,
                productName: 'Camiseta Basic',
                sku: 'CAM-BASIC-PRETA-P',
                color: 'Preta',
                size: 'P',
                quantityMil: 1000,
                availableStockMil: 4000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.pix,
          ),
        );

        final saleItem = operationalQueue.events.firstWhere(
          (event) => event.entity == 'saleItem',
        );
        expect(saleItem.payload['productId'], productRemoteId);
        expect(saleItem.payload['productLocalId'], 1);
        expect(saleItem.payload['productVariantId'], variantRemoteId);
        expect(saleItem.payload['productVariantLocalId'], 10);

        final deduction = operationalQueue.events.firstWhere(
          (event) => event.entity == 'stockDeduction',
        );
        expect(deduction.payload['productId'], productRemoteId);
        expect(deduction.payload['productLocalId'], 1);
        expect(deduction.payload['productVariantId'], variantRemoteId);
        expect(deduction.payload['productVariantLocalId'], 10);
      },
    );

    test('bloqueia venda operacional de produto sem identidade remota', () async {
      database = await openSaleInventoryTestDatabase();
      final operationalQueue = _RecordingOperationalSyncQueueRepository();
      final repository = SqliteSaleRepository.forDatabase(
        databaseLoader: () async => database,
        operationalContext: AppOperationalContext(
          environment: const AppEnvironment.localDefault(),
          session: AppSession.localDefault(),
        ),
        syncMetadataRepository: RecordingSyncMetadataRepository(),
        syncQueueRepository: RecordingSyncQueueRepository(),
        operationalSyncQueueRepository: operationalQueue,
      );
      await insertSimpleProduct(
        database,
        productId: 1,
        name: 'Bone',
        stockMil: 5000,
      );

      await expectLater(
        repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
                productRemoteId: null,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.pix,
          ),
        ),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            contains(
              'Este produto ainda não foi sincronizado com a nuvem. Sincronize antes de vender.',
            ),
          ),
        ),
      );

      expect(
        operationalQueue.events.where(
          (event) => event.entity == 'stockDeduction',
        ),
        isEmpty,
      );
      expect(await countRows(database, TableNames.vendas), 0);
    });

    test(
      'venda a vista com caixa fechado e bloqueada antes de gerar movimento',
      () async {
        database = await openSaleInventoryTestDatabase();
        final repository = createSaleRepository(database);
        await database.update(
          TableNames.caixaSessoes,
          {'status': 'fechado', 'fechada_em': '2026-04-16T13:00:00.000Z'},
          where: 'id = ?',
          whereArgs: [1],
        );
        await insertSimpleProduct(
          database,
          productId: 1,
          name: 'Bone',
          stockMil: 5000,
          salePriceCents: 10000,
        );

        await expectLater(
          repository.completeCashSale(
            input: CheckoutInput(
              items: [
                buildSimpleCartItem(
                  productId: 1,
                  productName: 'Bone',
                  quantityMil: 1000,
                  availableStockMil: 5000,
                  unitPriceCents: 10000,
                ),
              ],
              saleType: SaleType.cash,
              paymentMethod: PaymentMethod.cash,
            ),
          ),
          throwsA(
            isA<ValidationException>().having(
              (error) => error.message,
              'message',
              'Abra o caixa antes de registrar venda em dinheiro.',
            ),
          ),
        );

        expect(await countRows(database, TableNames.vendas), 0);
        expect(await countRows(database, TableNames.caixaMovimentos), 0);
      },
    );

    test(
      'venda com desconto grava total liquido no pagamento e no sync operacional',
      () async {
        database = await openSaleInventoryTestDatabase();
        final operationalQueue = _RecordingOperationalSyncQueueRepository();
        final repository = SqliteSaleRepository.forDatabase(
          databaseLoader: () async => database,
          operationalContext: AppOperationalContext(
            environment: const AppEnvironment.localDefault(),
            session: AppSession.localDefault(),
          ),
          syncMetadataRepository: RecordingSyncMetadataRepository(),
          syncQueueRepository: RecordingSyncQueueRepository(),
          operationalSyncQueueRepository: operationalQueue,
        );
        await insertSimpleProduct(
          database,
          productId: 1,
          name: 'Bone',
          stockMil: 5000,
          salePriceCents: 10000,
        );

        final sale = await repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
                unitPriceCents: 10000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.cash,
            discountCents: 1000,
          ),
        );

        final saleRows = await database.query(
          TableNames.vendas,
          columns: const [
            'desconto_centavos',
            'valor_total_centavos',
            'valor_final_centavos',
          ],
          where: 'id = ?',
          whereArgs: [sale.saleId],
          limit: 1,
        );
        expect(saleRows.single['desconto_centavos'], 1000);
        expect(saleRows.single['valor_total_centavos'], 10000);
        expect(saleRows.single['valor_final_centavos'], 9000);

        final paymentRows = await database.query(
          TableNames.caixaMovimentos,
          columns: const ['valor_centavos'],
          where: 'referencia_id = ? AND referencia_tipo = ?',
          whereArgs: [sale.saleId, 'venda'],
        );
        expect(paymentRows.single['valor_centavos'], 9000);

        final saleEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'sale',
        );
        expect(saleEvent.payload['subtotalCents'], 10000);
        expect(saleEvent.payload['discountCents'], 1000);
        expect(saleEvent.payload['totalCents'], 9000);

        final paymentEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'payment',
        );
        expect(paymentEvent.payload['amountCents'], 9000);

        final saleItemEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'saleItem',
        );
        expect(saleItemEvent.payload['unitCostCents'], 4000);
        expect(saleItemEvent.payload['totalCostCents'], 4000);

        final cashMovementEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'cashMovement',
        );
        expect(cashMovementEvent.payload['amountCents'], 9000);
        expect(cashMovementEvent.payload['paymentMethod'], 'dinheiro');
      },
    );

    test(
      'venda operacional referencia a sessao de caixa pelo uuid no sale e no cashMovement',
      () async {
        database = await openSaleInventoryTestDatabase();
        final operationalQueue = _RecordingOperationalSyncQueueRepository();
        final repository = SqliteSaleRepository.forDatabase(
          databaseLoader: () async => database,
          operationalContext: AppOperationalContext(
            environment: const AppEnvironment.localDefault(),
            session: AppSession.localDefault(),
          ),
          syncMetadataRepository: RecordingSyncMetadataRepository(),
          syncQueueRepository: RecordingSyncQueueRepository(),
          operationalSyncQueueRepository: operationalQueue,
        );
        await insertSimpleProduct(
          database,
          productId: 1,
          name: 'Bone',
          stockMil: 5000,
          salePriceCents: 10000,
        );

        await repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
                unitPriceCents: 10000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.cash,
          ),
        );

        final saleEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'sale',
        );
        expect(
          saleEvent.payload['cashSessionLocalId'],
          'test-open-cash-session',
        );
        expect(saleEvent.payload['cashSessionUuid'], 'test-open-cash-session');
        expect(saleEvent.payload['cashSessionLocalNumericId'], 1);

        final cashMovementEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'cashMovement',
        );
        expect(
          cashMovementEvent.payload['cashSessionLocalId'],
          'test-open-cash-session',
        );
        expect(
          cashMovementEvent.payload['cashSessionUuid'],
          'test-open-cash-session',
        );
        expect(cashMovementEvent.payload['cashSessionLocalNumericId'], 1);
      },
    );

    test(
      'sale/create operacional inclui o recebido imediato real quando o troco vira haver',
      () async {
        database = await openSaleInventoryTestDatabase();
        final operationalQueue = _RecordingOperationalSyncQueueRepository();
        final repository = SqliteSaleRepository.forDatabase(
          databaseLoader: () async => database,
          operationalContext: AppOperationalContext(
            environment: const AppEnvironment.localDefault(),
            session: AppSession.localDefault(),
          ),
          syncMetadataRepository: RecordingSyncMetadataRepository(),
          syncQueueRepository: RecordingSyncQueueRepository(),
          operationalSyncQueueRepository: operationalQueue,
        );
        await insertClient(database, customerId: 7);
        await insertSimpleProduct(
          database,
          productId: 1,
          name: 'Bone',
          stockMil: 5000,
          salePriceCents: 10000,
        );

        await repository.completeCashSale(
          input: CheckoutInput(
            items: [
              buildSimpleCartItem(
                productId: 1,
                productName: 'Bone',
                quantityMil: 1000,
                availableStockMil: 5000,
                unitPriceCents: 10000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.cash,
            clientId: 7,
            discountCents: 3000,
            changeLeftAsCreditCents: 3000,
          ),
        );

        final saleEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'sale',
        );
        final paymentEvent = operationalQueue.events.firstWhere(
          (event) => event.entity == 'payment',
        );

        expect(saleEvent.payload['totalCents'], 7000);
        expect(saleEvent.payload['immediateReceivedCents'], 10000);
        expect(saleEvent.payload['creditGeneratedCents'], 3000);
        expect(paymentEvent.payload['amountCents'], 10000);
      },
    );
  });
}

class _RecordingOperationalSyncQueueRepository
    implements OperationalSyncQueueRepository {
  final events = <OperationalSyncEvent>[];

  @override
  Future<bool> enqueue(
    DatabaseExecutor db, {
    required OperationalSyncEvent event,
  }) async {
    events.add(event);
    return true;
  }

  @override
  Future<List<OperationalSyncQueueItem>> listPending({
    required int limit,
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
    DateTime? now,
  }) async => const <OperationalSyncQueueItem>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
