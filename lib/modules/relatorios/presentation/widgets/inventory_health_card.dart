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
    this.onZeroedTap,
    this.onBelowMinimumTap,
    this.onDivergenceTap,
    this.onItemTap,
  });

  final ReportInventoryHealthSummary summary;
  final List<InventoryItem>? visibleCriticalItems;
  final String subtitle;
  final VoidCallback? onZeroedTap;
  final VoidCallback? onBelowMinimumTap;
  final VoidCallback? onDivergenceTap;
  final ValueChanged<InventoryItem>? onItemTap;

  @override
  Widget build(BuildContext context) {
    final criticalItems = visibleCriticalItems ?? summary.criticalItems;

    return AppSectionCard(
      title: 'Saude do estoque',
      subtitle: '$subtitle Toque em um item para abrir o recorte.',
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
                        onTap: onZeroedTap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMiniStat(
                        label: 'Abaixo do minimo',
                        value: '${summary.belowMinimumItemsCount}',
                        onTap: onBelowMinimumTap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMiniStat(
                        label: 'Divergencia',
                        value: '${summary.divergenceItemsCount}',
                        onTap: onDivergenceTap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < criticalItems.length; index++) ...[
                  Tooltip(
                    message: onItemTap == null
                        ? 'Item critico'
                        : 'Toque para abrir este item no relatorio',
                    child: ListTile(
                      onTap: onItemTap == null
                          ? null
                          : () => onItemTap!(criticalItems[index]),
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
  const _InventoryMiniStat({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
