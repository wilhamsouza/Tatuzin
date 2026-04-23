import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/sync/sync_display_state.dart';
import '../../../../app/core/sync/sync_error_type.dart';
import '../../../../app/core/sync/sync_queue_feature_summary.dart';

class SyncFeatureCard extends StatelessWidget {
  const SyncFeatureCard({
    super.key,
    required this.title,
    required this.summary,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
  });

  final String title;
  final SyncQueueFeatureSummary? summary;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayState = summary?.displayState;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (displayState != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(colorScheme),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    displayState.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _statusOnColor(colorScheme),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Chip(
                label: '${summary?.totalTracked ?? 0} total',
                icon: Icons.inventory_2_outlined,
              ),
              _Chip(
                label: '${summary?.pendingForDisplay ?? 0} pendente',
                icon: Icons.pending_actions_rounded,
              ),
              _Chip(
                label:
                    '${summary?.activeProcessingCount ?? 0} processando agora',
                icon: Icons.sync_rounded,
              ),
              if ((summary?.staleProcessingCount ?? 0) > 0)
                _Chip(
                  label:
                      '${summary?.staleProcessingCount ?? 0} processing antigo',
                  icon: Icons.history_toggle_off_rounded,
                ),
              _Chip(
                label: '${summary?.syncedCount ?? 0} sync',
                icon: Icons.cloud_done_outlined,
              ),
              _Chip(
                label: '${summary?.errorCount ?? 0} erro',
                icon: Icons.error_outline_rounded,
              ),
              if ((summary?.blockedCount ?? 0) > 0)
                _Chip(
                  label: '${summary?.blockedCount ?? 0} bloqueado',
                  icon: Icons.link_off_rounded,
                ),
              if ((summary?.conflictCount ?? 0) > 0)
                _Chip(
                  label: '${summary?.conflictCount ?? 0} conflito',
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary?.lastProcessedAt == null
                ? 'Ainda sem processamento concluido nesta fila.'
                : 'Ultimo processamento: ${AppFormatters.shortDateTime(summary!.lastProcessedAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (summary?.nextRetryAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Proximo retry: ${AppFormatters.shortDateTime(summary!.nextRetryAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if ((summary?.totalAttemptCount ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Tentativas acumuladas: ${summary!.totalAttemptCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (summary?.lastError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary!.lastErrorType == null
                        ? 'Ultima falha registrada'
                        : 'Ultima falha: ${summary!.lastErrorType!.label}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary!.lastError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: isLoading || !isEnabled ? null : onPressed,
            icon: Icon(
              isLoading ? Icons.sync_rounded : Icons.cloud_upload_outlined,
            ),
            label: Text(isLoading ? 'Sincronizando...' : buttonLabel),
          ),
        ],
      ),
    );
  }

  Color _statusColor(ColorScheme colorScheme) {
    if (summary?.hasAttention == true) {
      return colorScheme.errorContainer;
    }
    if (summary?.hasActiveProcessing == true) {
      return colorScheme.primaryContainer;
    }
    if ((summary?.pendingForDisplay ?? 0) > 0) {
      return colorScheme.secondaryContainer;
    }
    return colorScheme.tertiaryContainer;
  }

  Color _statusOnColor(ColorScheme colorScheme) {
    if (summary?.hasAttention == true) {
      return colorScheme.onErrorContainer;
    }
    if (summary?.hasActiveProcessing == true) {
      return colorScheme.onPrimaryContainer;
    }
    if ((summary?.pendingForDisplay ?? 0) > 0) {
      return colorScheme.onSecondaryContainer;
    }
    return colorScheme.onTertiaryContainer;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

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
