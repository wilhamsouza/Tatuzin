class SyncConflictInfo {
  const SyncConflictInfo({
    required this.reason,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
  });

  final String reason;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;
}
