import 'sync_conflict_info.dart';
import 'sync_queue_item.dart';

class SyncFeatureProcessResult {
  const SyncFeatureProcessResult._({
    required this.outcome,
    this.remoteId,
    this.message,
    this.conflict,
  });

  const SyncFeatureProcessResult.synced({String? remoteId})
    : this._(outcome: SyncFeatureProcessOutcome.synced, remoteId: remoteId);

  const SyncFeatureProcessResult.blocked({required String reason})
    : this._(outcome: SyncFeatureProcessOutcome.blocked, message: reason);

  const SyncFeatureProcessResult.requeued({required String reason})
    : this._(outcome: SyncFeatureProcessOutcome.requeued, message: reason);

  SyncFeatureProcessResult.conflict({required SyncConflictInfo conflict})
    : this._(
        outcome: SyncFeatureProcessOutcome.conflict,
        message: conflict.reason,
        conflict: conflict,
      );

  final SyncFeatureProcessOutcome outcome;
  final String? remoteId;
  final String? message;
  final SyncConflictInfo? conflict;
}

enum SyncFeatureProcessOutcome { synced, blocked, conflict, requeued }

abstract interface class SyncFeatureProcessor {
  String get featureKey;

  String get displayName;

  Future<void> ensureSyncAllowed();

  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item);

  Future<int> pullRemoteSnapshot();
}
