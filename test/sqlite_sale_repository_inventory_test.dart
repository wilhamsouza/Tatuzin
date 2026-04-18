import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/checkout_input.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';

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
  });
}
