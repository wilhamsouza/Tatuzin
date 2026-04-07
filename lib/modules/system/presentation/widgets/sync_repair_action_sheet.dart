import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_repair_action.dart';
import '../../../../app/core/sync/sync_repair_action_type.dart';
import '../../../../app/core/sync/sync_repair_decision.dart';

class SyncRepairActionSheet extends StatelessWidget {
  const SyncRepairActionSheet({super.key, required this.decision});

  final SyncRepairDecision decision;

  @override
  Widget build(BuildContext context) {
    final actions = decision.availableActions
        .map(
          (type) => SyncRepairAction(
            type: type,
            target: decision.target,
            confidence: decision.confidence,
            reason: decision.reason,
          ),
        )
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              decision.target.entityLabel,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              decision.reason,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...actions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_iconForAction(action.type)),
                  title: Text(action.type.label),
                  subtitle: Text(action.type.description),
                  onTap: () => Navigator.of(context).pop(action),
                ),
              ),
            ),
            if (actions.isEmpty)
              Text(
                'Este caso exige revisao manual e nao possui repair seguro disponivel agora.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForAction(SyncRepairActionType type) {
    switch (type) {
      case SyncRepairActionType.reenqueueForSync:
        return Icons.cloud_upload_outlined;
      case SyncRepairActionType.relinkRemoteId:
      case SyncRepairActionType.repairRemoteLink:
        return Icons.link_rounded;
      case SyncRepairActionType.clearInvalidRemoteId:
        return Icons.link_off_rounded;
      case SyncRepairActionType.retryDependencyChain:
      case SyncRepairActionType.rebuildDependencyState:
      case SyncRepairActionType.clearStaleBlock:
        return Icons.account_tree_outlined;
      case SyncRepairActionType.markConflictReviewed:
        return Icons.fact_check_outlined;
      case SyncRepairActionType.refreshRemoteSnapshot:
      case SyncRepairActionType.revalidateRemotePresence:
        return Icons.refresh_rounded;
      case SyncRepairActionType.reclassifySyncStatus:
      case SyncRepairActionType.repairLocalMetadata:
        return Icons.tune_rounded;
      case SyncRepairActionType.markMissingRemote:
      case SyncRepairActionType.markMissingLocal:
        return Icons.report_gmailerrorred_rounded;
      case SyncRepairActionType.relinkLocalUuid:
        return Icons.badge_outlined;
    }
  }
}
