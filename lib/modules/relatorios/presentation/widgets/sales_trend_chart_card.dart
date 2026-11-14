import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../domain/entities/report_sales_trend_point.dart';
import 'report_empty_state.dart';

class SalesTrendChartCard extends StatelessWidget {
  const SalesTrendChartCard({
    super.key,
    required this.points,
    this.title = 'Tendência de vendas',
    this.subtitle = 'Leitura rápida do comportamento do período.',
    this.emptyMessage =
        'Tente alterar o período ou limpar os filtros para comparar outra janela.',
  });

  final List<ReportSalesTrendPoint> points;
  final String title;
  final String subtitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return AppSectionCard(
        title: title,
        subtitle: subtitle,
        padding: const EdgeInsets.all(14),
        child: ReportEmptyState(
          title: 'Ainda não há vendas neste período.',
          message: emptyMessage,
        ),
      );
    }

    final maxValue = points.fold<int>(
      0,
      (current, point) => math.max(current, point.netSalesCents),
    );
    final palette = context.appColors.sales;

    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            key: const ValueKey('sales_trend_chart_area'),
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Semantics(
                        label:
                            '${point.label}: ${point.salesCount} venda(s), ${AppFormatters.currencyFromCents(point.netSalesCents)}',
                        child: Tooltip(
                          message:
                              '${point.label}: ${AppFormatters.currencyFromCents(point.netSalesCents)}',
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: maxValue == 0
                                  ? 0
                                  : math.max(
                                      0,
                                      math.min(
                                        1.0,
                                        point.netSalesCents / maxValue,
                                      ),
                                    ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.base,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const SizedBox(width: double.infinity),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'De ${points.first.label}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                'Até ${points.last.label}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TrendSummary(points: points, maxValue: maxValue),
        ],
      ),
    );
  }
}

class _TrendSummary extends StatelessWidget {
  const _TrendSummary({required this.points, required this.maxValue});

  final List<ReportSalesTrendPoint> points;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSales = points.fold<int>(
      0,
      (total, point) => total + point.salesCount,
    );
    final peak = points.reduce(
      (current, next) =>
          next.netSalesCents > current.netSalesCents ? next : current,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          'Pico ${peak.label}: ${AppFormatters.currencyFromCents(maxValue)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '$totalSales venda(s)',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
