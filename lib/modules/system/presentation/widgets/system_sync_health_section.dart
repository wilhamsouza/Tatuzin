import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/sync/auto_sync_coordinator.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../providers/system_providers.dart';
import 'system_support_widgets.dart';

class SystemSyncHealthSection extends StatelessWidget {
  const SystemSyncHealthSection({
    required this.syncHealth,
    required this.autoSyncSnapshot,
    required this.isLoading,
    required this.canRunManualSync,
    required this.onSyncAll,
    required this.onRetryPending,
    super.key,
  });

  final SyncHealthOverview syncHealth;
  final AutoSyncCoordinatorSnapshot autoSyncSnapshot;
  final bool isLoading;
  final bool canRunManualSync;
  final VoidCallback onSyncAll;
  final VoidCallback onRetryPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      title: 'Saude da sincronizacao',
      subtitle:
          'Visao consolidada da fila persistida, retries, bloqueios por dependencia e conflitos iniciais dos cadastros sincronizaveis.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SystemModeChip(
                label: '${syncHealth.totalPendingForDisplay} pendente(s)',
                icon: Icons.pending_actions_rounded,
              ),
              SystemModeChip(
                label:
                    'Auto-sync ${autoSyncSnapshot.phase.label.toLowerCase()}',
                icon: autoSyncSnapshot.isRunning
                    ? Icons.sync_rounded
                    : autoSyncSnapshot.isScheduled
                    ? Icons.schedule_rounded
                    : Icons.pause_circle_outline_rounded,
              ),
              SystemModeChip(
                label: '${syncHealth.totalActiveProcessing} processando agora',
                icon: Icons.sync_rounded,
              ),
              if (syncHealth.totalStaleProcessing > 0)
                SystemModeChip(
                  label: '${syncHealth.totalStaleProcessing} processing antigo',
                  icon: Icons.history_toggle_off_rounded,
                ),
              SystemModeChip(
                label: '${syncHealth.totalSynced} sincronizado(s)',
                icon: Icons.cloud_done_outlined,
              ),
              SystemModeChip(
                label: '${syncHealth.totalErrors} erro(s)',
                icon: Icons.error_outline_rounded,
              ),
              SystemModeChip(
                label: '${syncHealth.totalBlocked} bloqueado(s)',
                icon: Icons.link_off_rounded,
              ),
              SystemModeChip(
                label: '${syncHealth.totalConflicts} conflito(s)',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            syncHealth.lastProcessedAt == null
                ? 'Ainda sem processamento concluido nesta base local.'
                : 'Ultimo processamento de fila em ${AppFormatters.shortDateTime(syncHealth.lastProcessedAt!)}.',
            style: theme.textTheme.bodyMedium,
          ),
          if (autoSyncSnapshot.lastStartedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              autoSyncSnapshot.lastFinishedAt == null ||
                      autoSyncSnapshot.lastFinishedAt!.isBefore(
                        autoSyncSnapshot.lastStartedAt!,
                      )
                  ? 'Ultimo auto-sync iniciado em ${AppFormatters.shortDateTime(autoSyncSnapshot.lastStartedAt!)}.'
                  : 'Ultimo auto-sync executado de ${AppFormatters.shortDateTime(autoSyncSnapshot.lastStartedAt!)} ate ${AppFormatters.shortDateTime(autoSyncSnapshot.lastFinishedAt!)}.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Tentativas acumuladas na fila: ${syncHealth.totalAttempts}.',
            style: theme.textTheme.bodyMedium,
          ),
          if (autoSyncSnapshot.currentReason != null) ...[
            const SizedBox(height: 8),
            Text(
              autoSyncSnapshot.isRunning
                  ? 'Motivo atual do lote automatico: ${autoSyncSnapshot.currentReason}.'
                  : autoSyncSnapshot.isScheduled
                  ? 'Motivo do proximo disparo automatico: ${autoSyncSnapshot.currentReason}.'
                  : 'Ultimo gatilho automatico observado: ${autoSyncSnapshot.currentReason}.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (autoSyncSnapshot.followUpQueued) ...[
            const SizedBox(height: 8),
            Text(
              'Um lote complementar ja foi reservado porque novas mutacoes chegaram durante o processamento atual.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (syncHealth.totalProcessing >
              syncHealth.totalActiveProcessing) ...[
            const SizedBox(height: 8),
            Text(
              'Locks antigos nao contam mais como sync ativo e entram como pendencia recuperavel.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (autoSyncSnapshot.nextScheduledAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Proximo disparo automatico previsto para ${AppFormatters.shortDateTime(autoSyncSnapshot.nextScheduledAt!)}.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (syncHealth.nextRetryAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Proximo retry automatico elegivel em ${AppFormatters.shortDateTime(syncHealth.nextRetryAt!)}.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (autoSyncSnapshot.lastResult != null) ...[
            const SizedBox(height: 8),
            Text(
              '${autoSyncSnapshot.lastResult!.message} Duracao aproximada: ${autoSyncSnapshot.lastResult!.duration.inSeconds}s.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (autoSyncSnapshot.lastFailureMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ultima falha do orquestrador: ${autoSyncSnapshot.lastFailureMessage!}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (syncHealth.lastErrorAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ultima falha registrada em ${AppFormatters.shortDateTime(syncHealth.lastErrorAt!)}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isLoading || !canRunManualSync ? null : onSyncAll,
                icon: const Icon(Icons.cloud_sync_outlined),
                label: Text(
                  isLoading ? 'Sincronizando...' : 'Sincronizar tudo',
                ),
              ),
              OutlinedButton.icon(
                onPressed: isLoading || !canRunManualSync
                    ? null
                    : onRetryPending,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reprocessar pendentes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
