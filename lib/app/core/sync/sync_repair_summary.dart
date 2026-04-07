class SyncRepairSummary {
  const SyncRepairSummary({
    required this.totalIssues,
    required this.autoSafeCount,
    required this.assistedSafeCount,
    required this.manualReviewCount,
    required this.blockedCount,
    required this.notRepairableCount,
    required this.batchSafeCount,
  });

  const SyncRepairSummary.empty()
    : totalIssues = 0,
      autoSafeCount = 0,
      assistedSafeCount = 0,
      manualReviewCount = 0,
      blockedCount = 0,
      notRepairableCount = 0,
      batchSafeCount = 0;

  final int totalIssues;
  final int autoSafeCount;
  final int assistedSafeCount;
  final int manualReviewCount;
  final int blockedCount;
  final int notRepairableCount;
  final int batchSafeCount;
}
