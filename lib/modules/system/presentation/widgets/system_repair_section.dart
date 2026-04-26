import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_repair_decision.dart';
import '../../../../app/core/sync/sync_repair_summary.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import 'sync_repair_card.dart';
import 'system_support_widgets.dart';

class SystemRepairSection extends StatelessWidget {
  const SystemRepairSection({
    required this.summary,
    required this.canRunManualSync,
    required this.isRepairLoading,
    required this.isReconciliationLoading,
    required this.errorMessage,
    required this.supplierRepairs,
    required this.categoryRepairs,
    required this.productRepairs,
    required this.customerRepairs,
    required this.purchaseRepairs,
    required this.salesRepairs,
    required this.financialRepairs,
    required this.onRunSafeRepairs,
    required this.onRefreshDiagnostics,
    required this.onRunSafeRepairsForFeature,
    required this.onOpenDecision,
    super.key,
  });

  final SyncRepairSummary summary;
  final bool canRunManualSync;
  final bool isRepairLoading;
  final bool isReconciliationLoading;
  final String? errorMessage;
  final List<SyncRepairDecision> supplierRepairs;
  final List<SyncRepairDecision> categoryRepairs;
  final List<SyncRepairDecision> productRepairs;
  final List<SyncRepairDecision> customerRepairs;
  final List<SyncRepairDecision> purchaseRepairs;
  final List<SyncRepairDecision> salesRepairs;
  final List<SyncRepairDecision> financialRepairs;
  final VoidCallback onRunSafeRepairs;
  final VoidCallback onRefreshDiagnostics;
  final ValueChanged<String> onRunSafeRepairsForFeature;
  final ValueChanged<SyncRepairDecision> onOpenDecision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      title: 'Repair mode avancado',
      subtitle:
          'Correcao assistida e auditavel de vinculos, bloqueios e reenvios seguros, sem tocar nas regras operacionais locais.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SystemModeChip(
                label: '${summary.totalIssues} issue(s)',
                icon: Icons.build_circle_outlined,
              ),
              SystemModeChip(
                label: '${summary.autoSafeCount} seguro(s)',
                icon: Icons.auto_fix_high_rounded,
              ),
              SystemModeChip(
                label: '${summary.assistedSafeCount} assistido(s)',
                icon: Icons.handyman_outlined,
              ),
              SystemModeChip(
                label: '${summary.manualReviewCount} revisao manual',
                icon: Icons.manage_search_rounded,
              ),
              if (summary.batchSafeCount > 0)
                SystemModeChip(
                  label: '${summary.batchSafeCount} em lote',
                  icon: Icons.playlist_add_check_circle_outlined,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isRepairLoading || !canRunManualSync
                    ? null
                    : onRunSafeRepairs,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: Text(
                  isRepairLoading
                      ? 'Aplicando reparos...'
                      : 'Executar reparos seguros',
                ),
              ),
              OutlinedButton.icon(
                onPressed: isReconciliationLoading || !canRunManualSync
                    ? null
                    : onRefreshDiagnostics,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar diagnostico'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (errorMessage != null)
            Text(
              errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (summary.totalIssues == 0)
            Text(
              'Nenhuma issue reparavel foi identificada no ultimo diagnostico. Execute a reconciliacao para atualizar esta leitura.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(children: _buildCards()),
        ],
      ),
    );
  }

  List<Widget> _buildCards() {
    final widgets = <Widget>[];

    void addCard({
      required String title,
      required String featureKey,
      required List<SyncRepairDecision> decisions,
    }) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
      }
      widgets.add(
        SyncRepairCard(
          title: title,
          decisions: decisions,
          canRunRepair: canRunManualSync,
          isLoading: isRepairLoading,
          onRunSafeRepairs: decisions.isEmpty
              ? null
              : () => onRunSafeRepairsForFeature(featureKey),
          onOpenDecision: onOpenDecision,
        ),
      );
    }

    addCard(
      title: 'Fornecedores',
      featureKey: 'suppliers',
      decisions: supplierRepairs,
    );
    addCard(
      title: 'Categorias',
      featureKey: 'categories',
      decisions: categoryRepairs,
    );
    addCard(
      title: 'Produtos',
      featureKey: 'products',
      decisions: productRepairs,
    );
    addCard(
      title: 'Clientes',
      featureKey: 'customers',
      decisions: customerRepairs,
    );
    addCard(
      title: 'Compras',
      featureKey: 'purchases',
      decisions: purchaseRepairs,
    );
    addCard(title: 'Vendas', featureKey: 'sales', decisions: salesRepairs);
    addCard(
      title: 'Eventos financeiros',
      featureKey: 'financial_events',
      decisions: financialRepairs,
    );
    return widgets;
  }
}
