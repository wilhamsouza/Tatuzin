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
}
