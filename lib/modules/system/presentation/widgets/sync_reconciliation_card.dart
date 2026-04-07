import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/sync/sync_reconciliation_issue.dart';
import '../../../../app/core/sync/sync_reconciliation_result.dart';
import '../../../../app/core/sync/sync_reconciliation_status.dart';
import '../../../../app/core/sync/sync_queue_status.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../../../app/core/widgets/app_status_badge.dart';

class SyncReconciliationCard extends StatelessWidget {
  const SyncReconciliationCard({
    super.key,
    required this.result,
    required this.canRunReconciliation,
    required this.isLoading,
    this.onRepair,
  });

  final SyncReconciliationResult result;
  final bool canRunReconciliation;
  final bool isLoading;
  final VoidCallback? onRepair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final divergentCount =
        result.outOfSyncCount +
        result.missingRemoteCount +
        result.invalidLinkCount +
        result.remoteOnlyCount +
        result.orphanRemoteCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.displayName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              AppStatusBadge(
                label: result.issueCount == 0 ? 'Consistente' : 'Atencao',
                tone: result.issueCount == 0
                    ? AppStatusTone.success
                    : AppStatusTone.warning,
                icon: result.issueCount == 0
                    ? Icons.verified_outlined
                    : Icons.rule_folder_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                label: '${result.consistentCount} consistente(s)',
                icon: Icons.cloud_done_outlined,
              ),
              _MetricChip(
                label: '${result.pendingSyncCount} pendente(s)',
                icon: Icons.pending_actions_rounded,
              ),
              _MetricChip(
                label: '$divergentCount divergencia(s)',
                icon: Icons.compare_arrows_rounded,
              ),
              _MetricChip(
                label: '${result.conflictCount} conflito(s)',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ultima reconciliacao em ${AppFormatters.shortDateTime(result.checkedAt)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (result.fetchError != null) ...[
            const SizedBox(height: 10),
            Text(
              result.fetchError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          if (result.highlightedIssues.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...result.highlightedIssues.map(_buildIssueTile),
          ],
          if (result.repairableCount > 0) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: isLoading || !canRunReconciliation ? null : onRepair,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(
                isLoading
                    ? 'Revalidando...'
                    : 'Marcar ${result.repairableCount} item(ns) para reenvio',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIssueTile(SyncReconciliationIssue issue) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        issue.entityLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppStatusBadge(
                      label: issue.status.label,
                      tone: _toneFor(issue.status),
                      icon: _iconFor(issue.status),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  issue.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (issue.localUuid != null && issue.localUuid!.isNotEmpty)
                      _MetaTag(label: 'Local ${issue.localUuid}'),
                    if (issue.remoteId != null && issue.remoteId!.isNotEmpty)
                      _MetaTag(label: 'Remoto ${issue.remoteId}'),
                    if (issue.queueStatus != null)
                      _MetaTag(label: 'Fila ${issue.queueStatus!.label}'),
                    if (issue.metadataStatus != null)
                      _MetaTag(label: 'Meta ${issue.metadataStatus!.label}'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  AppStatusTone _toneFor(SyncReconciliationStatus status) {
    switch (status) {
      case SyncReconciliationStatus.consistent:
        return AppStatusTone.success;
      case SyncReconciliationStatus.pendingSync:
      case SyncReconciliationStatus.localOnly:
        return AppStatusTone.info;
      case SyncReconciliationStatus.conflict:
      case SyncReconciliationStatus.invalidLink:
      case SyncReconciliationStatus.missingRemote:
      case SyncReconciliationStatus.missingLocal:
      case SyncReconciliationStatus.outOfSync:
      case SyncReconciliationStatus.remoteOnly:
      case SyncReconciliationStatus.orphanRemote:
      case SyncReconciliationStatus.unknown:
        return AppStatusTone.warning;
    }
  }

  IconData _iconFor(SyncReconciliationStatus status) {
    switch (status) {
      case SyncReconciliationStatus.consistent:
        return Icons.verified_outlined;
      case SyncReconciliationStatus.pendingSync:
        return Icons.pending_actions_rounded;
      case SyncReconciliationStatus.localOnly:
        return Icons.offline_pin_rounded;
      case SyncReconciliationStatus.remoteOnly:
      case SyncReconciliationStatus.orphanRemote:
        return Icons.cloud_outlined;
      case SyncReconciliationStatus.conflict:
        return Icons.warning_amber_rounded;
      case SyncReconciliationStatus.outOfSync:
      case SyncReconciliationStatus.invalidLink:
      case SyncReconciliationStatus.missingRemote:
      case SyncReconciliationStatus.missingLocal:
        return Icons.compare_arrows_rounded;
      case SyncReconciliationStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
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
