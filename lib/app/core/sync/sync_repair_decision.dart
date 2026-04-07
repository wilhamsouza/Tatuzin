import 'sync_queue_status.dart';
import 'sync_reconciliation_status.dart';
import 'sync_repair_action_type.dart';
import 'sync_repair_target.dart';
import 'sync_repairability.dart';
import 'sync_status.dart';

class SyncRepairDecision {
  const SyncRepairDecision({
    required this.target,
    required this.status,
    required this.repairability,
    required this.reason,
    required this.confidence,
    required this.availableActions,
    required this.suggestedActionType,
    required this.isBatchSafe,
    required this.requiresConfirmation,
    this.queueStatus,
    this.metadataStatus,
    this.lastError,
    this.lastErrorType,
    this.localPayloadSignature,
    this.remotePayloadSignature,
  });

  final SyncRepairTarget target;
  final SyncReconciliationStatus status;
  final SyncRepairability repairability;
  final String reason;
  final double confidence;
  final List<SyncRepairActionType> availableActions;
  final SyncRepairActionType? suggestedActionType;
  final bool isBatchSafe;
  final bool requiresConfirmation;
  final SyncQueueStatus? queueStatus;
  final SyncStatus? metadataStatus;
  final String? lastError;
  final String? lastErrorType;
  final String? localPayloadSignature;
  final String? remotePayloadSignature;

  String get stableKey => target.stableKey;

  bool get hasActions => availableActions.isNotEmpty;

  bool get needsManualReview =>
      repairability == SyncRepairability.manualReviewOnly;
}
