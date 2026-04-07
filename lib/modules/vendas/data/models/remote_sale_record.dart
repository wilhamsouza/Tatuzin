import '../../domain/entities/sale_enums.dart';
import 'sale_sync_payload.dart';

class RemoteSaleRecord {
  const RemoteSaleRecord({
    required this.remoteId,
    required this.localUuid,
    required this.remoteCustomerId,
    required this.receiptNumber,
    required this.paymentType,
    required this.paymentMethod,
    required this.status,
    required this.totalAmountCents,
    required this.totalCostCents,
    required this.soldAt,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  factory RemoteSaleRecord.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    return RemoteSaleRecord(
      remoteId: json['id'] as String,
      localUuid: json['localUuid'] as String,
      remoteCustomerId: json['customerId'] as String?,
      receiptNumber: json['receiptNumber'] as String?,
      paymentType: json['paymentType'] as String,
      paymentMethod: json['paymentMethod'] as String? ?? 'dinheiro',
      status: json['status'] as String? ?? 'active',
      totalAmountCents: json['totalAmountCents'] as int? ?? 0,
      totalCostCents: json['totalCostCents'] as int? ?? 0,
      soldAt: DateTime.parse(json['soldAt'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      items: itemsJson is List
          ? itemsJson
                .whereType<Map<String, dynamic>>()
                .map(RemoteSaleItemRecord.fromJson)
                .toList()
          : const <RemoteSaleItemRecord>[],
    );
  }

  factory RemoteSaleRecord.fromSyncPayload(SaleSyncPayload sale) {
    return RemoteSaleRecord(
      remoteId: sale.remoteId ?? '',
      localUuid: sale.saleUuid,
      remoteCustomerId: sale.clientRemoteId,
      receiptNumber: sale.receiptNumber,
      paymentType: sale.saleType.dbValue,
      paymentMethod: sale.paymentMethod.dbValue,
      status: sale.status.name == 'cancelled' ? 'canceled' : 'active',
      totalAmountCents: sale.totalAmountCents,
      totalCostCents: sale.totalCostCents,
      soldAt: sale.soldAt,
      notes: sale.notes,
      createdAt: sale.soldAt,
      updatedAt: sale.updatedAt,
      items: sale.items.map(RemoteSaleItemRecord.fromSyncItemPayload).toList(),
    );
  }

  final String remoteId;
  final String localUuid;
  final String? remoteCustomerId;
  final String? receiptNumber;
  final String paymentType;
  final String paymentMethod;
  final String status;
  final int totalAmountCents;
  final int totalCostCents;
  final DateTime soldAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RemoteSaleItemRecord> items;

  Map<String, dynamic> toCreateBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'customerId': remoteCustomerId,
      'receiptNumber': receiptNumber,
      'paymentType': paymentType,
      'paymentMethod': paymentMethod,
      'status': status,
      'totalAmountCents': totalAmountCents,
      'totalCostCents': totalCostCents,
      'soldAt': soldAt.toIso8601String(),
      'notes': notes,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class RemoteSaleItemRecord {
  const RemoteSaleItemRecord({
    required this.remoteProductId,
    required this.productNameSnapshot,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.totalPriceCents,
    required this.unitCostCents,
    required this.totalCostCents,
    required this.unitMeasure,
    required this.productType,
  });

  factory RemoteSaleItemRecord.fromJson(Map<String, dynamic> json) {
    return RemoteSaleItemRecord(
      remoteProductId: json['productId'] as String?,
      productNameSnapshot: json['productNameSnapshot'] as String,
      quantityMil: json['quantityMil'] as int? ?? 0,
      unitPriceCents: json['unitPriceCents'] as int? ?? 0,
      totalPriceCents: json['totalPriceCents'] as int? ?? 0,
      unitCostCents: json['unitCostCents'] as int? ?? 0,
      totalCostCents: json['totalCostCents'] as int? ?? 0,
      unitMeasure: json['unitMeasure'] as String?,
      productType: json['productType'] as String?,
    );
  }

  factory RemoteSaleItemRecord.fromSyncItemPayload(SaleSyncItemPayload item) {
    return RemoteSaleItemRecord(
      remoteProductId: item.productRemoteId,
      productNameSnapshot: item.productNameSnapshot,
      quantityMil: item.quantityMil,
      unitPriceCents: item.unitPriceCents,
      totalPriceCents: item.totalPriceCents,
      unitCostCents: item.unitCostCents,
      totalCostCents: item.totalCostCents,
      unitMeasure: item.unitMeasure,
      productType: item.productType,
    );
  }

  final String? remoteProductId;
  final String productNameSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int totalPriceCents;
  final int unitCostCents;
  final int totalCostCents;
  final String? unitMeasure;
  final String? productType;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'productId': remoteProductId,
      'productNameSnapshot': productNameSnapshot,
      'quantityMil': quantityMil,
      'unitPriceCents': unitPriceCents,
      'totalPriceCents': totalPriceCents,
      'unitCostCents': unitCostCents,
      'totalCostCents': totalCostCents,
      'unitMeasure': unitMeasure,
      'productType': productType,
    };
  }
}
