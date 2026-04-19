import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/report_sold_product_summary.dart';

class ProductSalesSummaryWidget extends StatefulWidget {
  const ProductSalesSummaryWidget({
    super.key,
    required this.soldProducts,
    this.onProductTap,
  });

  final List<ReportSoldProductSummary> soldProducts;
  final ValueChanged<ReportSoldProductSummary>? onProductTap;

  @override
  State<ProductSalesSummaryWidget> createState() =>
      _ProductSalesSummaryWidgetState();
}

class _ProductSalesSummaryWidgetState extends State<ProductSalesSummaryWidget> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleProducts = _showAll
        ? widget.soldProducts
        : widget.soldProducts.take(5).toList(growable: false);

    return AppSectionCard(
      title: 'Produtos mais vendidos',
      subtitle:
          'Itens com maior giro no periodo selecionado. Toque em um item para abrir o detalhe.',
      padding: const EdgeInsets.all(14),
      child: widget.soldProducts.isEmpty
          ? Text(
              'Nenhum produto vendido no periodo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (
                  var index = 0;
                  index < visibleProducts.length;
                  index++
                ) ...[
                  _ProductSalesRow(
                    summary: visibleProducts[index],
                    onTap: widget.onProductTap == null
                        ? null
                        : () => widget.onProductTap!(visibleProducts[index]),
                  ),
                  if (index < visibleProducts.length - 1)
                    const Divider(height: 18),
                ],
                if (widget.soldProducts.length > 5) ...[
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

class _ProductSalesRow extends StatelessWidget {
  const _ProductSalesRow({required this.summary, this.onTap});

  final ReportSoldProductSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final costHigherThanSales =
        summary.totalCostCents > summary.soldAmountCents;

    return Tooltip(
      message: onTap == null
          ? 'Produto em destaque'
          : 'Toque para abrir este produto no relatorio de vendas',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${AppFormatters.quantityFromMil(summary.quantityMil)} ${summary.unitMeasure} | Venda ${AppFormatters.currencyFromCents(summary.soldAmountCents)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (costHigherThanSales) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Custo acima do valor vendido no periodo.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.currencyFromCents(summary.totalCostCents),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    onTap == null ? 'Custo' : 'Abrir detalhe',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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
