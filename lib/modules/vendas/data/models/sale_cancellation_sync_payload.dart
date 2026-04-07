import '../../../../app/core/sync/sync_status.dart';

class SaleCancellationSyncPayload {
  const SaleCancellationSyncPayload({
    required this.saleId,
    required this.saleUuid,
    required this.saleRemoteId,
    required this.remoteId,
    required this.amountCents,
    required this.paymentType,
    required this.canceledAt,
    required this.updatedAt,
    required this.notes,
    required this.syncStatus,
    required this.lastSyncedAt,
  });

  final int saleId;
  final String saleUuid;
  final String? saleRemoteId;
  final String? remoteId;
  final int amountCents;
  final String paymentType;
  final DateTime canceledAt;
  final DateTime updatedAt;
  final String? notes;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
}
