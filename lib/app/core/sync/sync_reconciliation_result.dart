import 'sync_reconciliation_issue.dart';
import 'sync_reconciliation_status.dart';

class SyncReconciliationResult {
  const SyncReconciliationResult({
    required this.featureKey,
    required this.displayName,
    required this.checkedAt,
    required this.totalLocal,
    required this.totalRemote,
    required this.consistentCount,
    required this.localOnlyCount,
    required this.remoteOnlyCount,
    required this.pendingSyncCount,
    required this.conflictCount,
    required this.outOfSyncCount,
    required this.missingRemoteCount,
    required this.missingLocalCount,
    required this.invalidLinkCount,
    required this.orphanRemoteCount,
    required this.unknownCount,
    required this.issues,
    this.fetchError,
  });

  factory SyncReconciliationResult.fromIssues({
    required String featureKey,
    required String displayName,
    required DateTime checkedAt,
    required int totalLocal,
    required int totalRemote,
    required List<SyncReconciliationIssue> issues,
    String? fetchError,
  }) {
    var consistentCount = 0;
    var localOnlyCount = 0;
    var remoteOnlyCount = 0;
    var pendingSyncCount = 0;
    var conflictCount = 0;
    var outOfSyncCount = 0;
    var missingRemoteCount = 0;
    var missingLocalCount = 0;
    var invalidLinkCount = 0;
    var orphanRemoteCount = 0;
    var unknownCount = 0;

    for (final issue in issues) {
      switch (issue.status) {
        case SyncReconciliationStatus.consistent:
          consistentCount++;
          break;
        case SyncReconciliationStatus.localOnly:
          localOnlyCount++;
          break;
        case SyncReconciliationStatus.remoteOnly:
          remoteOnlyCount++;
          break;
        case SyncReconciliationStatus.pendingSync:
          pendingSyncCount++;
          break;
        case SyncReconciliationStatus.conflict:
          conflictCount++;
          break;
        case SyncReconciliationStatus.outOfSync:
          outOfSyncCount++;
          break;
        case SyncReconciliationStatus.missingRemote:
          missingRemoteCount++;
          break;
        case SyncReconciliationStatus.missingLocal:
          missingLocalCount++;
          break;
        case SyncReconciliationStatus.invalidLink:
          invalidLinkCount++;
          break;
        case SyncReconciliationStatus.orphanRemote:
          orphanRemoteCount++;
          break;
        case SyncReconciliationStatus.unknown:
          unknownCount++;
          break;
      }
    }

    return SyncReconciliationResult(
      featureKey: featureKey,
      displayName: displayName,
      checkedAt: checkedAt,
      totalLocal: totalLocal,
      totalRemote: totalRemote,
      consistentCount: consistentCount,
      localOnlyCount: localOnlyCount,
      remoteOnlyCount: remoteOnlyCount,
      pendingSyncCount: pendingSyncCount,
      conflictCount: conflictCount,
      outOfSyncCount: outOfSyncCount,
      missingRemoteCount: missingRemoteCount,
      missingLocalCount: missingLocalCount,
      invalidLinkCount: invalidLinkCount,
      orphanRemoteCount: orphanRemoteCount,
      unknownCount: unknownCount,
      issues: issues,
      fetchError: fetchError,
    );
  }

  final String featureKey;
  final String displayName;
  final DateTime checkedAt;
  final int totalLocal;
  final int totalRemote;
  final int consistentCount;
  final int localOnlyCount;
  final int remoteOnlyCount;
  final int pendingSyncCount;
  final int conflictCount;
  final int outOfSyncCount;
  final int missingRemoteCount;
  final int missingLocalCount;
  final int invalidLinkCount;
  final int orphanRemoteCount;
  final int unknownCount;
  final List<SyncReconciliationIssue> issues;
  final String? fetchError;

  int get issueCount => issues.where((issue) => !issue.status.isHealthy).length;

  int get repairableCount =>
      issues.where((issue) => issue.canMarkForResync).length;

  int get manualReviewCount => issues
      .where((issue) => issue.status == SyncReconciliationStatus.conflict)
      .length;

  List<SyncReconciliationIssue> get highlightedIssues {
    return issues.where((issue) => !issue.status.isHealthy).take(5).toList();
  }
}
