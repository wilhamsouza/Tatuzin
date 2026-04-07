import 'sync_metadata.dart';
import 'sync_status.dart';

class SyncFeatureSummary {
  const SyncFeatureSummary({
    required this.featureKey,
    required this.displayName,
    required this.totalRecords,
    required this.localOnlyCount,
    required this.pendingUploadCount,
    required this.pendingUpdateCount,
    required this.syncedCount,
    required this.conflictCount,
    required this.errorCount,
    required this.lastLocalChangeAt,
    required this.lastSyncedAt,
    required this.lastErrorMessage,
    required this.lastErrorType,
    required this.lastErrorAt,
  });

  factory SyncFeatureSummary.fromMetadata({
    required String featureKey,
    required String displayName,
    required List<SyncMetadata> metadata,
  }) {
    var localOnlyCount = 0;
    var pendingUploadCount = 0;
    var pendingUpdateCount = 0;
    var syncedCount = 0;
    var conflictCount = 0;
    var errorCount = 0;
    DateTime? lastLocalChangeAt;
    DateTime? lastSyncedAt;
    String? lastErrorMessage;
    String? lastErrorType;
    DateTime? lastErrorAt;

    for (final item in metadata) {
      switch (item.status) {
        case SyncStatus.localOnly:
          localOnlyCount++;
          break;
        case SyncStatus.pendingUpload:
          pendingUploadCount++;
          break;
        case SyncStatus.synced:
          syncedCount++;
          break;
        case SyncStatus.pendingUpdate:
          pendingUpdateCount++;
          break;
        case SyncStatus.syncError:
          errorCount++;
          break;
        case SyncStatus.conflict:
          conflictCount++;
          break;
      }

      if (lastLocalChangeAt == null ||
          item.updatedAt.isAfter(lastLocalChangeAt)) {
        lastLocalChangeAt = item.updatedAt;
      }

      if (item.lastSyncedAt != null &&
          (lastSyncedAt == null || item.lastSyncedAt!.isAfter(lastSyncedAt))) {
        lastSyncedAt = item.lastSyncedAt;
      }

      if (item.lastErrorAt != null &&
          (lastErrorAt == null || item.lastErrorAt!.isAfter(lastErrorAt))) {
        lastErrorAt = item.lastErrorAt;
        lastErrorMessage = item.lastError;
        lastErrorType = item.lastErrorType;
      }
    }

    return SyncFeatureSummary(
      featureKey: featureKey,
      displayName: displayName,
      totalRecords: metadata.length,
      localOnlyCount: localOnlyCount,
      pendingUploadCount: pendingUploadCount,
      pendingUpdateCount: pendingUpdateCount,
      syncedCount: syncedCount,
      conflictCount: conflictCount,
      errorCount: errorCount,
      lastLocalChangeAt: lastLocalChangeAt,
      lastSyncedAt: lastSyncedAt,
      lastErrorMessage: lastErrorMessage,
      lastErrorType: lastErrorType,
      lastErrorAt: lastErrorAt,
    );
  }

  final String featureKey;
  final String displayName;
  final int totalRecords;
  final int localOnlyCount;
  final int pendingUploadCount;
  final int pendingUpdateCount;
  final int syncedCount;
  final int conflictCount;
  final int errorCount;
  final DateTime? lastLocalChangeAt;
  final DateTime? lastSyncedAt;
  final String? lastErrorMessage;
  final String? lastErrorType;
  final DateTime? lastErrorAt;
}
