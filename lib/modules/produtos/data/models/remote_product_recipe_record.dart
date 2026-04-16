import 'product_recipe_sync_payload.dart';

class RemoteProductRecipeRecord {
  const RemoteProductRecipeRecord({
    required this.productRemoteId,
    required this.productLocalUuid,
    required this.productName,
    required this.updatedAt,
    required this.items,
  });

  factory RemoteProductRecipeRecord.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    return RemoteProductRecipeRecord(
      productRemoteId: json['productId'] as String? ?? '',
      productLocalUuid: json['productLocalUuid'] as String? ?? '',
      productName: json['productName'] as String? ?? 'Produto',
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      items: itemsJson is List
          ? itemsJson
                .whereType<Map<String, dynamic>>()
                .map(RemoteProductRecipeItemRecord.fromJson)
                .toList(growable: false)
          : const <RemoteProductRecipeItemRecord>[],
    );
  }

  factory RemoteProductRecipeRecord.fromSyncPayload(
    ProductRecipeSyncPayload payload,
  ) {
    return RemoteProductRecipeRecord(
      productRemoteId: payload.productRemoteId ?? payload.remoteId ?? '',
      productLocalUuid: payload.productUuid,
      productName: '',
      updatedAt: payload.updatedAt,
      items: payload.items
          .map(RemoteProductRecipeItemRecord.fromSyncPayload)
          .toList(growable: false),
    );
  }

  final String productRemoteId;
  final String productLocalUuid;
  final String productName;
  final DateTime updatedAt;
  final List<RemoteProductRecipeItemRecord> items;

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'productLocalUuid': productLocalUuid,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class RemoteProductRecipeItemRecord {
  const RemoteProductRecipeItemRecord({
    required this.remoteId,
    required this.localUuid,
    required this.supplyRemoteId,
    required this.supplyLocalUuid,
    required this.supplyName,
    required this.quantityUsedMil,
    required this.unitType,
    required this.wasteBasisPoints,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RemoteProductRecipeItemRecord.fromJson(Map<String, dynamic> json) {
    return RemoteProductRecipeItemRecord(
      remoteId: json['id'] as String? ?? '',
      localUuid: json['localUuid'] as String? ?? '',
      supplyRemoteId: json['supplyId'] as String?,
      supplyLocalUuid: json['supplyLocalUuid'] as String?,
      supplyName: json['supplyName'] as String? ?? 'Insumo',
      quantityUsedMil: json['quantityUsedMil'] as int? ?? 0,
      unitType: json['unitType'] as String? ?? 'un',
      wasteBasisPoints: json['wasteBasisPoints'] as int? ?? 0,
      notes: json['notes'] as String?,
      createdAt: json['createdAt'] == null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  factory RemoteProductRecipeItemRecord.fromSyncPayload(
    ProductRecipeSyncItemPayload payload,
  ) {
    return RemoteProductRecipeItemRecord(
      remoteId: '',
      localUuid: payload.recipeItemUuid,
      supplyRemoteId: payload.supplyRemoteId,
      supplyLocalUuid: null,
      supplyName: '',
      quantityUsedMil: payload.quantityUsedMil,
      unitType: payload.unitType,
      wasteBasisPoints: payload.wasteBasisPoints,
      notes: payload.notes,
      createdAt: payload.createdAt,
      updatedAt: payload.updatedAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String? supplyRemoteId;
  final String? supplyLocalUuid;
  final String supplyName;
  final int quantityUsedMil;
  final String unitType;
  final int wasteBasisPoints;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'supplyId': supplyRemoteId,
      'quantityUsedMil': quantityUsedMil,
      'unitType': unitType,
      'wasteBasisPoints': wasteBasisPoints,
      'notes': notes,
    };
  }
}
