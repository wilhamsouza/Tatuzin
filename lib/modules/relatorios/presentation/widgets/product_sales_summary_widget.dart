import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../domain/entities/report_sold_product_summary.dart';

class ProductSalesSummaryWidget extends StatelessWidget {
  const ProductSalesSummaryWidget({super.key, required this.soldProducts});

  final List<ReportSoldProductSummary> soldProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Produtos vendidos',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (soldProducts.isEmpty)
          Text(
            'Nenhum produto vendido no periodo',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < soldProducts.length; index++) ...[
                _ProductSalesRow(summary: soldProducts[index]),
                if (index < soldProducts.length - 1) const Divider(height: 20),
              ],
            ],
          ),
      ],
    );
  }
}

class _ProductSalesRow extends StatelessWidget {
  const _ProductSalesRow({required this.summary});

  final ReportSoldProductSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.productName,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _ProductMetricChip(
              label: 'Qtd',
              value:
                  '${AppFormatters.quantityFromMil(summary.quantityMil)} ${summary.unitMeasure}',
            ),
            _ProductMetricChip(
              label: 'Venda',
              value: AppFormatters.currencyFromCents(summary.soldAmountCents),
            ),
            _ProductMetricChip(
              label: 'Custo',
              value: AppFormatters.currencyFromCents(summary.totalCostCents),
            ),
          ],
        ),
        if (summary.totalCostCents > summary.soldAmountCents) ...[
          const SizedBox(height: 6),
          Text(
            'Atencao: custo acima do valor vendido neste periodo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProductMetricChip extends StatelessWidget {
  const _ProductMetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
