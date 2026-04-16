import 'package:erp_pdv_app/app/core/sync/sync_status.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product_profitability_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductProfitabilityRow', () {
    test('nao penaliza produto sem ficha tecnica e custo manual', () {
      final row = ProductProfitabilityRow.fromProduct(
        _buildProduct(
          costSource: ProductCostSource.manual,
          costCents: 850,
          manualCostCents: 850,
        ),
      );

      expect(row.hasDerivedCalculation, isFalse);
      expect(row.marginStatus, ProductProfitabilityMarginStatus.notAvailable);
      expect(row.sourceLabel, 'Custo manual');
      expect(row.contextLabel, 'Sem ficha tecnica');
    });

    test('classifica produto com ficha tecnica e margem baixa', () {
      final row = ProductProfitabilityRow.fromProduct(
        _buildProduct(
          costSource: ProductCostSource.recipeSnapshot,
          costCents: 1800,
          manualCostCents: 900,
          variableCostSnapshotCents: 1800,
          estimatedGrossMarginCents: 200,
          estimatedGrossMarginPercentBasisPoints: 1000,
          lastCostUpdatedAt: DateTime(2026, 4, 15, 10),
        ),
      );

      expect(row.hasDerivedCalculation, isTrue);
      expect(row.marginStatus, ProductProfitabilityMarginStatus.attention);
      expect(row.sourceLabel, 'Calculo derivado');
      expect(row.contextLabel, 'Ficha tecnica ativa');
    });

    test('classifica produto com ficha tecnica e margem saudavel', () {
      final row = ProductProfitabilityRow.fromProduct(
        _buildProduct(
          costSource: ProductCostSource.recipeSnapshot,
          costCents: 1200,
          manualCostCents: 700,
          variableCostSnapshotCents: 1200,
          estimatedGrossMarginCents: 1800,
          estimatedGrossMarginPercentBasisPoints: 6000,
          lastCostUpdatedAt: DateTime(2026, 4, 15, 10),
        ),
      );

      expect(row.hasDerivedCalculation, isTrue);
      expect(row.marginStatus, ProductProfitabilityMarginStatus.healthy);
    });
  });
}

Product _buildProduct({
  required ProductCostSource costSource,
  required int costCents,
  required int manualCostCents,
  int? variableCostSnapshotCents,
  int? estimatedGrossMarginCents,
  int? estimatedGrossMarginPercentBasisPoints,
  DateTime? lastCostUpdatedAt,
}) {
  return Product(
    id: 1,
    uuid: 'product-1',
    name: 'X-Burger',
    description: null,
    categoryId: 1,
    categoryName: 'Lanches',
    barcode: null,
    primaryPhotoPath: null,
    productType: 'unidade',
    niche: ProductNiches.food,
    catalogType: ProductCatalogTypes.simple,
    modelName: null,
    variantLabel: null,
    baseProductId: null,
    baseProductName: null,
    unitMeasure: 'un',
    costCents: costCents,
    manualCostCents: manualCostCents,
    costSource: costSource,
    variableCostSnapshotCents: variableCostSnapshotCents,
    estimatedGrossMarginCents: estimatedGrossMarginCents,
    estimatedGrossMarginPercentBasisPoints:
        estimatedGrossMarginPercentBasisPoints,
    lastCostUpdatedAt: lastCostUpdatedAt,
    salePriceCents: 2000,
    stockMil: 1000,
    isActive: true,
    createdAt: DateTime(2026, 4, 1),
    updatedAt: DateTime(2026, 4, 15),
    deletedAt: null,
    remoteId: null,
    syncStatus: SyncStatus.localOnly,
    lastSyncedAt: null,
  );
}
