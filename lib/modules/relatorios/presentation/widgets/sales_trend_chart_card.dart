import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/report_sales_trend_point.dart';
import 'report_empty_state.dart';

class SalesTrendChartCard extends StatelessWidget {
  const SalesTrendChartCard({
    super.key,
    required this.points,
    this.title = 'Tendencia de vendas',
    this.subtitle = 'Leitura rapida do comportamento do periodo.',
  });

  final List<ReportSalesTrendPoint> points;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return AppSectionCard(
        title: title,
        subtitle: subtitle,
        padding: const EdgeInsets.all(14),
        child: const ReportEmptyState(
          title: 'Sem movimento no periodo',
          message:
              'As vendas vao aparecer aqui quando houver registro no recorte selecionado.',
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
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 220,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final point in points)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        AppFormatters.currencyFromCents(point.netSalesCents),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            height: maxValue == 0
                                ? 8
                                : (point.netSalesCents / maxValue) * 132,
                            decoration: BoxDecoration(
                              color: palette.base,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        point.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${point.salesCount} venda(s)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
