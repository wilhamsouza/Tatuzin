import 'package:flutter_test/flutter_test.dart';

import 'package:erp_pdv_app/modules/produtos/data/models/remote_product_record.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';

void main() {
  test('remote product json keeps cost source and snapshots explicit', () {
    final record = RemoteProductRecord.fromJson({
      'id': 'product-remote',
      'localUuid': 'product-uuid',
      'name': 'X-Burger',
      'productType': 'unidade',
      'niche': 'alimentacao',
      'catalogType': 'simple',
      'unitMeasure': 'un',
      'costPriceCents': 1890,
      'manualCostCents': 1200,
      'costSource': 'recipe_snapshot',
      'variableCostSnapshotCents': 1890,
      'estimatedGrossMarginCents': 1110,
      'estimatedGrossMarginPercentBasisPoints': 3700,
      'lastCostUpdatedAt': '2026-04-15T12:00:00Z',
      'salePriceCents': 3000,
      'stockMil': 1000,
      'isActive': true,
      'createdAt': '2026-04-15T11:00:00Z',
      'updatedAt': '2026-04-15T12:05:00Z',
      'variants': const [],
      'modifierGroups': const [],
    });

    expect(record.manualCostCents, 1200);
    expect(record.costSource, ProductCostSource.recipeSnapshot);
    expect(record.variableCostSnapshotCents, 1890);
    expect(record.estimatedGrossMarginCents, 1110);
    expect(record.estimatedGrossMarginPercentBasisPoints, 3700);
    expect(
      record.toUpsertBody()['costSource'],
      ProductCostSource.recipeSnapshot.storageValue,
    );
  });

  test('product upsert body uses backend datetime and numeric contract', () {
    final record = RemoteProductRecord(
      remoteId: '',
      localUuid: 'local-product-1',
      remoteCategoryId: '00000000-0000-4000-8000-000000000001',
      name: 'Produto simples',
      description: null,
      barcode: null,
      productType: 'unidade',
      niche: ProductNiches.food,
      catalogType: ProductCatalogTypes.simple,
      modelName: null,
      variantLabel: null,
      unitMeasure: 'un',
      costCents: 1000,
      manualCostCents: 1000,
      costSource: ProductCostSource.manual,
      variableCostSnapshotCents: null,
      estimatedGrossMarginCents: null,
      estimatedGrossMarginPercentBasisPoints: null,
      lastCostUpdatedAt: DateTime(2026, 4, 27, 20, 10, 30),
      salePriceCents: 1500,
      stockMil: 6000,
      variants: const [],
      modifierGroups: const [],
      isActive: true,
      createdAt: DateTime(2026, 4, 27, 20, 10),
      updatedAt: DateTime(2026, 4, 27, 20, 10),
      deletedAt: null,
    );

    final body = record.toUpsertBody();

    expect(body['costPriceCents'], 1000);
    expect(body['manualCostCents'], 1000);
    expect(body['salePriceCents'], 1500);
    expect(body['stockMil'], 6000);
    expect(body['categoryId'], record.remoteCategoryId);
    expect(body['unitMeasure'], 'un');
    expect(body['catalogType'], ProductCatalogTypes.simple);
    expect(body['variants'], isEmpty);
    expect(body['lastCostUpdatedAt'], endsWith('Z'));
    expect(body['lastCostUpdatedAt'], contains('T'));
  });
}
