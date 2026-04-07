import 'sync_queue_status.dart';
import 'sync_reconciliation_status.dart';
import 'sync_status.dart';

class SyncReconciliationIssue {
  const SyncReconciliationIssue({
    required this.featureKey,
    required this.entityType,
    required this.entityLabel,
    required this.status,
    required this.reasonCode,
    required this.message,
    this.localEntityId,
    this.localUuid,
    this.remoteId,
    this.localUpdatedAt,
    this.remoteUpdatedAt,
    this.metadataStatus,
    this.queueStatus,
    this.lastError,
    this.lastErrorType,
    this.canMarkForResync = false,
    this.localPayloadSignature,
    this.remotePayloadSignature,
  });

  final String featureKey;
  final String entityType;
  final String entityLabel;
  final SyncReconciliationStatus status;
  final String reasonCode;
  final String message;
  final int? localEntityId;
  final String? localUuid;
  final String? remoteId;
  final DateTime? localUpdatedAt;
  final DateTime? remoteUpdatedAt;
  final SyncStatus? metadataStatus;
  final SyncQueueStatus? queueStatus;
  final String? lastError;
  final String? lastErrorType;
  final bool canMarkForResync;
  final String? localPayloadSignature;
  final String? remotePayloadSignature;
}
