import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../../../app/core/sync/sync_queue_operation.dart';
import '../../../produtos/data/support/product_cost_database_support.dart';

abstract final class SupplyLinkedProductSupport {
  static Future<void> recalculateLinkedProducts(
    DatabaseExecutor txn, {
    required Iterable<int> supplyIds,
    required DateTime changedAt,
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required SqliteSyncQueueRepository syncQueueRepository,
  }) async {
    final normalizedSupplyIds = supplyIds.toSet().toList(growable: false);
    if (normalizedSupplyIds.isEmpty) {
      return;
    }

    final placeholders = List.filled(normalizedSupplyIds.length, '?').join(',');
    final productRows = await txn.rawQuery(
      '''
      SELECT DISTINCT
        p.id,
        p.uuid,
        p.criado_em
      FROM ${TableNames.productRecipeItems} pri
      INNER JOIN ${TableNames.produtos} p
        ON p.id = pri.product_id
      WHERE pri.supply_id IN ($placeholders)
        AND p.deletado_em IS NULL
      ORDER BY p.id ASC
    ''',
      normalizedSupplyIds,
    );

    for (final productRow in productRows) {
      final productId = productRow['id'] as int;
      final productUuid = productRow['uuid'] as String;
      final createdAt = DateTime.parse(productRow['criado_em'] as String);

      await ProductCostDatabaseSupport.recalculateAndPersistForProduct(
        txn,
        productId: productId,
        changedAt: changedAt,
      );
      await _markProductForSync(
        txn,
        syncMetadataRepository: syncMetadataRepository,
        syncQueueRepository: syncQueueRepository,
        productId: productId,
        productUuid: productUuid,
        createdAt: createdAt,
        updatedAt: changedAt,
      );
    }
  }

  static Future<void> _markProductForSync(
    DatabaseExecutor txn, {
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required SqliteSyncQueueRepository syncQueueRepository,
    required int productId,
    required String productUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final metadata = await syncMetadataRepository.findByLocalId(
      txn,
      featureKey: SyncFeatureKeys.products,
      localId: productId,
    );

    if (metadata == null) {
      await syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.products,
        localId: productId,
        localUuid: productUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      await syncQueueRepository.enqueueMutation(
        txn,
        featureKey: SyncFeatureKeys.products,
        entityType: 'product',
        localEntityId: productId,
        localUuid: productUuid,
        remoteId: null,
        operation: SyncQueueOperation.create,
        localUpdatedAt: updatedAt,
      );
      return;
    }

    await syncMetadataRepository.markPendingUpdate(
      txn,
      featureKey: SyncFeatureKeys.products,
      localId: productId,
      localUuid: productUuid,
      remoteId: metadata.identity.remoteId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    await syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.products,
      entityType: 'product',
      localEntityId: productId,
      localUuid: productUuid,
      remoteId: metadata.identity.remoteId,
      operation: metadata.identity.remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
  }
}
