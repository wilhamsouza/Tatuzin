import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/report_summary.dart';

class FinancialSummaryWidget extends StatelessWidget {
  const FinancialSummaryWidget({super.key, required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Detalhamento financeiro',
      subtitle: 'Quebra de recebimentos, compras e custo do período.',
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _FinanceLine(
            label: 'Vendas à vista recebidas',
            value: AppFormatters.currencyFromCents(
              summary.cashSalesReceivedCents,
            ),
          ),
          const Divider(height: 18),
          _FinanceLine(
            label: 'Fiado recebido',
            value: AppFormatters.currencyFromCents(summary.fiadoReceiptsCents),
          ),
          const Divider(height: 18),
          _FinanceLine(
            label: 'Compras registradas',
            value: AppFormatters.currencyFromCents(summary.totalPurchasedCents),
          ),
          const Divider(height: 18),
          _FinanceLine(
            label: 'Pagamentos de compras',
            value: AppFormatters.currencyFromCents(
              summary.totalPurchasePaymentsCents,
            ),
          ),
          const Divider(height: 18),
          _FinanceLine(
            label: 'Custo dos produtos vendidos',
            value: AppFormatters.currencyFromCents(
              summary.costOfGoodsSoldCents,
            ),
          ),
          const Divider(height: 18),
          _FinanceLine(
            label: 'Compras pendentes',
            value: AppFormatters.currencyFromCents(
              summary.totalPurchasePendingCents,
            ),
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _FinanceLine extends StatelessWidget {
  const _FinanceLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: emphasize
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                )
              : theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
        ),
      ],
    );
  }
}
