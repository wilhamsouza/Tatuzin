import 'sync_repair_action_type.dart';

class SyncRepairResult {
  const SyncRepairResult({
    required this.requestedCount,
    required this.appliedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.executedAt,
    required this.message,
    this.actionType,
  });

  final int requestedCount;
  final int appliedCount;
  final int skippedCount;
  final int failedCount;
  final DateTime executedAt;
  final String message;
  final SyncRepairActionType? actionType;
}
