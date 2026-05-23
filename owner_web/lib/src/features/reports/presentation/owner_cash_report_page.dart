import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerCashReportPage extends ConsumerWidget {
  const OwnerCashReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(ownerCashSessionsProvider);
    final selectedId = ref.watch(ownerSelectedCashSessionIdProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OwnerPageIntro(
            title: 'Relatorios de caixa',
            subtitle:
                'Consulte caixas antigos, encontre vendas e registre acoes administrativas sem alterar o fechamento original.',
            icon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: 18),
          const _CashFilters(),
          const SizedBox(height: 18),
          OwnerAsyncView(
            value: report,
            onRetry: () => ref.invalidate(ownerCashSessionsProvider),
            builder: (data) => _CashReportContent(report: data),
          ),
          if (selectedId != null) ...[
            const SizedBox(height: 18),
            OwnerAsyncView(
              value: ref.watch(ownerCashSessionDetailProvider(selectedId)),
              onRetry: () =>
                  ref.invalidate(ownerCashSessionDetailProvider(selectedId)),
              builder: (detail) => _CashDetail(detail: detail),
            ),
          ],
        ],
      ),
    );
  }
}

class _CashFilters extends ConsumerWidget {
  const _CashFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ownerCashSessionsStatusProvider);
    final search = ref.watch(ownerCashSessionsSearchProvider);
    return OwnerSectionCard(
      title: 'Filtros',
      subtitle: 'Use periodo, status e busca para localizar um caixa antigo.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: TextFormField(
              initialValue: ref.watch(ownerReportStartDateProvider),
              decoration: const InputDecoration(labelText: 'Data inicial'),
              onChanged: (value) {
                ref.read(ownerReportStartDateProvider.notifier).state = value;
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: TextFormField(
              initialValue: ref.watch(ownerReportEndDateProvider),
              decoration: const InputDecoration(labelText: 'Data final'),
              onChanged: (value) {
                ref.read(ownerReportEndDateProvider.notifier).state = value;
              },
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'open', child: Text('Aberto')),
                DropdownMenuItem(value: 'closed', child: Text('Fechado')),
                DropdownMenuItem(
                  value: 'with_difference',
                  child: Text('Com diferenca'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref.read(ownerCashSessionsStatusProvider.notifier).state =
                    value;
              },
            ),
          ),
          SizedBox(
            width: 320,
            child: TextFormField(
              initialValue: search,
              decoration: const InputDecoration(
                labelText: 'Buscar caixa, funcionario ou observacao',
              ),
              onChanged: (value) {
                ref.read(ownerCashSessionsSearchProvider.notifier).state =
                    value;
              },
            ),
          ),
          FilledButton.icon(
            onPressed: () => ref.invalidate(ownerCashSessionsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }
}

class _CashReportContent extends ConsumerWidget {
  const _CashReportContent({required this.report});

  final OwnerCashSessionsReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = report.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OwnerMetricCard(
              title: 'Total vendido',
              value: OwnerFormatters.moneyFromCents(summary.totalSoldCents),
              detail: '${summary.salesCount} vendas',
              icon: Icons.point_of_sale_rounded,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Caixas',
              value: OwnerFormatters.integer(summary.totalSessions),
              detail: '${summary.sessionsWithDifference} com diferenca',
              icon: Icons.account_balance_wallet_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Sangrias/suprimentos',
              value:
                  '${OwnerFormatters.moneyFromCents(summary.totalCashOutflowCents)} / ${OwnerFormatters.moneyFromCents(summary.totalCashInflowCents)}',
              detail: 'Saidas e entradas registradas',
              icon: Icons.swap_vert_rounded,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Ticket medio',
              value: OwnerFormatters.moneyFromCents(summary.averageTicketCents),
              detail: 'Periodo selecionado',
              icon: Icons.trending_up_rounded,
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Caixas encontrados',
          subtitle: 'Cada caixa preserva abertura, fechamento e vendas.',
          child: report.items.items.isEmpty
              ? const OwnerEmptyState(
                  title: 'Nenhum caixa encontrado',
                  message: 'Ajuste os filtros ou escolha outro periodo.',
                  icon: Icons.search_off_rounded,
                )
              : Column(
                  children: [
                    for (final item in report.items.items)
                      _CashSessionTile(
                        item: item,
                        onOpen: () {
                          ref
                              .read(ownerSelectedCashSessionIdProvider.notifier)
                              .state = item
                              .id;
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CashSessionTile extends StatelessWidget {
  const _CashSessionTile({required this.item, required this.onOpen});

  final OwnerCashSessionItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text('${item.shortId} - ${item.employee.name}'),
        subtitle: Text(
          'Aberto em ${OwnerFormatters.date(item.openedAt)} - ${item.statusLabel}',
        ),
        trailing: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(OwnerFormatters.moneyFromCents(item.totalSoldCents)),
            Text('${item.salesCount} vendas'),
            if (item.differenceCents != 0)
              Text(
                'Dif. ${OwnerFormatters.moneyFromCents(item.differenceCents)}',
              ),
            TextButton(onPressed: onOpen, child: const Text('Ver detalhes')),
          ],
        ),
      ),
    );
  }
}

class _CashDetail extends ConsumerWidget {
  const _CashDetail({required this.detail});

  final OwnerCashSessionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerSectionCard(
      title: 'Detalhe do caixa ${detail.session.shortId}',
      subtitle:
          'Acoes administrativas ficam no historico da venda e nao alteram o fechamento original do caixa.',
      trailing: IconButton(
        tooltip: 'Fechar detalhe',
        onPressed: () {
          ref.read(ownerSelectedCashSessionIdProvider.notifier).state = null;
        },
        icon: const Icon(Icons.close_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OwnerMetricCard(
                title: 'Responsavel',
                value: detail.employee.name,
                detail: detail.employee.email ?? 'Sem e-mail',
                icon: Icons.badge_outlined,
                isAvailable: true,
              ),
              OwnerMetricCard(
                title: 'Declarado',
                value: OwnerFormatters.moneyFromCents(
                  detail.values.closingBalanceCents ?? 0,
                ),
                detail:
                    'Esperado ${OwnerFormatters.moneyFromCents(detail.values.expectedBalanceCents ?? 0)}',
                icon: Icons.fact_check_outlined,
                isAvailable: true,
              ),
              OwnerMetricCard(
                title: 'Diferenca',
                value: OwnerFormatters.moneyFromCents(
                  detail.values.differenceCents,
                ),
                detail: detail.session.statusLabel,
                icon: Icons.balance_outlined,
                isAvailable: detail.values.differenceCents == 0,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SalesList(sessionId: detail.session.id, sales: detail.sales.items),
          const SizedBox(height: 18),
          _MovementsList(movements: detail.movements),
        ],
      ),
    );
  }
}

class _SalesList extends StatelessWidget {
  const _SalesList({required this.sessionId, required this.sales});

  final String sessionId;
  final List<OwnerCashSessionSale> sales;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma venda neste caixa',
        message:
            'Quando houver vendas vinculadas ao caixa, elas aparecerao aqui.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vendas do caixa',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final sale in sales) _SaleTile(sessionId: sessionId, sale: sale),
      ],
    );
  }
}

