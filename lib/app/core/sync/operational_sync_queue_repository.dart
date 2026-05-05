import 'package:sqflite/sqflite.dart';

import 'operational_sync_event.dart';
import 'operational_sync_queue_item.dart';
import 'sync_queue_feature_summary.dart';

abstract interface class OperationalSyncQueueRepository {
  Future<bool> enqueue(
    DatabaseExecutor db, {
    required OperationalSyncEvent event,
  });

  Future<List<OperationalSyncQueueItem>> listPending({
    required int limit,
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
    DateTime? now,
  });

  Future<void> markPushing(
    Iterable<OperationalSyncQueueItem> items, {
    required DateTime startedAt,
  });

  Future<void> markAccepted({
    required String eventId,
    required String? serverVersion,
    required DateTime processedAt,
  });

  Future<void> markDuplicate({
    required String eventId,
    required String? serverVersion,
    required DateTime processedAt,
  });

  Future<void> markRejected({
    required String eventId,
    required String code,
    required String message,
    required DateTime processedAt,
  });

  Future<void> markConflict({
    required String eventId,
    required String? serverVersion,
    required String code,
    required String message,
    required String? conflictId,
    required DateTime processedAt,
  });

  Future<void> markFailed(
    Iterable<OperationalSyncQueueItem> items, {
    required String message,
    required DateTime failedAt,
    required DateTime? nextRetryAt,
  });

  Future<String> readCheckpoint();

  Future<void> saveCheckpoint(String serverVersion);

  Future<String?> readSnapshotVersion();

  Future<void> saveSnapshotVersion(String serverFirstSnapshotVersion);

  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries();
}
