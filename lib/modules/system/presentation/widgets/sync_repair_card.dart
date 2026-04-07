import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_repair_decision.dart';
import '../../../../app/core/sync/sync_repairability.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import 'sync_repair_issue_tile.dart';

class SyncRepairCard extends StatelessWidget {
  const SyncRepairCard({
    super.key,
    required this.title,
    required this.decisions,
    required this.canRunRepair,
    required this.isLoading,
    required this.onRunSafeRepairs,
    required this.onOpenDecision,
  });

  final String title;
  final List<SyncRepairDecision> decisions;
  final bool canRunRepair;
  final bool isLoading;
  final VoidCallback? onRunSafeRepairs;
  final ValueChanged<SyncRepairDecision> onOpenDecision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final autoSafeCount = decisions
        .where(
          (decision) => decision.repairability == SyncRepairability.autoSafe,
        )
        .length;
    final assistedCount = decisions
        .where(
          (decision) =>
              decision.repairability == SyncRepairability.assistedSafe,
        )
        .length;
    final reviewCount = decisions
        .where(
          (decision) =>
              decision.repairability == SyncRepairability.manualReviewOnly,
        )
        .length;
    final blockedCount = decisions
        .where(
          (decision) => decision.repairability == SyncRepairability.blocked,
        )
        .length;
    final batchSafeCount = decisions
        .where((decision) => decision.isBatchSafe)
        .length;

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
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              AppStatusBadge(
                label: decisions.isEmpty
                    ? 'Sem acoes'
                    : '${decisions.length} issue(s)',
                tone: decisions.isEmpty
                    ? AppStatusTone.success
                    : AppStatusTone.warning,
                icon: decisions.isEmpty
                    ? Icons.verified_outlined
                    : Icons.build_circle_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Chip(
                label: '$autoSafeCount seguro(s)',
                icon: Icons.auto_fix_high_rounded,
              ),
              _Chip(
                label: '$assistedCount assistido(s)',
                icon: Icons.handyman_outlined,
              ),
              _Chip(
                label: '$reviewCount revisao',
                icon: Icons.manage_search_rounded,
              ),
              if (blockedCount > 0)
                _Chip(
                  label: '$blockedCount bloqueado(s)',
                  icon: Icons.lock_outline_rounded,
                ),
            ],
          ),
          if (decisions.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Nenhuma divergencia desta feature exige repair assistido agora.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            ...decisions
                .take(3)
                .map(
                  (decision) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SyncRepairIssueTile(
                      decision: decision,
                      isBusy: isLoading,
                      onTapActions: () => onOpenDecision(decision),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isLoading || !canRunRepair || batchSafeCount == 0
                ? null
                : onRunSafeRepairs,
            icon: Icon(
              isLoading ? Icons.sync_rounded : Icons.auto_fix_high_rounded,
            ),
            label: Text(
              isLoading
                  ? 'Aplicando...'
                  : 'Executar $batchSafeCount reparo(s) seguro(s)',
            ),
          ),
        ],
      ),
    );
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
