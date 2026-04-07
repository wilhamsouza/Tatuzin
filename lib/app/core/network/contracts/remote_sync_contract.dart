import '../../app_context/record_identity.dart';

class SyncPreview {
  const SyncPreview({
    required this.pendingPushCount,
    required this.pendingPullCount,
    required this.conflictCandidates,
    required this.lastSyncAt,
  });

  final int pendingPushCount;
  final int pendingPullCount;
  final List<RecordIdentity> conflictCandidates;
  final DateTime? lastSyncAt;
}

class SyncResult {
  const SyncResult({
    required this.pushedRecords,
    required this.pulledRecords,
    required this.resolvedConflicts,
    required this.completedAt,
  });

  final int pushedRecords;
  final int pulledRecords;
  final int resolvedConflicts;
  final DateTime completedAt;
}

abstract interface class RemoteSyncContract {
  Future<SyncPreview> previewSync();

  Future<SyncResult> synchronize();
}
