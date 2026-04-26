import 'package:flutter/material.dart';

import '../../../../app/core/sync/sync_reconciliation_result.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import 'sync_reconciliation_card.dart';
import 'system_support_widgets.dart';

class SystemReconciliationSection extends StatelessWidget {
  const SystemReconciliationSection({
    required this.overview,
    required this.canRunManualSync,
    required this.isLoading,
    required this.errorMessage,
    required this.supplierReconciliation,
    required this.categoryReconciliation,
    required this.productReconciliation,
    required this.customerReconciliation,
    required this.purchaseReconciliation,
    required this.salesReconciliation,
    required this.financialReconciliation,
    required this.onRunReconciliation,
    required this.onRepairFeature,
    super.key,
  });

  final (int, int, int, int) overview;
  final bool canRunManualSync;
  final bool isLoading;
  final String? errorMessage;
  final SyncReconciliationResult? supplierReconciliation;
  final SyncReconciliationResult? categoryReconciliation;
  final SyncReconciliationResult? productReconciliation;
  final SyncReconciliationResult? customerReconciliation;
  final SyncReconciliationResult? purchaseReconciliation;
  final SyncReconciliationResult? salesReconciliation;
  final SyncReconciliationResult? financialReconciliation;
  final VoidCallback onRunReconciliation;
  final ValueChanged<String> onRepairFeature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      title: 'Reconciliação local vs remoto',
      subtitle:
          'Compara SQLite e espelho remoto sem alterar automaticamente os dados operacionais. Divergencias continuam visiveis para diagnostico e reparo controlado.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SystemModeChip(
                label: '${overview.$1} consistente(s)',
                icon: Icons.cloud_done_outlined,
              ),
              SystemModeChip(
                label: '${overview.$2} pendente(s)',
                icon: Icons.pending_actions_rounded,
              ),
              SystemModeChip(
                label: '${overview.$3} divergencia(s)',
                icon: Icons.compare_arrows_rounded,
              ),
              SystemModeChip(
                label: '${overview.$4} conflito(s)',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isLoading || !canRunManualSync
                    ? null
                    : onRunReconciliation,
                icon: const Icon(Icons.rule_folder_outlined),
                label: Text(
                  isLoading ? 'Reconciliando...' : 'Executar reconciliacao',
                ),
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
          else if (_results.every((result) => result == null))
            Text(
              'Execute a reconciliacao manual para comparar o estado local com o espelho remoto por feature.',
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

  List<SyncReconciliationResult?> get _results => <SyncReconciliationResult?>[
    supplierReconciliation,
    categoryReconciliation,
    productReconciliation,
    customerReconciliation,
    purchaseReconciliation,
    salesReconciliation,
    financialReconciliation,
  ];

  List<Widget> _buildCards() {
    final widgets = <Widget>[];
    void addCard(SyncReconciliationResult? result) {
      if (result == null) {
        return;
      }
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
      }
      widgets.add(
        SyncReconciliationCard(
          result: result,
          canRunReconciliation: canRunManualSync,
          isLoading: isLoading,
          onRepair: () => onRepairFeature(result.featureKey),
        ),
      );
    }

    addCard(supplierReconciliation);
    addCard(categoryReconciliation);
    addCard(productReconciliation);
    addCard(customerReconciliation);
    addCard(purchaseReconciliation);
    addCard(salesReconciliation);
    addCard(financialReconciliation);
    return widgets;
  }
}
