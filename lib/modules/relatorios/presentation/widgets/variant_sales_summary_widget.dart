import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/report_variant_summary.dart';

class VariantSalesSummaryWidget extends StatefulWidget {
  const VariantSalesSummaryWidget({super.key, required this.variants});

  final List<ReportVariantSummary> variants;

  @override
  State<VariantSalesSummaryWidget> createState() =>
      _VariantSalesSummaryWidgetState();
}

class _VariantSalesSummaryWidgetState extends State<VariantSalesSummaryWidget> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleVariants = _showAll
        ? widget.variants
        : widget.variants.take(8).toList(growable: false);

    return AppSectionCard(
      title: 'Giro por variante',
      subtitle: 'SKU, cor, tamanho, compra e venda no periodo.',
      padding: const EdgeInsets.all(14),
      child: widget.variants.isEmpty
          ? Text(
              'Nenhuma variante com movimentacao relevante neste periodo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (
                  var index = 0;
                  index < visibleVariants.length;
                  index++
                ) ...[
                  _VariantSalesRow(summary: visibleVariants[index]),
                  if (index < visibleVariants.length - 1)
                    const Divider(height: 18),
                ],
                if (widget.variants.length > 8) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      icon: Icon(
                        _showAll
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                      ),
                      label: Text(_showAll ? 'Mostrar menos' : 'Mostrar mais'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _VariantSalesRow extends StatelessWidget {
  const _VariantSalesRow({required this.summary});

  final ReportVariantSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.straighten_rounded,
            size: 18,
            color: colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.modelName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                summary.variantSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if ((summary.variantSku ?? '').trim().isNotEmpty)
                    _VariantMetricChip(
                      label: 'SKU ${summary.variantSku!.trim()}',
                    ),
                  _VariantMetricChip(
                    label:
                        'Estoque ${AppFormatters.quantityFromMil(summary.currentStockMil)}',
                  ),
                  _VariantMetricChip(
                    label:
                        'Vendidas ${AppFormatters.quantityFromMil(summary.soldQuantityMil)}',
                    emphasize: summary.hasSales,
                  ),
                  _VariantMetricChip(
                    label:
                        'Compradas ${AppFormatters.quantityFromMil(summary.purchasedQuantityMil)}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppFormatters.currencyFromCents(summary.grossRevenueCents),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Receita',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VariantMetricChip extends StatelessWidget {
  const _VariantMetricChip({required this.label, this.emphasize = false});

  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: emphasize
            ? colorScheme.primaryContainer.withValues(alpha: 0.58)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          color: emphasize ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
    );
  }
}
