import '../../../../app/core/sync/sync_status.dart';
import '../../domain/entities/sale_enums.dart';

class SaleSyncPayload {
  const SaleSyncPayload({
    required this.saleId,
    required this.saleUuid,
    required this.receiptNumber,
    required this.saleType,
    required this.paymentMethod,
    required this.status,
    required this.totalAmountCents,
    required this.totalCostCents,
    required this.soldAt,
    required this.updatedAt,
    required this.clientLocalId,
    required this.clientRemoteId,
    required this.notes,
    required this.remoteId,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.items,
  });

  final int saleId;
  final String saleUuid;
  final String receiptNumber;
  final SaleType saleType;
  final PaymentMethod paymentMethod;
  final SaleStatus status;
  final int totalAmountCents;
  final int totalCostCents;
  final DateTime soldAt;
  final DateTime updatedAt;
  final int? clientLocalId;
  final String? clientRemoteId;
  final String? notes;
  final String? remoteId;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
  final List<SaleSyncItemPayload> items;
}

class SaleSyncItemPayload {
  const SaleSyncItemPayload({
    required this.itemId,
    required this.productLocalId,
    required this.productRemoteId,
    required this.productNameSnapshot,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.totalPriceCents,
    required this.unitCostCents,
    required this.totalCostCents,
    required this.unitMeasure,
    required this.productType,
  });

  final int itemId;
  final int? productLocalId;
  final String? productRemoteId;
  final String productNameSnapshot;
  final int quantityMil;
  final int unitPriceCents;
  final int totalPriceCents;
  final int unitCostCents;
  final int totalCostCents;
  final String unitMeasure;
  final String productType;
}
