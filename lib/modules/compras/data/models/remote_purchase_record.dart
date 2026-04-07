import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase_status.dart';
import 'purchase_sync_payload.dart';

class RemotePurchaseRecord {
  const RemotePurchaseRecord({
    required this.remoteId,
    required this.localUuid,
    required this.remoteSupplierId,
    required this.supplierLocalUuid,
    required this.supplierName,
    required this.documentNumber,
    required this.notes,
    required this.purchasedAt,
    required this.dueDate,
    required this.paymentMethod,
    required this.status,
    required this.subtotalCents,
    required this.discountCents,
    required this.surchargeCents,
    required this.freightCents,
    required this.finalAmountCents,
    required this.paidAmountCents,
    required this.pendingAmountCents,
    required this.canceledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    required this.payments,
  });

  factory RemotePurchaseRecord.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    final paymentsJson = json['payments'];
    return RemotePurchaseRecord(
      remoteId: json['id'] as String,
      localUuid: json['localUuid'] as String,
      remoteSupplierId: json['supplierId'] as String,
      supplierLocalUuid: json['supplierLocalUuid'] as String?,
      supplierName: json['supplierName'] as String? ?? '',
      documentNumber: json['documentNumber'] as String?,
      notes: json['notes'] as String?,
      purchasedAt: DateTime.parse(json['purchasedAt'] as String),
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.parse(json['dueDate'] as String),
      paymentMethod: _parsePaymentMethod(json['paymentMethod'] as String?),
      status: PurchaseStatusX.fromDb(json['status'] as String? ?? 'recebida'),
      subtotalCents: json['subtotalCents'] as int? ?? 0,
      discountCents: json['discountCents'] as int? ?? 0,
      surchargeCents: json['surchargeCents'] as int? ?? 0,
      freightCents: json['freightCents'] as int? ?? 0,
      finalAmountCents: json['finalAmountCents'] as int? ?? 0,
      paidAmountCents: json['paidAmountCents'] as int? ?? 0,
      pendingAmountCents: json['pendingAmountCents'] as int? ?? 0,
      canceledAt: json['canceledAt'] == null
          ? null
          : DateTime.parse(json['canceledAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      items: itemsJson is List
          ? itemsJson
                .whereType<Map<String, dynamic>>()
                .map(RemotePurchaseItemRecord.fromJson)
                .toList()
          : const <RemotePurchaseItemRecord>[],
      payments: paymentsJson is List
          ? paymentsJson
                .whereType<Map<String, dynamic>>()
                .map(RemotePurchasePaymentRecord.fromJson)
                .toList()
          : const <RemotePurchasePaymentRecord>[],
    );
  }

  factory RemotePurchaseRecord.fromSyncPayload(PurchaseSyncPayload purchase) {
    return RemotePurchaseRecord(
      remoteId: purchase.remoteId ?? '',
      localUuid: purchase.purchaseUuid,
      remoteSupplierId: purchase.supplierRemoteId ?? '',
      supplierLocalUuid: null,
      supplierName: '',
      documentNumber: purchase.documentNumber,
      notes: purchase.notes,
      purchasedAt: purchase.purchasedAt,
      dueDate: purchase.dueDate,
      paymentMethod: purchase.paymentMethod,
      status: purchase.status,
      subtotalCents: purchase.subtotalCents,
      discountCents: purchase.discountCents,
      surchargeCents: purchase.surchargeCents,
      freightCents: purchase.freightCents,
      finalAmountCents: purchase.finalAmountCents,
      paidAmountCents: purchase.paidAmountCents,
      pendingAmountCents: purchase.pendingAmountCents,
      canceledAt: purchase.cancelledAt,
      createdAt: purchase.createdAt,
      updatedAt: purchase.updatedAt,
      items: purchase.items
          .map(RemotePurchaseItemRecord.fromSyncPayload)
          .toList(),
      payments: purchase.payments
          .map(RemotePurchasePaymentRecord.fromSyncPayload)
          .toList(),
    );
  }

  final String remoteId;
  final String localUuid;
  final String remoteSupplierId;
  final String? supplierLocalUuid;
  final String supplierName;
  final String? documentNumber;
  final String? notes;
  final DateTime purchasedAt;
  final DateTime? dueDate;
  final PaymentMethod? paymentMethod;
  final PurchaseStatus status;
  final int subtotalCents;
  final int discountCents;
  final int surchargeCents;
  final int freightCents;
  final int finalAmountCents;
  final int paidAmountCents;
  final int pendingAmountCents;
  final DateTime? canceledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RemotePurchaseItemRecord> items;
  final List<RemotePurchasePaymentRecord> payments;

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'supplierId': remoteSupplierId,
      'documentNumber': documentNumber,
      'notes': notes,
      'purchasedAt': purchasedAt.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'paymentMethod': paymentMethod?.dbValue,
      'status': status.dbValue,
      'subtotalCents': subtotalCents,
      'discountCents': discountCents,
      'surchargeCents': surchargeCents,
      'freightCents': freightCents,
      'finalAmountCents': finalAmountCents,
      'paidAmountCents': paidAmountCents,
      'pendingAmountCents': pendingAmountCents,
      'canceledAt': canceledAt?.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
      'payments': payments.map((payment) => payment.toJson()).toList(),
    };
  }

  static PaymentMethod? _parsePaymentMethod(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return PaymentMethodX.fromDb(value);
  }
}

