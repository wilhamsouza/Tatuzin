import 'package:flutter/material.dart';

import '../../../../../app/core/formatters/app_formatters.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../../../app/core/widgets/app_summary_block.dart';
import '../../../../../app/core/widgets/app_status_badge.dart';
import '../../../../../app/theme/app_design_tokens.dart';
import '../../../domain/services/product_cost_calculator.dart';

class ProductProfitabilitySection extends StatelessWidget {
  const ProductProfitabilitySection({
    super.key,
    required this.summary,
    required this.salePriceCents,
    required this.manualCostCents,
  });

  final ProductCostSummary summary;
  final int salePriceCents;
  final int manualCostCents;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final tone = _toneForSummary(context, summary);
    final marginPercent = summary.estimatedGrossMarginPercentBasisPoints / 100;

    return AppSectionCard(
      title: 'Lucratividade',
      subtitle:
          'Leitura local do custo variavel da composicao versus o preco de venda atual.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: layout.space3,
            runSpacing: layout.space3,
            children: [
              AppStatusBadge(
                label: _statusLabel(summary),
                tone: switch (tone) {
                  AppStatusTone.success => AppStatusTone.success,
                  AppStatusTone.warning => AppStatusTone.warning,
                  AppStatusTone.danger => AppStatusTone.danger,
                  _ => AppStatusTone.neutral,
                },
              ),
              if (summary.hasRecipe)
                const AppStatusBadge(
                  label: 'Snapshot sera salvo localmente',
                  tone: AppStatusTone.info,
                ),
              if (!summary.hasRecipe)
                const AppStatusBadge(
                  label: 'Custo manual',
                  tone: AppStatusTone.neutral,
                ),
            ],
          ),
          SizedBox(height: layout.space4),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width < 720 ? 2 : 4,
            shrinkWrap: true,
            mainAxisSpacing: layout.space4,
            crossAxisSpacing: layout.space4,
            childAspectRatio: 1.4,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              AppSummaryBlock(
                label: 'Preco de venda',
                value: AppFormatters.currencyFromCents(salePriceCents),
                icon: Icons.sell_outlined,
                palette: context.appColors.brand,
                compact: true,
              ),
              AppSummaryBlock(
                label: summary.hasRecipe ? 'Custo variavel' : 'Custo manual',
                value: AppFormatters.currencyFromCents(
                  summary.hasRecipe
                      ? summary.variableCostSnapshotCents
                      : manualCostCents,
                ),
                icon: Icons.receipt_long_outlined,
                palette: context.appColors.info,
                compact: true,
              ),
              AppSummaryBlock(
                label: 'Lucro bruto',
                value: summary.hasRecipe
                    ? AppFormatters.currencyFromCents(
                        summary.estimatedGrossMarginCents,
                      )
                    : 'Sem calculo',
                icon: Icons.trending_up_rounded,
                palette: switch (tone) {
                  AppStatusTone.success => context.appColors.success,
                  AppStatusTone.warning => context.appColors.warning,
                  AppStatusTone.danger => context.appColors.danger,
                  _ => context.appColors.info,
                },
                compact: true,
              ),
              AppSummaryBlock(
                label: 'Margem estimada',
                value: summary.hasRecipe
                    ? '${marginPercent.toStringAsFixed(2)}%'
                    : 'Sem ficha',
                icon: Icons.percent_rounded,
                palette: switch (tone) {
                  AppStatusTone.success => context.appColors.success,
                  AppStatusTone.warning => context.appColors.warning,
                  AppStatusTone.danger => context.appColors.danger,
                  _ => context.appColors.info,
                },
                compact: true,
              ),
            ],
          ),
          if (!summary.hasRecipe) ...[
            SizedBox(height: layout.space4),
            Text(
              'Sem ficha tecnica, o produto continua usando o custo manual atual e nao entra em leitura automatica de margem.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  AppStatusTone _toneForSummary(
    BuildContext context,
    ProductCostSummary summary,
  ) {
    if (!summary.hasRecipe) {
      return AppStatusTone.neutral;
    }

    final marginBasisPoints = summary.estimatedGrossMarginPercentBasisPoints;
    if (marginBasisPoints >= 2000) {
      return AppStatusTone.success;
    }
    if (marginBasisPoints >= 1000) {
      return AppStatusTone.warning;
    }
    return AppStatusTone.danger;
  }

  String _statusLabel(ProductCostSummary summary) {
    if (!summary.hasRecipe) {
      return 'Sem ficha tecnica';
    }

    final marginBasisPoints = summary.estimatedGrossMarginPercentBasisPoints;
    if (marginBasisPoints >= 2000) {
      return 'Saudavel';
    }
    if (marginBasisPoints >= 1000) {
      return 'Atencao';
    }
    return 'Margem baixa';
  }
}
