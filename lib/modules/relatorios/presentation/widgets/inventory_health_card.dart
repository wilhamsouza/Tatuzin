import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../estoque/domain/entities/inventory_item.dart';
import '../../domain/entities/report_inventory_health_summary.dart';
import 'report_empty_state.dart';

class InventoryHealthCard extends StatelessWidget {
  const InventoryHealthCard({
    super.key,
    required this.summary,
    this.visibleCriticalItems,
    this.subtitle = 'Itens que pedem atencao agora.',
  });

  final ReportInventoryHealthSummary summary;
  final List<InventoryItem>? visibleCriticalItems;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final criticalItems = visibleCriticalItems ?? summary.criticalItems;

    return AppSectionCard(
      title: 'Saude do estoque',
      subtitle: subtitle,
      padding: const EdgeInsets.all(14),
      child: criticalItems.isEmpty
          ? const ReportEmptyState(
              title: 'Sem alertas criticos',
              message: 'Os itens zerados e abaixo do minimo vao aparecer aqui.',
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InventoryMiniStat(
                        label: 'Zerados',
                        value: '${summary.zeroedItemsCount}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMiniStat(
                        label: 'Abaixo do minimo',
                        value: '${summary.belowMinimumItemsCount}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMiniStat(
                        label: 'Divergencia',
                        value: '${summary.divergenceItemsCount}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < criticalItems.length; index++) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(criticalItems[index].displayName),
                    subtitle: Text(
                      'Saldo ${AppFormatters.quantityFromMil(criticalItems[index].currentStockMil)} ${criticalItems[index].unitMeasure}',
                    ),
                    trailing: Text(
                      criticalItems[index].isZeroed
                          ? 'Zerado'
                          : 'Abaixo do minimo',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (index < criticalItems.length - 1)
                    const Divider(height: 16),
                ],
              ],
            ),
    );
  }
}

class _InventoryMiniStat extends StatelessWidget {
  const _InventoryMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
