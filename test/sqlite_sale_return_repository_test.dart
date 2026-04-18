import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:erp_pdv_app/modules/historico_vendas/domain/entities/sale_return.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/checkout_input.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';

import 'support/sale_inventory_test_support.dart';

void main() {
  initializeSaleInventoryTestSupport();

  group('SqliteSaleReturnRepository inventory integration', () {
    late Database database;

    tearDown(() async {
      await database.close();
    });

    test('devolucao com retorno fisico grava return_in', () async {
      database = await openSaleInventoryTestDatabase();
      final saleRepository = createSaleRepository(database);
      final repository = createSaleReturnRepository(
        database,
        saleRepository: saleRepository,
      );

      await insertClient(database, customerId: 1);
      await insertVariantProduct(
        database,
        productId: 1,
        name: 'Camiseta Basic',
        parentStockMil: 1000,
        variants: const [
          VariantSeed(
            id: 10,
            sku: 'CAM-BASIC-PRETA-P',
            color: 'Preta',
            size: 'P',
            stockMil: 1000,
          ),
        ],
      );

      final sale = await saleRepository.completeCashSale(
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
              availableStockMil: 1000,
            ),
          ],
          saleType: SaleType.cash,
          paymentMethod: PaymentMethod.pix,
          clientId: 1,
        ),
      );
      final saleItemId = await loadLatestSaleItemId(database, sale.saleId);

      final result = await repository.registerReturn(
        SaleReturnInput(
          saleId: sale.saleId,
          mode: SaleReturnMode.returnOnly,
          reason: 'Cliente preferiu outro tamanho',
          returnedItems: [
            SaleReturnItemInput(saleItemId: saleItemId, quantityMil: 1000),
          ],
        ),
      );

      expect(result.mode, SaleReturnMode.returnOnly);
      expect(await loadVariantStock(database, 10), 1000);
      expect(await loadProductStock(database, 1), 1000);

      final movementRows = await loadInventoryMovementRows(database);
      expect(movementRows.map((row) => row['movement_type']), [
        'sale_out',
        'return_in',
      ]);
      expect(movementRows.last['reference_type'], 'sale_return');
      expect(movementRows.last['reference_id'], result.saleReturnId);
      expect(movementRows.last['product_variant_id'], 10);
      expect(movementRows.last['quantity_delta_mil'], 1000);
      expect(movementRows.last['stock_before_mil'], 0);
      expect(movementRows.last['stock_after_mil'], 1000);
      expect(movementRows.last['notes'], 'Cliente preferiu outro tamanho');
    });

    test(
      'troca com item devolvido e reposicao grava return_in e exchange_out',
      () async {
        database = await openSaleInventoryTestDatabase();
        final saleRepository = createSaleRepository(database);
        final repository = createSaleReturnRepository(
          database,
          saleRepository: saleRepository,
        );

        await insertClient(database, customerId: 1);
        await insertVariantProduct(
          database,
          productId: 1,
          name: 'Camiseta Basic',
          parentStockMil: 3000,
          variants: const [
            VariantSeed(
              id: 10,
              sku: 'CAM-BASIC-PRETA-P',
              color: 'Preta',
              size: 'P',
              stockMil: 1000,
            ),
            VariantSeed(
              id: 11,
              sku: 'CAM-BASIC-PRETA-M',
              color: 'Preta',
              size: 'M',
              stockMil: 2000,
              order: 1,
            ),
          ],
        );

        final sale = await saleRepository.completeCashSale(
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
                availableStockMil: 1000,
                unitPriceCents: 12000,
              ),
            ],
            saleType: SaleType.cash,
            paymentMethod: PaymentMethod.pix,
            clientId: 1,
          ),
        );
        final saleItemId = await loadLatestSaleItemId(database, sale.saleId);

        final result = await repository.registerReturn(
          SaleReturnInput(
            saleId: sale.saleId,
            mode: SaleReturnMode.exchangeWithNewSale,
            reason: 'Troca de tamanho',
            returnedItems: [
              SaleReturnItemInput(saleItemId: saleItemId, quantityMil: 1000),
            ],
            replacementItems: [
              buildVariantCartItem(
                productId: 1,
                variantId: 11,
                productName: 'Camiseta Basic',
                sku: 'CAM-BASIC-PRETA-M',
                color: 'Preta',
                size: 'M',
                quantityMil: 1000,
                availableStockMil: 2000,
                unitPriceCents: 15000,
              ),
            ],
            replacementPaymentMethod: PaymentMethod.pix,
          ),
        );

        expect(result.mode, SaleReturnMode.exchangeWithNewSale);
        expect(result.replacementSaleId, isNotNull);
        expect(await loadVariantStock(database, 10), 1000);
        expect(await loadVariantStock(database, 11), 1000);
        expect(await loadProductStock(database, 1), 2000);

        final movementRows = await loadInventoryMovementRows(database);
        expect(movementRows, hasLength(3));
        expect(movementRows[0]['movement_type'], 'sale_out');
        expect(movementRows[1]['movement_type'], 'return_in');
        expect(movementRows[2]['movement_type'], 'exchange_out');
        expect(movementRows[1]['reference_id'], result.saleReturnId);
        expect(movementRows[2]['reference_id'], result.saleReturnId);
        expect(movementRows[1]['product_variant_id'], 10);
        expect(movementRows[2]['product_variant_id'], 11);
        expect(movementRows[1]['quantity_delta_mil'], 1000);
        expect(movementRows[2]['quantity_delta_mil'], -1000);
        expect(movementRows[2]['stock_before_mil'], 2000);
        expect(movementRows[2]['stock_after_mil'], 1000);
      },
    );
  });
}
