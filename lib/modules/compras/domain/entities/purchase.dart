import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../../app/core/sync/sync_status.dart';
import 'purchase_item.dart';
import 'purchase_status.dart';

class Purchase {
  const Purchase({
    required this.id,
    required this.uuid,
    required this.supplierId,
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
    required this.createdAt,
    required this.updatedAt,
    required this.cancelledAt,
    required this.itemsCount,
    this.remoteId,
    this.syncStatus,
    this.lastSyncedAt,
    this.syncIssueMessage,
    this.syncIssueType,
  });

  final int id;
  final String uuid;
  final int supplierId;
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
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? cancelledAt;
  final int itemsCount;
  final String? remoteId;
  final SyncStatus? syncStatus;
  final DateTime? lastSyncedAt;
  final String? syncIssueMessage;
  final String? syncIssueType;

  bool get isCancelled => status == PurchaseStatus.cancelada;

  bool get isLocalOnly => syncStatus == SyncStatus.localOnly;
}

class PurchaseUpsertInput {
  const PurchaseUpsertInput({
    required this.supplierId,
    required this.purchasedAt,
    required this.items,
    required this.discountCents,
    required this.surchargeCents,
    required this.freightCents,
    required this.initialPaidAmountCents,
    this.documentNumber,
    this.notes,
    this.dueDate,
    this.paymentMethod,
  });

  final int supplierId;
  final String? documentNumber;
  final String? notes;
  final DateTime purchasedAt;
  final DateTime? dueDate;
  final PaymentMethod? paymentMethod;
  final List<PurchaseItemInput> items;
  final int discountCents;
  final int surchargeCents;
  final int freightCents;
  final int initialPaidAmountCents;
}
