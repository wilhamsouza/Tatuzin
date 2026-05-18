import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/report_sold_product_summary.dart';
import 'report_empty_state.dart';

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
    final visibleProducts = _showAll
        ? widget.soldProducts
        : widget.soldProducts.take(5).toList(growable: false);
    final leaderAmount = widget.soldProducts.fold<int>(
      0,
      (leader, product) => math.max(leader, product.soldAmountCents),
    );

    return AppSectionCard(
      title: 'Top produtos',
      subtitle:
          'Ranking por valor vendido no período. Toque em um item para aprofundar.',
      padding: const EdgeInsets.all(14),
      child: widget.soldProducts.isEmpty
          ? const ReportEmptyState(
              title: 'Ainda não há vendas neste período.',
              message: 'Tente alterar o período ou limpar os filtros.',
            )
          : Column(
              children: [
                for (
                  var index = 0;
                  index < visibleProducts.length;
                  index++
                ) ...[
                  _ProductSalesRow(
                    rank: index + 1,
                    leaderAmountCents: leaderAmount,
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
  const _ProductSalesRow({
    required this.rank,
    required this.leaderAmountCents,
    required this.summary,
    this.onTap,
  });

  final int rank;
  final int leaderAmountCents;
  final ReportSoldProductSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appColors;
    final costHigherThanSales =
        summary.totalCostCents > summary.soldAmountCents;
    final progress = leaderAmountCents <= 0
        ? 0.0
        : (summary.soldAmountCents / leaderAmountCents).clamp(0.0, 1.0);

    return Tooltip(
      message: onTap == null
          ? 'Produto em destaque'
          : 'Toque para abrir este produto no relatório de vendas',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.appLayout.radiusMd),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 340;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RankBadge(rank: rank),
                      const SizedBox(width: 10),
                      Expanded(child: _ProductText(summary: summary)),
                      if (!compact) ...[
                        const SizedBox(width: 10),
                        _ProductAmount(summary: summary),
                      ],
                    ],
                  ),
                  if (compact) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: _ProductAmount(summary: summary, compact: true),
                    ),
                  ],
                  if (leaderAmountCents > 0) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.appLayout.radiusPill,
                        ),
                        child: LinearProgressIndicator(
                          key: ValueKey('product_ranking_progress_$rank'),
                          minHeight: 5,
                          value: progress,
                          backgroundColor: tokens.disabled.surface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            tokens.sales.base,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (costHigherThanSales) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: Text(
                        'Custo acima do valor vendido no período.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.sales.surface,
        borderRadius: BorderRadius.circular(context.appLayout.radiusSm),
        border: Border.all(color: tokens.sales.border),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tokens.sales.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProductText extends StatelessWidget {
  const _ProductText({required this.summary});

  final ReportSoldProductSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = summary.quantityMil > 0
        ? '${AppFormatters.quantityFromMil(summary.quantityMil)} ${summary.unitMeasure.trim()} vendidos'
              .trim()
        : 'Quantidade não informada';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.productName.trim().isEmpty
              ? 'Produto sem nome'
              : summary.productName.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          quantity,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ProductAmount extends StatelessWidget {
  const _ProductAmount({required this.summary, this.compact = false});

  final ReportSoldProductSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: compact ? Alignment.centerLeft : Alignment.centerRight,
          child: Text(
            AppFormatters.currencyFromCents(summary.soldAmountCents),
            maxLines: 1,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Valor vendido',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (compact) {
      return content;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 118),
      child: content,
    );
  }
}
