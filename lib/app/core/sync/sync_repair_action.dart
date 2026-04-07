import 'sync_repair_action_type.dart';
import 'sync_repair_target.dart';

class SyncRepairAction {
  const SyncRepairAction({
    required this.type,
    required this.target,
    required this.confidence,
    required this.reason,
  });

  final SyncRepairActionType type;
  final SyncRepairTarget target;
  final double confidence;
  final String reason;
}
