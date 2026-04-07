import 'sync_error_type.dart';

class SyncQueueFeatureSummary {
  const SyncQueueFeatureSummary({
    required this.featureKey,
    required this.displayName,
    required this.totalTracked,
    required this.pendingCount,
    required this.processingCount,
    required this.syncedCount,
    required this.errorCount,
    required this.blockedCount,
    required this.conflictCount,
    required this.totalAttemptCount,
    required this.lastProcessedAt,
    required this.nextRetryAt,
    required this.lastError,
    required this.lastErrorType,
  });

  final String featureKey;
  final String displayName;
  final int totalTracked;
  final int pendingCount;
  final int processingCount;
  final int syncedCount;
  final int errorCount;
  final int blockedCount;
  final int conflictCount;
  final int totalAttemptCount;
  final DateTime? lastProcessedAt;
  final DateTime? nextRetryAt;
  final String? lastError;
  final SyncErrorType? lastErrorType;
}
