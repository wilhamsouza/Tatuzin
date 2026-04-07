import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../../../app/core/sync/sync_queue_status.dart';
import '../../../../app/core/sync/sync_reconciliation_status.dart';
import '../../../../app/core/sync/sync_repair_action_type.dart';
import '../../../../app/core/sync/sync_repair_decision.dart';
import '../../../../app/core/sync/sync_repairability.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../../../app/core/widgets/app_status_badge.dart';

class SyncRepairIssueTile extends StatelessWidget {
  const SyncRepairIssueTile({
    super.key,
    required this.decision,
    required this.isBusy,
    required this.onTapActions,
  });

  final SyncRepairDecision decision;
  final bool isBusy;
  final VoidCallback onTapActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      decision.target.entityLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      syncFeatureDisplayName(decision.target.featureKey),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              AppStatusBadge(
                label: decision.repairability.label,
                tone: _toneForRepairability(decision.repairability),
                icon: _iconForRepairability(decision.repairability),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            decision.reason,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Tag(label: decision.status.label),
              _Tag(label: 'Confianca ${(decision.confidence * 100).round()}%'),
              if (decision.queueStatus != null)
                _Tag(label: 'Fila ${decision.queueStatus!.label}'),
              if (decision.metadataStatus != null)
                _Tag(label: 'Meta ${decision.metadataStatus!.label}'),
              if (decision.suggestedActionType != null)
                _Tag(label: 'Sugestao ${decision.suggestedActionType!.label}'),
            ],
          ),
          if (decision.lastError != null &&
              decision.lastError!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                decision.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: isBusy || !decision.hasActions ? null : onTapActions,
              icon: Icon(
                decision.needsManualReview
                    ? Icons.fact_check_outlined
                    : Icons.build_circle_outlined,
              ),
              label: Text(
                decision.needsManualReview
                    ? 'Ver orientacoes'
                    : 'Acoes de repair',
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppStatusTone _toneForRepairability(SyncRepairability repairability) {
    switch (repairability) {
      case SyncRepairability.autoSafe:
        return AppStatusTone.success;
      case SyncRepairability.assistedSafe:
        return AppStatusTone.info;
      case SyncRepairability.manualReviewOnly:
        return AppStatusTone.warning;
      case SyncRepairability.blocked:
      case SyncRepairability.notRepairableYet:
        return AppStatusTone.neutral;
    }
  }

  IconData _iconForRepairability(SyncRepairability repairability) {
    switch (repairability) {
      case SyncRepairability.autoSafe:
        return Icons.auto_fix_high_rounded;
      case SyncRepairability.assistedSafe:
        return Icons.handyman_outlined;
      case SyncRepairability.manualReviewOnly:
        return Icons.manage_search_rounded;
      case SyncRepairability.blocked:
        return Icons.lock_outline_rounded;
      case SyncRepairability.notRepairableYet:
        return Icons.pause_circle_outline_rounded;
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
