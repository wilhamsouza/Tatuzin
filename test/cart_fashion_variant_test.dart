import 'package:erp_pdv_app/modules/carrinho/presentation/providers/cart_provider.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('produto simples adiciona direto ao carrinho', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final added = container
        .read(cartProvider.notifier)
        .addProduct(_buildProduct());

    expect(added, isTrue);
    expect(container.read(cartProvider).items, hasLength(1));
    expect(container.read(cartProvider).items.single.productVariantId, isNull);
  });

  test('produto com grade nao entra no carrinho sem productVariantId', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final added = container
        .read(cartProvider.notifier)
        .addProduct(
          _buildProduct(
            variants: [_buildVariant(id: 10, sku: 'CAM-PRE-P', size: 'P')],
          ),
        );

    expect(added, isFalse);
    expect(container.read(cartProvider).items, isEmpty);
  });

  test('produto simples nao entra no carrinho se disponivel real for zero', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final added = container
        .read(cartProvider.notifier)
        .addProduct(_buildProduct(stockMil: 0));

    expect(added, isFalse);
    expect(container.read(cartProvider).items, isEmpty);
  });

  test(
    'produto com grade nao entra no carrinho se disponivel real for zero',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final added = container
          .read(cartProvider.notifier)
          .addProduct(
            _buildProduct(
              sellableVariantId: 10,
              sellableVariantSku: 'CAM-PRE-G',
              sellableVariantColorLabel: 'Preta',
              sellableVariantSizeLabel: 'G',
              stockMil: 0,
            ),
          );

      expect(added, isFalse);
      expect(container.read(cartProvider).items, isEmpty);
    },
  );

  test('ao selecionar variantes, carrinho preserva SKU cor e tamanho', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final variantP = _buildProduct(
      sellableVariantId: 10,
      sellableVariantSku: 'CAM-PRE-P',
      sellableVariantColorLabel: 'Preta',
      sellableVariantSizeLabel: 'P',
      stockMil: 2000,
    );
    final variantG = _buildProduct(
      sellableVariantId: 11,
      sellableVariantSku: 'CAM-PRE-G',
      sellableVariantColorLabel: 'Preta',
      sellableVariantSizeLabel: 'G',
      stockMil: 2000,
    );

    expect(container.read(cartProvider.notifier).addProduct(variantP), isTrue);
    expect(container.read(cartProvider.notifier).addProduct(variantG), isTrue);

    final items = container.read(cartProvider).items;
    expect(items, hasLength(2));
    expect(items.map((item) => item.productVariantId), containsAll([10, 11]));
    expect(
      items.map((item) => item.variantSku),
      containsAll(['CAM-PRE-P', 'CAM-PRE-G']),
    );
    expect(items.map((item) => item.variantColorLabel), everyElement('Preta'));
    expect(items.map((item) => item.variantSizeLabel), containsAll(['P', 'G']));
  });

  test('carrinho nao aumenta quantidade acima do disponivel real recebido', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final product = _buildProduct(stockMil: 1000);

    expect(container.read(cartProvider.notifier).addProduct(product), isTrue);
    expect(container.read(cartProvider.notifier).addProduct(product), isFalse);
    expect(container.read(cartProvider).items.single.quantityMil, 1000);
  });
}

Product _buildProduct({
  int id = 1,
  int stockMil = 5000,
  List<ProductVariant> variants = const <ProductVariant>[],
  int? sellableVariantId,
  String? sellableVariantSku,
  String? sellableVariantColorLabel,
  String? sellableVariantSizeLabel,
}) {
  final now = DateTime(2026);
  return Product(
    id: id,
    uuid: 'product-$id',
    name: 'Camiseta Basic',
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
    salePriceCents: 9900,
    stockMil: stockMil,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    sellableVariantId: sellableVariantId,
    sellableVariantSku: sellableVariantSku,
    sellableVariantColorLabel: sellableVariantColorLabel,
    sellableVariantSizeLabel: sellableVariantSizeLabel,
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
