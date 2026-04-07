class SyncActionResult {
  const SyncActionResult({
    required this.featureKey,
    required this.displayName,
    required this.pushedCount,
    required this.pulledCount,
    required this.syncedCount,
    required this.failedCount,
    required this.startedAt,
    required this.finishedAt,
    this.message,
  });

  final String featureKey;
  final String displayName;
  final int pushedCount;
  final int pulledCount;
  final int syncedCount;
  final int failedCount;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? message;
}
