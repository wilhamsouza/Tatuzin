import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/services/product_permission_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitiza custos de produto herdado do cache para leitura de Caixa', () {
    final product = _productWithCost();

    final sanitized = ProductPermissionSanitizer.sanitizeForSalesRead(product);

    expect(sanitized.costCents, 0);
    expect(sanitized.manualCostCents, 0);
    expect(sanitized.variableCostSnapshotCents, isNull);
    expect(sanitized.estimatedGrossMarginCents, isNull);
    expect(sanitized.estimatedGrossMarginPercentBasisPoints, isNull);
    expect(sanitized.lastCostUpdatedAt, isNull);
    expect(sanitized.salePriceCents, product.salePriceCents);
    expect(sanitized.stockMil, product.stockMil);
    expect(sanitized.name, product.name);
  });
}

Product _productWithCost() {
  final now = DateTime(2026, 5, 20, 10);
  return Product(
    id: 1,
    uuid: 'produto-cache-owner',
    name: 'Cafe coado',
    description: 'Produto com custo antigo no cache',
    categoryId: 1,
    categoryName: 'Bebidas',
    barcode: '789000000001',
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    unitMeasure: 'un',
    costCents: 450,
    manualCostCents: 450,
    costSource: ProductCostSource.recipeSnapshot,
    variableCostSnapshotCents: 450,
    estimatedGrossMarginCents: 550,
    estimatedGrossMarginPercentBasisPoints: 5500,
    lastCostUpdatedAt: now,
    salePriceCents: 1000,
    stockMil: 12000,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    remoteId: 'remote-produto-cache-owner',
  );
}
