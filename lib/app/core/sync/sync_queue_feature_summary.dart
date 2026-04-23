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

  int get pendingForDisplay => pendingCount + staleProcessingCount;

  bool get hasActiveProcessing => activeProcessingCount > 0;

  bool get hasAttention =>
      errorCount > 0 || blockedCount > 0 || conflictCount > 0;

  SyncDisplayState get displayState {
    if (hasAttention) {
      return SyncDisplayState.attention;
    }
    if (hasActiveProcessing) {
      return SyncDisplayState.syncing;
    }
    if (pendingForDisplay > 0) {
      return SyncDisplayState.pending;
    }
    return SyncDisplayState.synced;
  }
}
