import 'sync_queue_item.dart';
import 'sync_status.dart';

class ReconciliationLocalComparableRecord {
  const ReconciliationLocalComparableRecord({
    required this.featureKey,
    required this.entityType,
    required this.localId,
    required this.localUuid,
    required this.remoteId,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    required this.metadataStatus,
    required this.queueItem,
    required this.lastError,
    required this.lastErrorType,
    required this.payload,
    required this.allowRepair,
  });

  final String featureKey;
  final String entityType;
  final int localId;
  final String localUuid;
  final String? remoteId;
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus? metadataStatus;
  final SyncQueueItem? queueItem;
  final String? lastError;
  final String? lastErrorType;
  final Map<String, dynamic> payload;
  final bool allowRepair;
}
