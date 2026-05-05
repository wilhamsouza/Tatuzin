import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/carrinho/presentation/providers/cart_provider.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_availability.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:erp_pdv_app/modules/estoque/domain/repositories/stock_availability_repository.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/repositories/product_repository.dart';
import 'package:erp_pdv_app/modules/vendas/presentation/pages/sales_page.dart';
import 'package:erp_pdv_app/modules/vendas/presentation/providers/sales_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_tenant_session.dart';

void main() {
  testWidgets('produto com grade abre selecao antes de entrar no carrinho', (
    tester,
  ) async {
    final product = _buildProduct(
      variants: [
        _buildVariant(id: 10, sku: 'CAM-PRE-P', size: 'P'),
        _buildVariant(id: 11, sku: 'CAM-PRE-G', size: 'G'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        ...testTenantBootstrapOverrides(),
        salesCatalogRepositoryProvider.overrideWithValue(
          _FakeProductRepository([product]),
        ),
        stockAvailabilityRepositoryProvider.overrideWithValue(
          _FakeStockAvailabilityRepository({
            const StockReservationProductKey(
              productId: 1,
              productVariantId: 10,
            ): StockAvailability(
              productId: 1,
              productVariantId: 10,
              physicalQuantityMil: 2000,
              reservedQuantityMil: 0,
            ),
            const StockReservationProductKey(
              productId: 1,
              productVariantId: 11,
            ): StockAvailability(
              productId: 1,
              productVariantId: 11,
              physicalQuantityMil: 2000,
              reservedQuantityMil: 0,
            ),
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    setTestTenantSession(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const SalesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(cartProvider).items, isEmpty);
    expect(find.text('Escolher variante'), findsWidgets);

    await tester.tap(find.text('Escolher variante').last);
    await tester.pumpAndSettle();

    expect(find.text('Adicionar variante'), findsOneWidget);
    expect(container.read(cartProvider).items, isEmpty);

    await tester.tap(find.text('G').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar variante'));
    await tester.pumpAndSettle();

    final items = container.read(cartProvider).items;
    expect(items, hasLength(1));
    expect(items.single.productVariantId, 11);
    expect(items.single.variantSku, 'CAM-PRE-G');
    expect(items.single.variantColorLabel, 'Preta');
    expect(items.single.variantSizeLabel, 'G');
  });
}

class _FakeStockAvailabilityRepository implements StockAvailabilityRepository {
  const _FakeStockAvailabilityRepository(this.availabilityByKey);

  final Map<StockReservationProductKey, StockAvailability> availabilityByKey;

  @override
  Future<StockAvailability> getAvailability({
    required int productId,
    required int? productVariantId,
  }) async {
    final key = StockReservationProductKey(
      productId: productId,
      productVariantId: productVariantId,
    );
    final availability = availabilityByKey[key];
    if (availability == null) {
      throw StateError('Disponibilidade fake ausente para $key');
    }
    return availability;
  }

  @override
  Future<Map<StockReservationProductKey, StockAvailability>>
  getAvailabilityByProductKeys(
    Iterable<StockReservationProductKey> keys,
  ) async {
    return {
      for (final key in keys)
        key:
            availabilityByKey[key] ??
            StockAvailability(
              productId: key.productId,
              productVariantId: key.productVariantId,
              physicalQuantityMil: 0,
              reservedQuantityMil: 0,
            ),
    };
  }
}

class _FakeProductRepository implements ProductRepository {
  const _FakeProductRepository(this.products);

  final List<Product> products;

  @override
  Future<List<Product>> search({String query = ''}) async => products;

  @override
  Future<List<Product>> searchAvailable({String query = ''}) async => products;

  @override
  Future<int> create(ProductInput input) => throw UnimplementedError();

  @override
  Future<void> update(int id, ProductInput input) => throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();
}

Product _buildProduct({required List<ProductVariant> variants}) {
  final now = DateTime(2026);
  return Product(
    id: 1,
    uuid: 'product-1',
    name: 'Camiseta Verao 2026',
    description: null,
    categoryId: 1,
    categoryName: 'Roupas',
    barcode: null,
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.fashion,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    variants: variants,
    unitMeasure: 'un',
    costCents: 4000,
    manualCostCents: 4000,
    costSource: ProductCostSource.manual,
    salePriceCents: 6000,
    stockMil: 4000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

ProductVariant _buildVariant({
  required int id,
  required String sku,
  required String size,
}) {
  final now = DateTime(2026);
  return ProductVariant(
    id: id,
    uuid: 'variant-$id',
    productId: 1,
    sku: sku,
    colorLabel: 'Preta',
    sizeLabel: size,
    priceAdditionalCents: 0,
    stockMil: 2000,
    sortOrder: id,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}