class RemotePurchaseItemRecord {
  const RemotePurchaseItemRecord({
    required this.remoteId,
    required this.localUuid,
    required this.remoteProductId,
    required this.productNameSnapshot,
    required this.unitMeasureSnapshot,
    required this.quantityMil,
    required this.unitCostCents,
    required this.subtotalCents,
  });

  factory RemotePurchaseItemRecord.fromJson(Map<String, dynamic> json) {
    return RemotePurchaseItemRecord(
      remoteId: json['id'] as String,
      localUuid: json['localUuid'] as String,
      remoteProductId: json['productId'] as String?,
      productNameSnapshot: json['productNameSnapshot'] as String,
      unitMeasureSnapshot: json['unitMeasureSnapshot'] as String,
      quantityMil: json['quantityMil'] as int? ?? 0,
      unitCostCents: json['unitCostCents'] as int? ?? 0,
      subtotalCents: json['subtotalCents'] as int? ?? 0,
    );
  }

  factory RemotePurchaseItemRecord.fromSyncPayload(
    PurchaseSyncItemPayload item,
  ) {
    return RemotePurchaseItemRecord(
      remoteId: '',
      localUuid: item.itemUuid,
      remoteProductId: item.productRemoteId,
      productNameSnapshot: item.productNameSnapshot,
      unitMeasureSnapshot: item.unitMeasureSnapshot,
      quantityMil: item.quantityMil,
      unitCostCents: item.unitCostCents,
      subtotalCents: item.subtotalCents,
    );
  }

  final String remoteId;
  final String localUuid;
  final String? remoteProductId;
  final String productNameSnapshot;
  final String unitMeasureSnapshot;
  final int quantityMil;
  final int unitCostCents;
  final int subtotalCents;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'productId': remoteProductId,
      'productNameSnapshot': productNameSnapshot,
      'unitMeasureSnapshot': unitMeasureSnapshot,
      'quantityMil': quantityMil,
      'unitCostCents': unitCostCents,
      'subtotalCents': subtotalCents,
    };
  }
}

class RemotePurchasePaymentRecord {
  const RemotePurchasePaymentRecord({
    required this.remoteId,
    required this.localUuid,
    required this.amountCents,
    required this.paymentMethod,
    required this.paidAt,
    required this.notes,
  });

  factory RemotePurchasePaymentRecord.fromJson(Map<String, dynamic> json) {
    return RemotePurchasePaymentRecord(
      remoteId: json['id'] as String,
      localUuid: json['localUuid'] as String,
      amountCents: json['amountCents'] as int? ?? 0,
      paymentMethod: PaymentMethodX.fromDb(
        json['paymentMethod'] as String? ?? 'dinheiro',
      ),
      paidAt: DateTime.parse(json['paidAt'] as String),
      notes: json['notes'] as String?,
    );
  }

  factory RemotePurchasePaymentRecord.fromSyncPayload(
    PurchaseSyncPaymentPayload payment,
  ) {
    return RemotePurchasePaymentRecord(
      remoteId: '',
      localUuid: payment.paymentUuid,
      amountCents: payment.amountCents,
      paymentMethod: payment.paymentMethod,
      paidAt: payment.paidAt,
      notes: payment.notes,
    );
  }

  final String remoteId;
  final String localUuid;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final DateTime paidAt;
  final String? notes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'amountCents': amountCents,
      'paymentMethod': paymentMethod.dbValue,
      'paidAt': paidAt.toIso8601String(),
      'notes': notes,
    };
  }
}
