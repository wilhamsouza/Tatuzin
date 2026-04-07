import '../../../../app/core/sync/sync_status.dart';
import '../../../vendas/domain/entities/sale_enums.dart';

class FiadoPaymentSyncPayload {
  const FiadoPaymentSyncPayload({
    required this.entryId,
    required this.entryUuid,
    required this.fiadoId,
    required this.fiadoUuid,
    required this.saleLocalId,
    required this.saleRemoteId,
    required this.amountCents,
    required this.paymentMethod,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.remoteId,
    required this.syncStatus,
    required this.lastSyncedAt,
  });

  final int entryId;
  final String entryUuid;
  final int fiadoId;
  final String fiadoUuid;
  final int saleLocalId;
  final String? saleRemoteId;
  final int amountCents;
  final PaymentMethod paymentMethod;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? remoteId;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
}
