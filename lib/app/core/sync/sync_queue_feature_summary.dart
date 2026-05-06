import 'sync_error_type.dart';
import 'sync_display_state.dart';

class SyncQueueFeatureSummary {
  const SyncQueueFeatureSummary({
    required this.featureKey,
    required this.displayName,
    required this.totalTracked,
    required this.pendingCount,
    required this.processingCount,
    required this.activeProcessingCount,
    required this.staleProcessingCount,
    required this.syncedCount,
    required this.errorCount,
    required this.blockedCount,
    required this.conflictCount,
    required this.totalAttemptCount,
    required this.lastProcessedAt,
    required this.nextRetryAt,
    required this.lastError,
    required this.lastErrorType,
    required this.lastErrorAt,
    this.partialStatus,
    this.lastPullError,
    this.lastSnapshotError,
  });

  final String featureKey;
  final String displayName;
  final int totalTracked;
  final int pendingCount;
  final int processingCount;
  final int activeProcessingCount;
  final int staleProcessingCount;
  final int syncedCount;
  final int errorCount;
  final int blockedCount;
  final int conflictCount;
  final int totalAttemptCount;
  final DateTime? lastProcessedAt;
  final DateTime? nextRetryAt;
  final String? lastError;
  final SyncErrorType? lastErrorType;
  final DateTime? lastErrorAt;
  final String? partialStatus;
  final String? lastPullError;
  final String? lastSnapshotError;

  int get pendingForDisplay => pendingCount + staleProcessingCount;

  bool get hasActiveProcessing => activeProcessingCount > 0;

  bool get hasAttention =>
      errorCount > 0 || blockedCount > 0 || conflictCount > 0;

  bool get hasServerDataStale =>
      partialStatus == 'pushOkPullFailed' ||
      partialStatus == 'snapshotFailed' ||
      (lastPullError != null && lastPullError!.trim().isNotEmpty) ||
      (lastSnapshotError != null && lastSnapshotError!.trim().isNotEmpty);

  SyncDisplayState get displayState {
    if (conflictCount > 0) {
      return SyncDisplayState.conflict;
    }
    if (errorCount > 0 || blockedCount > 0) {
      return SyncDisplayState.error;
    }
    if (hasActiveProcessing) {
      return SyncDisplayState.syncing;
    }
    if (pendingForDisplay > 0) {
      return SyncDisplayState.pending;
    }
    if (hasServerDataStale) {
      return SyncDisplayState.serverDataStale;
    }
    return SyncDisplayState.synced;
  }
}
