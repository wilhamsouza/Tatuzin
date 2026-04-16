import 'package:flutter_test/flutter_test.dart';

import 'package:erp_pdv_app/app/core/sync/sync_status.dart';
import 'package:erp_pdv_app/modules/produtos/data/models/product_recipe_sync_payload.dart';
import 'package:erp_pdv_app/modules/produtos/data/models/remote_product_recipe_record.dart';

void main() {
  test('product recipe sync payload stays atomic by product', () {
    final record = RemoteProductRecipeRecord.fromSyncPayload(
      ProductRecipeSyncPayload(
        productId: 1,
        productUuid: 'product-uuid',
        productRemoteId: 'product-remote',
        remoteId: null,
        createdAt: DateTime.parse('2026-04-15T12:00:00Z'),
        updatedAt: DateTime.parse('2026-04-15T12:10:00Z'),
        syncStatus: SyncStatus.pendingUpload,
        lastSyncedAt: null,
        items: [
          ProductRecipeSyncItemPayload(
            recipeItemId: 1,
            recipeItemUuid: 'recipe-item-1',
            supplyLocalId: 10,
            supplyRemoteId: 'supply-remote-1',
            quantityUsedMil: 150,
            unitType: 'g',
            wasteBasisPoints: 500,
            notes: 'Fatia padrao',
            createdAt: _recipeCreatedAt,
            updatedAt: _recipeUpdatedAt,
          ),
          ProductRecipeSyncItemPayload(
            recipeItemId: 2,
            recipeItemUuid: 'recipe-item-2',
            supplyLocalId: 20,
            supplyRemoteId: 'supply-remote-2',
            quantityUsedMil: 1,
            unitType: 'un',
            wasteBasisPoints: 0,
            notes: null,
            createdAt: _recipeCreatedAt,
            updatedAt: _recipeUpdatedAt,
          ),
        ],
      ),
    );

    final body = record.toUpsertBody();
    final items = body['items'] as List<dynamic>;

    expect(body['productLocalUuid'], 'product-uuid');
    expect(items, hasLength(2));
    expect(items.first, <String, dynamic>{
      'localUuid': 'recipe-item-1',
      'supplyId': 'supply-remote-1',
      'quantityUsedMil': 150,
      'unitType': 'g',
      'wasteBasisPoints': 500,
      'notes': 'Fatia padrao',
    });
    expect(items.last, <String, dynamic>{
      'localUuid': 'recipe-item-2',
      'supplyId': 'supply-remote-2',
      'quantityUsedMil': 1,
      'unitType': 'un',
      'wasteBasisPoints': 0,
      'notes': null,
    });
  });
}

final _recipeCreatedAt = DateTime.parse('2026-04-15T12:00:00Z');
final _recipeUpdatedAt = DateTime.parse('2026-04-15T12:10:00Z');
