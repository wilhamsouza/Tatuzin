import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../domain/entities/operational_order_detail.dart';
import '../support/order_ui_support.dart';

class OperationalOrderItemCard extends StatelessWidget {
  const OperationalOrderItemCard({
    super.key,
    required this.itemDetail,
    this.showPrices = true,
    this.kitchenMode = false,
    this.onEdit,
    this.onRemove,
  });

  final OperationalOrderItemDetail itemDetail;
  final bool showPrices;
  final bool kitchenMode;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final item = itemDetail.item;
    final quantityLabel = AppFormatters.quantityFromMil(item.quantityMil);
    final variantLabel = operationalOrderVariantSnapshotLabel(
      sku: item.variantSkuSnapshot,
      color: item.variantColorSnapshot,
      size: item.variantSizeSnapshot,
    );

    return AppCard(
      padding: const EdgeInsets.all(16),
      color: kitchenMode ? colorScheme.surfaceContainerLow : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: kitchenMode ? 12 : 10,
                  vertical: kitchenMode ? 10 : 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${quantityLabel}x',
                  style:
                      (kitchenMode
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onPrimaryContainer,
                          ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productNameSnapshot,
                      maxLines: kitchenMode ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (kitchenMode
                                  ? theme.textTheme.titleLarge
                                  : theme.textTheme.titleMedium)
                              ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (variantLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        variantLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: kitchenMode ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      showPrices
                          ? '$quantityLabel x ${AppFormatters.currencyFromCents(item.unitPriceCents)}'
                          : 'Quantidade: $quantityLabel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: kitchenMode ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (showPrices)
                Text(
                  AppFormatters.currencyFromCents(itemDetail.totalCents),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          if (item.notes?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            _InfoBlock(
              label: 'Observacao',
              value: item.notes!.trim(),
              emphasize: kitchenMode,
            ),
          ],
          if (itemDetail.modifiers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adicionais e remocoes',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final modifier in itemDetail.modifiers) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(Icons.circle, size: 7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [
                              if (modifier.groupNameSnapshot
                                      ?.trim()
                                      .isNotEmpty ??
                                  false)
                                '${modifier.groupNameSnapshot}:',
                              operationalOrderModifierLabel(
                                modifier.optionNameSnapshot,
                                modifier.adjustmentTypeSnapshot,
                              ),
                              if (modifier.quantity > 1)
                                'x${modifier.quantity}',
                            ].join(' '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: kitchenMode ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                        if (showPrices && modifier.priceDeltaCents != 0)
                          Text(
                            AppFormatters.currencyFromCents(
                              modifier.priceDeltaCents,
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    if (modifier != itemDetail.modifiers.last)
                      const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ],
          if (onEdit != null || onRemove != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onEdit != null)
                  FilledButton.tonalIcon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Editar item'),
                  ),
                if (onRemove != null)
                  OutlinedButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remover'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.value,
    required this.emphasize,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasize
            ? colorScheme.errorContainer.withValues(alpha: 0.65)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: emphasize ? colorScheme.onErrorContainer : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? colorScheme.onErrorContainer : null,
            ),
          ),
        ],
      ),
    );
  }
}
