import 'sync_conflict_info.dart';
import 'sync_error_type.dart';
import 'sync_queue_operation.dart';
import 'sync_queue_status.dart';

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.featureKey,
    required this.entityType,
    required this.localEntityId,
    required this.localUuid,
    required this.remoteId,
    required this.operation,
    required this.status,
    required this.attemptCount,
    required this.nextRetryAt,
    required this.lastError,
    required this.lastErrorType,
    required this.createdAt,
    required this.updatedAt,
    required this.lockedAt,
    required this.lastProcessedAt,
    required this.correlationKey,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.conflictReason,
  });

  final int id;
  final String featureKey;
  final String entityType;
  final int localEntityId;
  final String? localUuid;
  final String? remoteId;
  final SyncQueueOperation operation;
  final SyncQueueStatus status;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final SyncErrorType? lastErrorType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lockedAt;
  final DateTime? lastProcessedAt;
  final String correlationKey;
  final DateTime? localUpdatedAt;
  final DateTime? remoteUpdatedAt;
  final String? conflictReason;

  SyncConflictInfo? get conflictInfo {
    if (conflictReason == null ||
        localUpdatedAt == null ||
        remoteUpdatedAt == null) {
      return null;
    }

    return SyncConflictInfo(
      reason: conflictReason!,
      localUpdatedAt: localUpdatedAt!,
      remoteUpdatedAt: remoteUpdatedAt!,
    );
  }
}
