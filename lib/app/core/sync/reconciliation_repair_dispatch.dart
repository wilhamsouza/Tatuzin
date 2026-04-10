import 'sync_repair_action_type.dart';

enum RepairDispatchTarget {
  repairIssue,
  applyRemoteRelink,
  clearBrokenRemoteLink,
  retryDependencyChain,
  clearStaleBlock,
  unsupported,
}

class ReconciliationRepairDispatch {
  const ReconciliationRepairDispatch._();

  static RepairDispatchTarget resolve(SyncRepairActionType actionType) {
    switch (actionType) {
      case SyncRepairActionType.reenqueueForSync:
        return RepairDispatchTarget.repairIssue;
      case SyncRepairActionType.relinkRemoteId:
        return RepairDispatchTarget.applyRemoteRelink;
      case SyncRepairActionType.clearInvalidRemoteId:
        return RepairDispatchTarget.clearBrokenRemoteLink;
      case SyncRepairActionType.retryDependencyChain:
        return RepairDispatchTarget.retryDependencyChain;
      case SyncRepairActionType.clearStaleBlock:
        return RepairDispatchTarget.clearStaleBlock;
      case SyncRepairActionType.markConflictReviewed:
      case SyncRepairActionType.markMissingRemote:
      case SyncRepairActionType.markMissingLocal:
      case SyncRepairActionType.refreshRemoteSnapshot:
      case SyncRepairActionType.repairRemoteLink:
      case SyncRepairActionType.repairLocalMetadata:
      case SyncRepairActionType.rebuildDependencyState:
      case SyncRepairActionType.reclassifySyncStatus:
      case SyncRepairActionType.revalidateRemotePresence:
      case SyncRepairActionType.relinkLocalUuid:
        return RepairDispatchTarget.unsupported;
    }
  }
}
