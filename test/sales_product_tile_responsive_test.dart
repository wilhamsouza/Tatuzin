import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin/app/theme/app_theme.dart';
import 'package:tatuzin/modules/estoque/domain/entities/stock_availability.dart';
import 'package:tatuzin/modules/produtos/domain/entities/product.dart';
import 'package:tatuzin/modules/vendas/presentation/pages/sales_page.dart';
import 'package:tatuzin/modules/vendas/presentation/providers/sales_providers.dart';

void main() {
  testWidgets('card do PDV nao estoura em largura compacta e texto grande', (
    tester,
  ) async {
    await _pumpSalesPage(
      tester,
      size: const Size(320, 900),
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Escolher variante'), findsWidgets);
    expect(find.textContaining('Disponivel'), findsOneWidget);
    expect(find.textContaining('A partir de'), findsOneWidget);
  });

  testWidgets('card do PDV preserva comportamento em largura maior', (
    tester,
  ) async {
    await _pumpSalesPage(tester, size: const Size(900, 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Escolher variante'), findsWidgets);
    expect(find.textContaining('Disponivel'), findsOneWidget);
    expect(find.textContaining('variante'), findsWidgets);
  });
}

Future<void> _pumpSalesPage(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        salesCatalogProvider.overrideWith(
          (ref) async => [_buildCatalogEntry()],
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: MaterialApp(theme: AppTheme.light(), home: const SalesPage()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

SalesCatalogEntry _buildCatalogEntry() {
  final product = _buildProduct(
    variants: [
      _buildVariant(
        id: 10,
        sku: 'SKU-PRETO-PROMOCIONAL-GRANDE-2026',
        size: 'GG Especial',
        additionalPriceCents: 123456789,
      ),
      _buildVariant(
        id: 11,
        sku: 'SKU-AZUL-PROMOCIONAL-GRANDE-2026',
        size: 'P',
        additionalPriceCents: 987654321,
      ),
    ],
  );
  return SalesCatalogEntry(
    product: product,
    productAvailability: StockAvailability(
      productId: 1,
      productVariantId: null,
      physicalQuantityMil: 2000000,
      reservedQuantityMil: 1000,
    ),
    availableVariants: product.variants
        .map(
          (variant) => SalesCatalogVariantOption(
            variant: variant,
            availability: StockAvailability(
              productId: 1,
              productVariantId: variant.id,
              physicalQuantityMil: variant.stockMil,
              reservedQuantityMil: 1000,
            ),
          ),
        )
        .toList(growable: false),
  );
}

Product _buildProduct({required List<ProductVariant> variants}) {
  final now = DateTime(2026);
  return Product(
    id: 1,
    uuid: 'product-responsive-1',
    name:
        'Camiseta premium oversized colecao limitada com nome muito longo para testar ellipsis',
    description: null,
    categoryId: 1,
    categoryName: 'Roupas',
    barcode: '78912345678901234567890',
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.fashion,
    catalogType: ProductCatalogTypes.variant,
    modelName:
        'Camiseta premium oversized colecao limitada com nome muito longo para testar ellipsis',
    variantLabel: 'Tamanho/Cor',
    baseProductId: null,
    baseProductName: null,
    variants: variants,
    unitMeasure: 'unidade',
    costCents: 4000,
    manualCostCents: 4000,
    costSource: ProductCostSource.manual,
    salePriceCents: 999999999,
    stockMil: 4000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: '11111111-1111-4111-8111-111111111111',
  );
}

ProductVariant _buildVariant({
  required int id,
  required String sku,
  required String size,
  required int additionalPriceCents,
}) {
  final now = DateTime(2026);
  return ProductVariant(
    id: id,
    uuid: 'variant-responsive-$id',
    remoteId: '22222222-2222-4222-8222-22222222222$id',
    productId: 1,
    sku: sku,
    colorLabel: 'Preta super longa',
    sizeLabel: size,
    priceAdditionalCents: additionalPriceCents,
    stockMil: 2000000,
    sortOrder: id,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}
