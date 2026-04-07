import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/sync/sync_audit_event_type.dart';
import '../../../../app/core/sync/sync_audit_log.dart';
import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../../../app/core/widgets/app_status_badge.dart';

class SyncAuditCard extends StatelessWidget {
  const SyncAuditCard({super.key, required this.logs});

  final List<SyncAuditLog> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (logs.isEmpty) {
      return Text(
        'Ainda nao ha trilha de auditoria registrada nesta base local.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      children: logs
          .map(
            (log) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
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
                                syncFeatureDisplayName(log.featureKey),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppFormatters.shortDateTime(log.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppStatusBadge(
                          label: log.eventType.label,
                          tone: _toneFor(log.eventType.storageValue),
                          icon: _iconFor(log.eventType.storageValue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(log.message, style: theme.textTheme.bodyMedium),
                    if (log.entityType != null ||
                        log.localUuid != null ||
                        log.remoteId != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (log.entityType != null)
                            _Tag(label: log.entityType!),
                          if (log.localUuid != null)
                            _Tag(label: 'Local ${log.localUuid}'),
                          if (log.remoteId != null)
                            _Tag(label: 'Remoto ${log.remoteId}'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  AppStatusTone _toneFor(String storageValue) {
    switch (storageValue) {
      case 'synced':
      case 'reconciliation_checked':
      case 'repair_applied':
      case 'relink_applied':
      case 'status_reclassified':
      case 'dependency_chain_retried':
      case 'stale_block_cleared':
      case 'reenqueue_requested':
        return AppStatusTone.success;
      case 'failed':
      case 'conflict_detected':
      case 'repair_failed':
      case 'relink_rejected':
        return AppStatusTone.warning;
      case 'blocked_dependency':
      case 'repair_requested':
      case 'repair_skipped':
      case 'repair_manual_review_required':
        return AppStatusTone.info;
      default:
        return AppStatusTone.neutral;
    }
  }

  IconData _iconFor(String storageValue) {
    switch (storageValue) {
      case 'synced':
        return Icons.cloud_done_outlined;
      case 'reconciliation_checked':
        return Icons.rule_folder_outlined;
      case 'repair_applied':
        return Icons.build_circle_outlined;
      case 'relink_applied':
        return Icons.link_rounded;
      case 'status_reclassified':
        return Icons.tune_rounded;
      case 'dependency_chain_retried':
        return Icons.account_tree_outlined;
      case 'stale_block_cleared':
        return Icons.lock_open_outlined;
      case 'reenqueue_requested':
        return Icons.cloud_upload_outlined;
      case 'failed':
      case 'repair_failed':
        return Icons.error_outline_rounded;
      case 'conflict_detected':
      case 'relink_rejected':
        return Icons.warning_amber_rounded;
      case 'blocked_dependency':
        return Icons.link_off_rounded;
      case 'processing_started':
        return Icons.sync_rounded;
      case 'repair_requested':
        return Icons.playlist_add_check_circle_outlined;
      case 'repair_skipped':
        return Icons.skip_next_outlined;
      case 'repair_manual_review_required':
        return Icons.fact_check_outlined;
      default:
        return Icons.history_rounded;
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
