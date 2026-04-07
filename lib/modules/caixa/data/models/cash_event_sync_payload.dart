import '../../../../app/core/sync/sync_status.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cash_enums.dart';

class CashEventSyncPayload {
  const CashEventSyncPayload({
    required this.movementId,
    required this.movementUuid,
    required this.type,
    required this.amountCents,
    required this.paymentMethod,
    required this.referenceType,
    required this.referenceLocalId,
    required this.referenceRemoteId,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.remoteId,
    required this.syncStatus,
    required this.lastSyncedAt,
  });

  final int movementId;
  final String movementUuid;
  final CashMovementType type;
  final int amountCents;
  final PaymentMethod? paymentMethod;
  final String? referenceType;
  final int? referenceLocalId;
  final String? referenceRemoteId;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? remoteId;
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
}
