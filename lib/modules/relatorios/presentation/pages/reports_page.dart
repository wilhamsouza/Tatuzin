import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/report_payment_summary.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/report_summary.dart';
import '../providers/report_providers.dart';
import '../widgets/financial_summary_widget.dart';
import '../widgets/product_sales_summary_widget.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPeriod = ref.watch(reportPeriodProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedRange = selectedPeriod.resolveRange(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportSummaryProvider);
          await ref.read(reportSummaryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const AppPageHeader(
              title: 'Relat\u00f3rios',
              subtitle:
                  'Acompanhe vendas, recebimentos, compras e pend\u00eancias com base nos dados locais reais.',
              badgeLabel: 'Vis\u00e3o gerencial',
              badgeIcon: Icons.insights_rounded,
              emphasized: true,
            ),
            const SizedBox(height: 18),
            AppSectionCard(
              title: 'Per\u00edodo',
              subtitle: 'Selecione o recorte para atualizar os indicadores.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final period in ReportPeriod.values)
                        ChoiceChip(
                          label: Text(period.label),
                          selected: selectedPeriod == period,
                          onSelected: (_) {
                            ref.read(reportPeriodProvider.notifier).state =
                                period;
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Base consultada: ${_formatRange(selectedRange, selectedPeriod)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            summaryAsync.when(
              data: (summary) => _ReportSummaryContent(summary: summary),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar relat\u00f3rios',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(reportSummaryProvider),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatRange(ReportDateRange range, ReportPeriod period) {
    final lastIncludedDay = range.endExclusive.subtract(
      const Duration(days: 1),
    );

    if (period == ReportPeriod.daily) {
      return AppFormatters.shortDate(range.start);
    }

    return '${AppFormatters.shortDate(range.start)} at\u00e9 ${AppFormatters.shortDate(lastIncludedDay)}';
  }
}

class _ReportSummaryContent extends StatelessWidget {
  const _ReportSummaryContent({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.92,
          children: [
            AppMetricCard(
              label: 'Vendas no per\u00edodo',
              value: AppFormatters.currencyFromCents(summary.totalSalesCents),
              caption: '${summary.salesCount} venda(s) ativas',
              icon: Icons.point_of_sale_rounded,
              accentColor: AppTheme.primary,
            ),
            AppMetricCard(
              label: 'Total recebido',
              value: AppFormatters.currencyFromCents(
                summary.totalReceivedCents,
              ),
              caption: 'J\u00e1 considera estornos de cancelamento',
              icon: Icons.account_balance_wallet_rounded,
              accentColor: AppTheme.secondary,
            ),
            AppMetricCard(
              label: 'Lucro realizado',
              value: AppFormatters.currencyFromCents(
                summary.realizedProfitCents,
              ),
              caption: 'Lucro bruto reconhecido no per\u00edodo',
              icon: Icons.trending_up_rounded,
              accentColor: AppTheme.success,
            ),
            AppMetricCard(
              label: 'Fiado pendente',
              value: AppFormatters.currencyFromCents(summary.pendingFiadoCents),
              caption: '${summary.pendingFiadoCount} nota(s) em aberto',
              icon: Icons.receipt_long_rounded,
              accentColor: AppTheme.warning,
            ),
          ],
        ),
        const SizedBox(height: 18),
        FinancialSummaryWidget(summary: summary),
        const SizedBox(height: 18),
        AppSectionCard(
          title: 'Resumo operacional',
          subtitle: 'Volume, pend\u00eancias e cancelamentos do ERP.',
          child: Column(
            children: [
              _SummaryLine(
                label: 'Quantidade de vendas',
                value: '${summary.salesCount} venda(s)',
              ),
              const Divider(height: 24),
              _SummaryLine(
                label: 'Notas pendentes',
                value:
                    '${summary.pendingFiadoCount} nota(s) - ${AppFormatters.currencyFromCents(summary.pendingFiadoCents)}',
              ),
              const Divider(height: 24),
              _SummaryLine(
                label: 'Cancelamentos no per\u00edodo',
                value:
                    '${summary.cancelledSalesCount} venda(s) - ${AppFormatters.currencyFromCents(summary.cancelledSalesCents)}',
              ),
              const Divider(height: 24),
              _SummaryLine(
                label: 'Compras registradas',
                value: AppFormatters.currencyFromCents(
                  summary.totalPurchasedCents,
                ),
              ),
              const Divider(height: 24),
              _SummaryLine(
                label: 'Compras pendentes',
                value: AppFormatters.currencyFromCents(
                  summary.totalPurchasePendingCents,
                ),
              ),
              const Divider(height: 24),
              ProductSalesSummaryWidget(soldProducts: summary.soldProducts),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AppSectionCard(
          title: 'Formas de pagamento',
          subtitle:
              'Entradas recebidas no per\u00edodo por forma de pagamento.',
          child: summary.paymentSummaries.isEmpty
              ? const Text(
                  'Nenhum recebimento com forma de pagamento registrada neste per\u00edodo.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < summary.paymentSummaries.length;
                      index++
                    ) ...[
                      _PaymentSummaryTile(
                        summary: summary.paymentSummaries[index],
                      ),
                      if (index < summary.paymentSummaries.length - 1)
                        const Divider(height: 24),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PaymentSummaryTile extends StatelessWidget {
  const _PaymentSummaryTile({required this.summary});

  final ReportPaymentSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            summary.paymentMethod == PaymentMethod.cash
                ? Icons.payments_outlined
                : summary.paymentMethod == PaymentMethod.pix
                ? Icons.pix
                : Icons.credit_card_rounded,
            size: 20,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.paymentMethod.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${summary.operationsCount} recebimento(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(summary.receivedCents),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
