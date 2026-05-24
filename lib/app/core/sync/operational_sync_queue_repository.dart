import 'package:sqflite/sqflite.dart';

import 'operational_sync_event.dart';
import 'operational_sync_queue_item.dart';
import 'operational_sync_remote_datasource.dart';
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

  Future<int> recoverStalePushing({
    required Duration staleAfter,
    DateTime? now,
  });

  Future<String> readCheckpoint();

  Future<void> saveCheckpoint(String serverVersion);

  Future<String?> readSnapshotVersion();

  Future<void> saveSnapshotVersion(String serverFirstSnapshotVersion);

  Future<void> recordPullSucceeded({required DateTime completedAt});

  Future<void> recordPullFailed({
    required String message,
    required DateTime failedAt,
  });

  Future<void> recordSnapshotSucceeded({
    required String serverFirstSnapshotVersion,
    required DateTime completedAt,
  });

  Future<void> recordSnapshotFailed({
    required String message,
    required DateTime failedAt,
  });

  Future<OperationalSyncDiagnosticReport> buildDiagnosticReport({
    List<OperationalSyncConflict> conflicts = const <OperationalSyncConflict>[],
  });

  Future<int> repairOperationalOrderItemTotalCents();

  Future<int> reenqueueRecoverableFailedEvents();

  Future<int> clearResolvedConflictCache({
    required List<OperationalSyncConflict> conflicts,
  });

  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries();
}
