import '../../../../app/core/sync/sync_status.dart';

class ProductRecipeSyncPayload {
  const ProductRecipeSyncPayload({
    required this.productId,
    required this.productUuid,
    required this.productRemoteId,
    required this.remoteId,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.items,
  });

  final int productId;
  final String productUuid;
  final String? productRemoteId;
  final String? remoteId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus? syncStatus;
  final DateTime? lastSyncedAt;
  final List<ProductRecipeSyncItemPayload> items;

  bool get hasItems => items.isNotEmpty;
}

class ProductRecipeSyncItemPayload {
  const ProductRecipeSyncItemPayload({
    required this.recipeItemId,
    required this.recipeItemUuid,
    required this.supplyLocalId,
    required this.supplyRemoteId,
    required this.quantityUsedMil,
    required this.unitType,
    required this.wasteBasisPoints,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int recipeItemId;
  final String recipeItemUuid;
  final int supplyLocalId;
  final String? supplyRemoteId;
  final int quantityUsedMil;
  final String unitType;
  final int wasteBasisPoints;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}
