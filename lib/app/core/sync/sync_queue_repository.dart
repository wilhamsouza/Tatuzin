import 'package:sqflite/sqflite.dart';

import 'sync_conflict_info.dart';
import 'sync_error_type.dart';
import 'sync_queue_feature_summary.dart';
import 'sync_queue_item.dart';
import 'sync_queue_operation.dart';

abstract interface class SyncQueueRepository {
  Future<void> enqueueMutation(
    DatabaseExecutor db, {
    required String featureKey,
    required String entityType,
    required int localEntityId,
    required String? localUuid,
    required String? remoteId,
    required SyncQueueOperation operation,
    required DateTime localUpdatedAt,
  });

  Future<void> removeForEntity(
    DatabaseExecutor db, {
    required String featureKey,
    required int localEntityId,
  });

  Future<List<SyncQueueItem>> listEligibleItems({
    Iterable<String>? featureKeys,
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
    DateTime? now,
  });

  Future<SyncQueueItem?> lockItem(int queueId, {DateTime? now});

  Future<int> recoverStaleProcessingLocks({DateTime? now});

  Future<void> markSynced(
    int queueId, {
    required String? remoteId,
    required DateTime processedAt,
  });

  Future<void> markBlocked(
    int queueId, {
    required String reason,
    required DateTime blockedAt,
  });

  Future<void> markConflict(
    int queueId, {
    required SyncConflictInfo conflict,
    required DateTime processedAt,
  });

  Future<void> markFailure(
    int queueId, {
    required String message,
    required SyncErrorType errorType,
    required DateTime processedAt,
    required DateTime? nextRetryAt,
  });

  Future<void> reenqueueAsCreate(
    int queueId, {
    required DateTime requeuedAt,
    DatabaseExecutor? executor,
  });

  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries();

  Future<List<SyncQueueItem>> listAttentionItems({int limit = 50});
}
