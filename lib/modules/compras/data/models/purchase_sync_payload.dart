import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../domain/entities/purchase_status.dart';

class PurchaseSyncPayload {
  const PurchaseSyncPayload({
    required this.purchaseId,
    required this.purchaseUuid,
    required this.remoteId,
    required this.supplierLocalId,
    required this.supplierRemoteId,
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
    required this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.items,
    required this.payments,
  });

  final int purchaseId;
  final String purchaseUuid;
  final String? remoteId;
  final int supplierLocalId;
  final String? supplierRemoteId;
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
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus? syncStatus;
  final DateTime? lastSyncedAt;
  final List<PurchaseSyncItemPayload> items;
  final List<PurchaseSyncPaymentPayload> payments;
}

class PurchaseSyncItemPayload {
  const PurchaseSyncItemPayload({
    required this.itemId,
    required this.itemUuid,
    required this.productLocalId,
    required this.productRemoteId,
    required this.productNameSnapshot,
    required this.unitMeasureSnapshot,
    required this.quantityMil,
    required this.unitCostCents,
    required this.subtotalCents,
  });

  final int itemId;
  final String itemUuid;
  final int productLocalId;
  final String? productRemoteId;
  final String productNameSnapshot;
  final String unitMeasureSnapshot;
  final int quantityMil;
  final int unitCostCents;
  final int subtotalCents;
}

class PurchaseSyncPaymentPayload {
  const PurchaseSyncPaymentPayload({
    required this.paymentId,
    required this.paymentUuid,
    required this.amountCents,
    required this.paymentMethod,
    required this.paidAt,
    required this.notes,
  });

  final int paymentId;
  final String paymentUuid;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final DateTime paidAt;
  final String? notes;
}