class _SaleTile extends ConsumerWidget {
  const _SaleTile({required this.sessionId, required this.sale});

  final String sessionId;
  final OwnerCashSessionSale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text('Venda ${sale.receiptNumber ?? sale.shortId}'),
        subtitle: Text(
          '${OwnerFormatters.date(sale.soldAt)} - ${sale.paymentMethod} - ${sale.statusLabel}',
        ),
        trailing: Text(OwnerFormatters.moneyFromCents(sale.totalAmountCents)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Cliente: ${sale.customerName ?? 'Nao informado'}'),
          ),
          const SizedBox(height: 8),
          for (final item in sale.items)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${item.productName} - ${OwnerFormatters.quantityFromMil(item.quantityMil)} x ${OwnerFormatters.moneyFromCents(item.unitPriceCents)}',
              ),
            ),
          if (sale.actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final action in sale.actions)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${action.title}: ${OwnerFormatters.moneyFromCents(action.amountCents)}',
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showReceiptDialog(context, sale),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Ver comprovante'),
              ),
              if (sale.canReturn)
                FilledButton.icon(
                  onPressed: () =>
                      _showReturnDialog(context, ref, sessionId, sale),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Registrar troca/devolucao'),
                ),
              if (sale.canCancel)
                OutlinedButton.icon(
                  onPressed: () =>
                      _confirmCancel(context, ref, sessionId, sale),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar venda'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovementsList extends StatelessWidget {
  const _MovementsList({required this.movements});

  final List<OwnerCashMovement> movements;

  @override
  Widget build(BuildContext context) {
    return OwnerSectionCard(
      title: 'Movimentos e historico',
      subtitle:
          'Inclui movimentos do caixa e acoes administrativas posteriores.',
      child: movements.isEmpty
          ? const OwnerEmptyState(
              title: 'Sem movimentos',
              message: 'Nenhum movimento foi encontrado para este caixa.',
            )
          : Column(
              children: [
                for (final movement in movements)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(movement.title),
                    subtitle: Text(
                      '${OwnerFormatters.date(movement.createdAt)} - ${movement.notes ?? 'Sem observacao'}',
                    ),
                    trailing: Text(
                      OwnerFormatters.moneyFromCents(movement.amountCents),
                    ),
                  ),
              ],
            ),
    );
  }
}

