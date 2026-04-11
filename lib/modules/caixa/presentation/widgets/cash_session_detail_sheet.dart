import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/cash_enums.dart';
import '../../domain/entities/cash_session.dart';
import '../../domain/entities/cash_session_detail.dart';
import '../providers/cash_providers.dart';

class CashSessionDetailSheet extends ConsumerWidget {
  const CashSessionDetailSheet({super.key, required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(cashSessionDetailProvider(session.id));
    final colorScheme = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 0.94,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 52,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(
              child: detailAsync.when(
                data: (detail) => _CashSessionDetailBody(detail: detail),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: AppStateCard(
                    title: 'Carregando sessão',
                    message: 'Montando os detalhes do caixa.',
                    tone: AppStateTone.loading,
                    compact: true,
                  ),
                ),
                error: (error, _) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: AppStateCard(
                      title: 'Falha ao carregar a sessão',
                      message:
                          'Feche e abra novamente para consultar os detalhes.',
                      tone: AppStateTone.error,
                      compact: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashSessionDetailBody extends StatelessWidget {
  const _CashSessionDetailBody({required this.detail});

  final CashSessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final session = detail.session;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sessionTone = session.isOpen
        ? AppStatusTone.success
        : AppStatusTone.neutral;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.isOpen ? 'Sessão em andamento' : 'Sessão encerrada',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.isOpen
                        ? 'Histórico atual da sessão aberta no caixa.'
                        : 'Resumo completo do que compôs o fechamento desta sessão.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppStatusBadge(
              label: session.status.label,
              tone: sessionTone,
              icon: session.isOpen ? Icons.lock_open : Icons.lock_outline,
            ),
          ],
        ),
        const SizedBox(height: 18),
        AppSectionCard(
          title: 'Cabeçalho da sessão',
          subtitle: 'Situação operacional, horários e saldo consolidado.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _InfoLine(
                      label: 'Abertura',
                      value: AppFormatters.shortDateTime(session.openedAt),
                    ),
                  ),
                  Expanded(
                    child: _InfoLine(
                      label: session.closedAt == null
                          ? 'Última leitura'
                          : 'Fechamento',
                      value: AppFormatters.shortDateTime(detail.periodEnd),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _InfoLine(
                      label: 'Saldo final calculado',
                      value: AppFormatters.currencyFromCents(
                        session.finalBalanceCents,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _InfoLine(
                      label: 'Falta para zerar',
                      value: AppFormatters.currencyFromCents(
                        detail.amountToZeroCents,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ZeroingStatusCard(detail: detail),
              if (session.notes?.isNotEmpty ?? false) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Observações: ${session.notes}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Resumo financeiro',
          subtitle:
              'Totais operacionais consolidados sem alterar a lógica atual.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryMetric(
                label: 'Valor inicial',
                value: AppFormatters.currencyFromCents(
                  session.initialFloatCents,
                ),
              ),
              _SummaryMetric(
                label: 'Total vendido',
                value: AppFormatters.currencyFromCents(detail.totalSoldCents),
              ),
              _SummaryMetric(
                label: 'Recebido à vista',
                value: AppFormatters.currencyFromCents(
                  detail.totalCashSalesReceivedCents,
                ),
              ),
              _SummaryMetric(
                label: 'Recebido de fiado',
                value: AppFormatters.currencyFromCents(
                  detail.totalFiadoReceiptsCents,
                ),
              ),
              _SummaryMetric(
                label: 'Entradas totais',
                value: AppFormatters.currencyFromCents(
                  detail.totalEntriesCents,
                ),
              ),
              _SummaryMetric(
                label: 'Saídas totais',
                value: AppFormatters.currencyFromCents(
                  detail.totalOutflowsCents,
                ),
              ),
              _SummaryMetric(
                label: 'Entradas manuais',
                value: AppFormatters.currencyFromCents(
                  detail.totalManualEntriesCents,
                ),
              ),
              _SummaryMetric(
                label: 'Retiradas manuais',
                value: AppFormatters.currencyFromCents(
                  detail.totalManualWithdrawalsCents,
                ),
              ),
              _SummaryMetric(
                label: 'Saldo final',
                value: AppFormatters.currencyFromCents(
                  session.finalBalanceCents,
                ),
              ),
              _SummaryMetric(
                label: 'Valor contado',
                value: detail.countedAmountCents == null
                    ? 'Não registrado'
                    : AppFormatters.currencyFromCents(
                        detail.countedAmountCents!,
                      ),
              ),
              _SummaryMetric(
                label: 'Diferença',
                value: detail.differenceCents == null
                    ? 'Não disponível'
                    : AppFormatters.currencyFromCents(detail.differenceCents!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Movimentações',
          subtitle: 'Entradas, saídas e referências registradas nesta sessão.',
          child: detail.movements.isEmpty
              ? const AppStateCard(
                  title: 'Nenhuma movimentação registrada',
                  message:
                      'Esta sessão não recebeu entradas ou saídas manuais.',
                  compact: true,
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < detail.movements.length;
                      index++
                    )
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == detail.movements.length - 1 ? 0 : 12,
                        ),
                        child: _MovementDetailTile(
                          detail: detail.movements[index],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'O que foi vendido',
          subtitle:
              'Vendas registradas dentro da janela desta sessão, com resumo suficiente para auditoria operacional.',
          child: detail.sales.isEmpty
              ? const AppStateCard(
                  title: 'Nenhuma venda nesta sessão',
                  message: 'Não houve vendas registradas na janela consultada.',
                  compact: true,
                )
              : Column(
                  children: [
                    for (var index = 0; index < detail.sales.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == detail.sales.length - 1 ? 0 : 12,
                        ),
                        child: _SaleSummaryTile(summary: detail.sales[index]),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.of(context).size.width - 72) / 2;
    final metricWidth = width.clamp(140.0, 240.0).toDouble();

    return Container(
      width: metricWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ZeroingStatusCard extends StatelessWidget {
  const _ZeroingStatusCard({required this.detail});

  final CashSessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (
      title,
      description,
      toneColor,
    ) = switch (detail.session.finalBalanceCents) {
      > 0 => (
        'Caixa acima de zero',
        'Falta retirar ${AppFormatters.currencyFromCents(detail.amountToZeroCents)} para o caixa ficar zerado.',
        const Color(0xFFFEF3C7),
      ),
      < 0 => (
        'Caixa abaixo de zero',
        'O caixa está abaixo do zero em ${AppFormatters.currencyFromCents(detail.amountToZeroCents)}.',
        colorScheme.errorContainer,
      ),
      _ => (
        'Caixa zerado',
        'O saldo consolidado desta sessão está zerado.',
        const Color(0xFFDCFCE7),
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: toneColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MovementDetailTile extends StatelessWidget {
  const _MovementDetailTile({required this.detail});

  final CashSessionMovementDetail detail;

  @override
  Widget build(BuildContext context) {
    final movement = detail.movement;
    final isNegative = movement.amountCents < 0;
    final amountTone = isNegative
        ? AppStatusTone.warning
        : AppStatusTone.success;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStatusBadge(
                        label: detail.originLabel,
                        tone: amountTone,
                      ),
                      if (detail.saleStatus != null)
                        AppStatusBadge(
                          label: detail.saleStatus!.label,
                          tone: detail.saleStatus == SaleStatus.cancelled
                              ? AppStatusTone.danger
                              : AppStatusTone.info,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  AppFormatters.currencyFromCents(movement.amountCents),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isNegative
                        ? Theme.of(context).colorScheme.error
                        : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoLine(
              label: 'Data e hora',
              value: AppFormatters.shortDateTime(movement.createdAt),
            ),
            if (detail.referenceLabel != null) ...[
              const SizedBox(height: 10),
              _InfoLine(label: 'Referência', value: detail.referenceLabel!),
            ],
            if (detail.clientName?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              _InfoLine(label: 'Cliente', value: detail.clientName!),
            ],
            if (movement.paymentMethod != null) ...[
              const SizedBox(height: 10),
              _InfoLine(
                label: 'Forma de pagamento',
                value: movement.paymentMethod!.label,
              ),
            ] else if (detail.salePaymentMethod != null) ...[
              const SizedBox(height: 10),
              _InfoLine(
                label: 'Forma de pagamento',
                value: detail.salePaymentMethod!.label,
              ),
            ],
            if (movement.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              _InfoLine(label: 'Comentário', value: movement.description!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaleSummaryTile extends StatelessWidget {
  const _SaleSummaryTile({required this.summary});

  final CashSessionSaleSummary summary;

  @override
  Widget build(BuildContext context) {
    final sale = summary.sale;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cupom ${sale.receiptNumber}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.shortDateTime(sale.soldAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  AppFormatters.currencyFromCents(sale.finalCents),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppStatusBadge(
                  label: sale.saleType.label,
                  tone: sale.saleType == SaleType.fiado
                      ? AppStatusTone.warning
                      : AppStatusTone.info,
                ),
                AppStatusBadge(
                  label: sale.paymentMethod.label,
                  tone: AppStatusTone.neutral,
                ),
                AppStatusBadge(
                  label: sale.status.label,
                  tone: sale.status == SaleStatus.cancelled
                      ? AppStatusTone.danger
                      : AppStatusTone.success,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoLine(
              label: 'Cliente',
              value: sale.clientName ?? 'Não informado',
            ),
            const SizedBox(height: 10),
            _InfoLine(
              label: 'Quantidade de itens',
              value: '${summary.itemLinesCount} item(ns)',
            ),
            if (sale.discountCents > 0 || sale.surchargeCents > 0) ...[
              const SizedBox(height: 10),
              _InfoLine(
                label: 'Ajustes',
                value:
                    'Desconto ${AppFormatters.currencyFromCents(sale.discountCents)} • Acréscimo ${AppFormatters.currencyFromCents(sale.surchargeCents)}',
              ),
            ],
            if (summary.itemPreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Resumo dos itens',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final item in summary.itemPreview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${item.productName} • ${AppFormatters.quantityFromMil(item.quantityMil)} ${item.unitMeasure}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
