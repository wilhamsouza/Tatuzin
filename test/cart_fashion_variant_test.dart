import 'package:erp_pdv_app/modules/carrinho/presentation/providers/cart_provider.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_availability.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/stock_reservation.dart';
import 'package:erp_pdv_app/modules/estoque/domain/repositories/stock_availability_repository.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
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

  test('incremento revalida disponibilidade atual do estoque', () async {
    final repository = _MutableStockAvailabilityRepository();
    final container = ProviderContainer(
      overrides: [
        stockAvailabilityRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final product = _buildProduct(stockMil: 1000);
    repository.setAvailability(productId: product.id, availableMil: 1000);

    expect(container.read(cartProvider.notifier).addProduct(product), isTrue);
    expect(
      await container
          .read(cartProvider.notifier)
          .increaseQuantityRevalidated(
            container.read(cartProvider).items.single.id,
          ),
      isFalse,
    );
    expect(container.read(cartProvider).items.single.quantityMil, 1000);

    repository.setAvailability(productId: product.id, availableMil: 2000);

    expect(
      await container
          .read(cartProvider.notifier)
          .increaseQuantityRevalidated(
            container.read(cartProvider).items.single.id,
          ),
      isTrue,
    );
    final item = container.read(cartProvider).items.single;
    expect(item.quantityMil, 2000);
    expect(item.availableStockMil, 2000);
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

class _MutableStockAvailabilityRepository
    implements StockAvailabilityRepository {
  final _availableByKey = <StockReservationProductKey, int>{};

  void setAvailability({
    required int productId,
    int? productVariantId,
    required int availableMil,
  }) {
    _availableByKey[StockReservationProductKey(
          productId: productId,
          productVariantId: productVariantId,
        )] =
        availableMil;
  }

  @override
  Future<StockAvailability> getAvailability({
    required int productId,
    required int? productVariantId,
  }) async {
    final key = StockReservationProductKey(
      productId: productId,
      productVariantId: productVariantId,
    );
    final availableMil = _availableByKey[key] ?? 0;
    return StockAvailability(
      productId: productId,
      productVariantId: productVariantId,
      physicalQuantityMil: availableMil,
      reservedQuantityMil: 0,
    );
  }

  @override
  Future<Map<StockReservationProductKey, StockAvailability>>
  getAvailabilityByProductKeys(
    Iterable<StockReservationProductKey> keys,
  ) async {
    return {
      for (final key in keys)
        key: StockAvailability(
          productId: key.productId,
          productVariantId: key.productVariantId,
          physicalQuantityMil: _availableByKey[key] ?? 0,
          reservedQuantityMil: 0,
        ),
    };
  }
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
