import '../../domain/entities/supply.dart';
import 'supply_sync_payload.dart';

class RemoteSupplyRecord {
  const RemoteSupplyRecord({
    required this.remoteId,
    required this.localUuid,
    required this.remoteDefaultSupplierId,
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
    required this.deletedAt,
    this.defaultSupplierLocalUuid,
    this.defaultSupplierName,
    this.costHistory = const <RemoteSupplyCostHistoryRecord>[],
  });

  factory RemoteSupplyRecord.fromJson(Map<String, dynamic> json) {
    final historyJson = json['costHistory'];
    final remoteId = json['id'] as String;
    return RemoteSupplyRecord(
      remoteId: remoteId,
      localUuid: (json['localUuid'] as String?)?.trim().isNotEmpty == true
          ? json['localUuid'] as String
          : remoteId,
      remoteDefaultSupplierId: json['defaultSupplierId'] as String?,
      defaultSupplierLocalUuid: json['defaultSupplierLocalUuid'] as String?,
      defaultSupplierName: json['defaultSupplierName'] as String?,
      name: json['name'] as String? ?? '',
      sku: json['sku'] as String?,
      unitType: SupplyUnitTypes.normalize(json['unitType'] as String?),
      purchaseUnitType: SupplyUnitTypes.normalize(
        json['purchaseUnitType'] as String?,
      ),
      conversionFactor: json['conversionFactor'] as int? ?? 1,
      lastPurchasePriceCents: json['lastPurchasePriceCents'] as int? ?? 0,
      averagePurchasePriceCents: json['averagePurchasePriceCents'] as int?,
      currentStockMil: json['currentStockMil'] as int?,
      minimumStockMil: json['minimumStockMil'] as int?,
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      costHistory: historyJson is List
          ? historyJson
                .whereType<Map<String, dynamic>>()
                .map(RemoteSupplyCostHistoryRecord.fromJson)
                .toList(growable: false)
          : const <RemoteSupplyCostHistoryRecord>[],
    );
  }

  factory RemoteSupplyRecord.fromSyncPayload(SupplySyncPayload supply) {
    return RemoteSupplyRecord(
      remoteId: supply.remoteId ?? '',
      localUuid: supply.supplyUuid,
      remoteDefaultSupplierId: supply.defaultSupplierRemoteId,
      name: supply.name,
      sku: supply.sku,
      unitType: supply.unitType,
      purchaseUnitType: supply.purchaseUnitType,
      conversionFactor: supply.conversionFactor,
      lastPurchasePriceCents: supply.lastPurchasePriceCents,
      averagePurchasePriceCents: supply.averagePurchasePriceCents,
      currentStockMil: supply.currentStockMil,
      minimumStockMil: supply.minimumStockMil,
      isActive: supply.isActive,
      createdAt: supply.createdAt,
      updatedAt: supply.updatedAt,
      deletedAt: supply.isActive ? null : supply.updatedAt,
      costHistory: supply.costHistory
          .map(RemoteSupplyCostHistoryRecord.fromSyncPayload)
          .toList(growable: false),
    );
  }

  final String remoteId;
  final String localUuid;
  final String? remoteDefaultSupplierId;
  final String? defaultSupplierLocalUuid;
  final String? defaultSupplierName;
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
  final DateTime? deletedAt;
  final List<RemoteSupplyCostHistoryRecord> costHistory;

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'defaultSupplierId': remoteDefaultSupplierId,
      'name': name,
      'sku': sku,
      'unitType': unitType,
      'purchaseUnitType': purchaseUnitType,
      'conversionFactor': conversionFactor,
      'lastPurchasePriceCents': lastPurchasePriceCents,
      'averagePurchasePriceCents': averagePurchasePriceCents,
      'currentStockMil': currentStockMil,
      'minimumStockMil': minimumStockMil,
      'isActive': isActive,
      'deletedAt': deletedAt?.toIso8601String(),
      'costHistory': costHistory.map((entry) => entry.toJson()).toList(),
    };
  }
}

class RemoteSupplyCostHistoryRecord {
  const RemoteSupplyCostHistoryRecord({
    required this.remoteId,
    required this.localUuid,
    required this.purchaseRemoteId,
    required this.purchaseItemId,
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

  factory RemoteSupplyCostHistoryRecord.fromJson(Map<String, dynamic> json) {
    return RemoteSupplyCostHistoryRecord(
      remoteId: json['id'] as String? ?? '',
      localUuid:
          (json['localUuid'] as String?) ??
          (json['uuid'] as String?) ??
          '',
      purchaseRemoteId: json['purchaseId'] as String?,
      purchaseItemId: json['purchaseItemId'] as String?,
      purchaseItemLocalUuid: json['purchaseItemLocalUuid'] as String?,
      source: json['source'] as String? ?? 'manual',
      eventType: json['eventType'] as String? ?? 'manual_edit',
      purchaseUnitType: json['purchaseUnitType'] as String? ?? 'un',
      conversionFactor: json['conversionFactor'] as int? ?? 1,
      lastPurchasePriceCents: json['lastPurchasePriceCents'] as int? ?? 0,
      averagePurchasePriceCents: json['averagePurchasePriceCents'] as int?,
      changeSummary: json['changeSummary'] as String?,
      notes: json['notes'] as String?,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  factory RemoteSupplyCostHistoryRecord.fromSyncPayload(
    SupplyCostHistorySyncPayload history,
  ) {
    return RemoteSupplyCostHistoryRecord(
      remoteId: '',
      localUuid: history.historyUuid,
      purchaseRemoteId: history.purchaseRemoteId,
      purchaseItemId: null,
      purchaseItemLocalUuid: history.purchaseItemLocalUuid,
      source: history.source,
      eventType: history.eventType,
      purchaseUnitType: history.purchaseUnitType,
      conversionFactor: history.conversionFactor,
      lastPurchasePriceCents: history.lastPurchasePriceCents,
      averagePurchasePriceCents: history.averagePurchasePriceCents,
      changeSummary: history.changeSummary,
      notes: history.notes,
      occurredAt: history.occurredAt,
      createdAt: history.createdAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String? purchaseRemoteId;
  final String? purchaseItemId;
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'purchaseId': purchaseRemoteId,
      'purchaseItemId': purchaseItemId,
      'purchaseItemLocalUuid': purchaseItemLocalUuid,
      'source': source,
      'eventType': eventType,
      'purchaseUnitType': purchaseUnitType,
      'conversionFactor': conversionFactor,
      'lastPurchasePriceCents': lastPurchasePriceCents,
      'averagePurchasePriceCents': averagePurchasePriceCents,
      'changeSummary': changeSummary,
      'notes': notes,
      'occurredAt': occurredAt.toIso8601String(),
    };
  }
}
