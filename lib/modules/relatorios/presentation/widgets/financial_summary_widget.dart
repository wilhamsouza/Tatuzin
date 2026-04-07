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
      title: 'Resumo financeiro',
      subtitle: 'Entradas e impacto comercial do periodo selecionado.',
      child: Column(
        children: [
          _FinanceLine(
            label: 'Recebimentos de vendas a vista',
            value: AppFormatters.currencyFromCents(
              summary.cashSalesReceivedCents,
            ),
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Recebimentos de fiado',
            value: AppFormatters.currencyFromCents(summary.fiadoReceiptsCents),
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Compras registradas',
            value: AppFormatters.currencyFromCents(summary.totalPurchasedCents),
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Pagamentos de compras',
            value: AppFormatters.currencyFromCents(
              summary.totalPurchasePaymentsCents,
            ),
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Compras pendentes',
            value: AppFormatters.currencyFromCents(
              summary.totalPurchasePendingCents,
            ),
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Total recebido liquido',
            value: AppFormatters.currencyFromCents(summary.totalReceivedCents),
            emphasize: true,
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Custo dos produtos vendidos',
            value: AppFormatters.currencyFromCents(
              summary.costOfGoodsSoldCents,
            ),
          ),
          const Divider(height: 24),
          _FinanceLine(
            label: 'Lucro bruto realizado',
            value: AppFormatters.currencyFromCents(summary.realizedProfitCents),
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: emphasize
              ? theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                )
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
        ),
      ],
    );
  }
}
