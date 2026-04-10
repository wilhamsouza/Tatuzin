import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../providers/system_providers.dart';
import 'system_support_widgets.dart';

class SystemSyncHealthSection extends StatelessWidget {
  const SystemSyncHealthSection({
    required this.syncHealth,
    required this.isLoading,
    required this.canRunManualSync,
    required this.onSyncAll,
    required this.onRetryPending,
    super.key,
  });

  final SyncHealthOverview syncHealth;
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
                label: '${syncHealth.totalPending} pendente(s)',
                icon: Icons.pending_actions_rounded,
              ),
              SystemModeChip(
                label: '${syncHealth.totalProcessing} processando',
                icon: Icons.sync_rounded,
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
          const SizedBox(height: 8),
          Text(
            'Tentativas acumuladas na fila: ${syncHealth.totalAttempts}.',
            style: theme.textTheme.bodyMedium,
          ),
          if (syncHealth.nextRetryAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Proximo retry automatico elegivel em ${AppFormatters.shortDateTime(syncHealth.nextRetryAt!)}.',
              style: theme.textTheme.bodyMedium,
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
                label: Text(isLoading ? 'Sincronizando...' : 'Sincronizar tudo'),
              ),
              OutlinedButton.icon(
                onPressed:
                    isLoading || !canRunManualSync ? null : onRetryPending,
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