void _showReceiptDialog(BuildContext context, OwnerCashSessionSale sale) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Comprovante ${sale.receiptNumber ?? sale.shortId}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Data: ${OwnerFormatters.date(sale.soldAt)}'),
            Text('Cliente: ${sale.customerName ?? 'Nao informado'}'),
            Text('Forma: ${sale.paymentMethod}'),
            const SizedBox(height: 12),
            for (final item in sale.items)
              Text(
                '${item.productName}: ${OwnerFormatters.moneyFromCents(item.totalPriceCents)}',
              ),
            const Divider(),
            Text(
              'Total: ${OwnerFormatters.moneyFromCents(sale.totalAmountCents)}',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

Future<void> _showReturnDialog(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  OwnerCashSessionSale sale,
) async {
  final reasonController = TextEditingController();
  final quantities = <String, int>{
    for (final item in sale.items) item.id: item.quantityMil,
  };
  var returnToStock = true;
  var submitting = false;
  final messenger = ScaffoldMessenger.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Registrar troca/devolucao'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Essa acao sera registrada no historico da venda e nao altera o fechamento original do caixa.',
              ),
              const SizedBox(height: 12),
              for (final item in sale.items)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: (quantities[item.id] ?? 0) > 0,
                  title: Text(item.productName),
                  subtitle: Text(
                    'Quantidade: ${OwnerFormatters.quantityFromMil(item.quantityMil)}',
                  ),
                  onChanged: submitting
                      ? null
                      : (checked) {
                          setState(() {
                            quantities[item.id] = checked == true
                                ? item.quantityMil
                                : 0;
                          });
                        },
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: returnToStock,
                title: const Text('Voltar item ao estoque'),
                onChanged: submitting
                    ? null
                    : (value) => setState(() => returnToStock = value == true),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Motivo'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting
                ? null
                : () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    final reason = reasonController.text.trim();
                    if (reason.length < 3) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Informe o motivo.')),
                      );
                      return;
                    }
                    final selectedItems = quantities.entries
                        .where((entry) => entry.value > 0)
                        .map(
                          (entry) => {
                            'saleItemId': entry.key,
                            'quantityMil': entry.value,
                          },
                        )
                        .toList(growable: false);
                    if (selectedItems.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Selecione pelo menos um item.'),
                        ),
                      );
                      return;
                    }
                    final navigator = Navigator.of(dialogContext);
                    var keepDialogOpen = true;
                    setState(() => submitting = true);
                    try {
                      await ref
                          .read(ownerApiServiceProvider)
                          .registerSaleReturn(
                            cashSessionId: sessionId,
                            saleId: sale.id,
                            body: {
                              'reason': reason,
                              'returnToStock': returnToStock,
                              'items': selectedItems,
                            },
                          );
                      ref.invalidate(ownerCashSessionsProvider);
                      ref.invalidate(ownerCashSessionDetailProvider(sessionId));
                      keepDialogOpen = false;
                      if (navigator.mounted) {
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Troca/devolucao registrada.'),
                          ),
                        );
                      }
                    } on OwnerApiException catch (error) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    } finally {
                      if (keepDialogOpen) {
                        setState(() => submitting = false);
                      }
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirmar troca/devolucao'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmCancel(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  OwnerCashSessionSale sale,
) async {
  final reasonController = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancelar venda'),
      content: TextField(
        controller: reasonController,
        decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
        maxLines: 2,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirmar cancelamento'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final reason = reasonController.text.trim();
  if (reason.length < 3) {
    messenger.showSnackBar(const SnackBar(content: Text('Informe o motivo.')));
    return;
  }
  try {
    await ref
        .read(ownerApiServiceProvider)
        .cancelCashSessionSale(
          cashSessionId: sessionId,
          saleId: sale.id,
          reason: reason,
        );
    ref.invalidate(ownerCashSessionsProvider);
    ref.invalidate(ownerCashSessionDetailProvider(sessionId));
    messenger.showSnackBar(const SnackBar(content: Text('Venda cancelada.')));
  } on OwnerApiException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}
