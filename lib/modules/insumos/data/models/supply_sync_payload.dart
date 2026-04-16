import '../../../../app/core/sync/sync_status.dart';

class SupplySyncPayload {
  const SupplySyncPayload({
    required this.supplyId,
    required this.supplyUuid,
    required this.remoteId,
    required this.defaultSupplierLocalId,
    required this.defaultSupplierRemoteId,
    required this.name,
    required this.sku,
    required this.unitType,
    required this.purchaseUnitType,
    required this.conversionFactor,
    required this.lastPurchasePriceCents,
    required this.averagePurchasePriceCents,
    required this.currentStockMil,
    required this.minimumStockMil,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.costHistory,
  });

  final int supplyId;
  final String supplyUuid;
  final String? remoteId;
  final int? defaultSupplierLocalId;
  final String? defaultSupplierRemoteId;
  final String name;
  final String? sku;
  final String unitType;
  final String purchaseUnitType;
  final int conversionFactor;
  final int lastPurchasePriceCents;
  final int? averagePurchasePriceCents;
  final int? currentStockMil;
  final int? minimumStockMil;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus? syncStatus;
  final DateTime? lastSyncedAt;
  final List<SupplyCostHistorySyncPayload> costHistory;
}

class SupplyCostHistorySyncPayload {
  const SupplyCostHistorySyncPayload({
    required this.historyId,
    required this.historyUuid,
    required this.purchaseLocalId,
    required this.purchaseRemoteId,
    required this.purchaseItemLocalUuid,
    required this.source,
    required this.eventType,
    required this.purchaseUnitType,
    required this.conversionFactor,
    required this.lastPurchasePriceCents,
    required this.averagePurchasePriceCents,
    required this.changeSummary,
    required this.notes,
    required this.occurredAt,
    required this.createdAt,
  });

  final int historyId;
  final String historyUuid;
  final int? purchaseLocalId;
  final String? purchaseRemoteId;
  final String? purchaseItemLocalUuid;
  final String source;
  final String eventType;
  final String purchaseUnitType;
  final int conversionFactor;
  final int lastPurchasePriceCents;
  final int? averagePurchasePriceCents;
  final String? changeSummary;
  final String? notes;
  final DateTime occurredAt;
  final DateTime createdAt;
}
