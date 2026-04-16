import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/report_payment_summary.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/report_summary.dart';
import '../providers/report_providers.dart';
import '../widgets/financial_summary_widget.dart';
import '../widgets/product_sales_summary_widget.dart';
import '../widgets/variant_sales_summary_widget.dart';

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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          children: [
            const AppPageHeader(
              title: 'Painel de relatórios',
              subtitle:
                  'Recebimentos, lucro e pendências em leitura executiva rápida.',
              badgeLabel: 'Decisão do dia',
              badgeIcon: Icons.insights_rounded,
            ),
            const SizedBox(height: 14),
            AppSectionCard(
              title: 'Período',
              subtitle: 'Troque o recorte para atualizar o painel.',
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final period in ReportPeriod.values)
                        ChoiceChip(
                          label: Text(_periodLabel(period)),
                          selected: selectedPeriod == period,
                          onSelected: (_) {
                            ref.read(reportPeriodProvider.notifier).state =
                                period;
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Base consultada: ${_formatRange(selectedRange, selectedPeriod)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            summaryAsync.when(
              data: (summary) => _ReportSummaryContent(summary: summary),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: AppStateCard(
                  title: 'Atualizando relatórios',
                  message: 'Consolidando o resumo do período.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar relatórios',
                subtitle: error.toString(),
                child: AppStateCard(
                  title: 'Não foi possível atualizar o painel',
                  message:
                      'Tente novamente para consultar os números do período.',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(reportSummaryProvider),
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

    return '${AppFormatters.shortDate(range.start)} até ${AppFormatters.shortDate(lastIncludedDay)}';
  }

  static String _periodLabel(ReportPeriod period) {
    switch (period) {
      case ReportPeriod.daily:
        return 'Diário';
      case ReportPeriod.weekly:
        return 'Semanal';
      case ReportPeriod.monthly:
        return 'Mensal';
      case ReportPeriod.yearly:
        return 'Anual';
    }
  }
}

class _ReportSummaryContent extends StatelessWidget {
  const _ReportSummaryContent({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.18,
          children: [
            AppMetricCard(
              label: 'Vendas no período',
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
              caption: 'Entradas líquidas',
              icon: Icons.account_balance_wallet_rounded,
              accentColor: AppTheme.secondary,
            ),
            AppMetricCard(
              label: 'Lucro realizado',
              value: AppFormatters.currencyFromCents(
                summary.realizedProfitCents,
              ),
              caption: 'Lucro bruto no período',
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
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            AppMetricCard(
              label: 'Haver gerado',
              value: AppFormatters.currencyFromCents(
                summary.totalCreditGeneratedCents,
              ),
              caption: 'Crédito emitido no período',
              icon: Icons.add_card_rounded,
            ),
            AppMetricCard(
              label: 'Haver utilizado',
              value: AppFormatters.currencyFromCents(
                summary.totalCreditUsedCents,
              ),
              caption: 'Abatido em vendas',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          title: 'Recebimentos por forma',
          subtitle: 'O que entrou no caixa no período.',
          padding: const EdgeInsets.all(14),
          child: summary.paymentSummaries.isEmpty
              ? const Text(
                  'Nenhum recebimento com forma de pagamento registrada neste período.',
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
                        const Divider(height: 18),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          title: 'Visão operacional',
          subtitle: 'Indicadores de volume, pendência e passivo de haver.',
          padding: const EdgeInsets.all(14),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              _OperationalTile(
                label: 'Vendas ativas',
                value: '${summary.salesCount}',
                caption: 'Operações concluídas',
              ),
              _OperationalTile(
                label: 'Cancelamentos',
                value: '${summary.cancelledSalesCount}',
                caption: AppFormatters.currencyFromCents(
                  summary.cancelledSalesCents,
                ),
              ),
              _OperationalTile(
                label: 'Notas pendentes',
                value: '${summary.pendingFiadoCount}',
                caption: AppFormatters.currencyFromCents(
                  summary.pendingFiadoCents,
                ),
                emphasize: true,
              ),
              _OperationalTile(
                label: 'Compras pendentes',
                value: AppFormatters.currencyFromCents(
                  summary.totalPurchasePendingCents,
                ),
                caption: 'Acompanhar pagamento',
              ),
              _OperationalTile(
                label: 'Passivo de haver',
                value: AppFormatters.currencyFromCents(
                  summary.totalOutstandingCreditCents,
                ),
                caption: 'Saldo aberto da loja',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          title: 'Clientes com mais haver',
          subtitle: 'Quem concentra mais saldo positivo na loja.',
          padding: const EdgeInsets.all(14),
          child: summary.topCreditCustomers.isEmpty
              ? const Text('Nenhum cliente com haver em aberto neste momento.')
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < summary.topCreditCustomers.length;
                      index++
                    ) ...[
                      _TopCreditCustomerTile(
                        name: summary.topCreditCustomers[index].customerName,
                        balanceCents:
                            summary.topCreditCustomers[index].balanceCents,
                      ),
                      if (index < summary.topCreditCustomers.length - 1)
                        const Divider(height: 18),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),
        FinancialSummaryWidget(summary: summary),
        const SizedBox(height: 14),
        ProductSalesSummaryWidget(soldProducts: summary.soldProducts),
        const SizedBox(height: 14),
        VariantSalesSummaryWidget(variants: summary.variantSummaries),
      ],
    );
  }
}

class _TopCreditCustomerTile extends StatelessWidget {
  const _TopCreditCustomerTile({
    required this.name,
    required this.balanceCents,
  });

  final String name;
  final int balanceCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(balanceCents),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _OperationalTile extends StatelessWidget {
  const _OperationalTile({
    required this.label,
    required this.value,
    required this.caption,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String caption;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasize
            ? colorScheme.primaryContainer.withValues(alpha: 0.52)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: emphasize ? colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
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
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            summary.paymentMethod == PaymentMethod.cash
                ? Icons.payments_outlined
                : summary.paymentMethod == PaymentMethod.pix
                ? Icons.pix
                : Icons.credit_card_rounded,
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
                summary.paymentMethod.label,
                style: theme.textTheme.titleSmall?.copyWith(
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
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
