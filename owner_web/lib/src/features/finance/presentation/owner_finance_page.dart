import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerFinancePage extends ConsumerWidget {
  const OwnerFinancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(ownerReceivablesProvider);
    final selectedStatus = ref.watch(ownerReceivablesStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerPageIntro(
          title: 'Fiado e financeiro',
          subtitle:
              'Acompanhe contas a receber, valores em aberto e saúde financeira da operação.',
          icon: Icons.account_balance_wallet_rounded,
          trailing: SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'open', child: Text('Em aberto')),
                DropdownMenuItem(value: 'overdue', child: Text('Vencidos')),
                DropdownMenuItem(value: 'paid', child: Text('Pagos')),
                DropdownMenuItem(value: 'all', child: Text('Todos')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                ref.read(ownerReceivablesStatusProvider.notifier).state = value;
                ref.read(ownerReceivablesPageProvider.notifier).state = 1;
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: report,
          onRetry: () => ref.invalidate(ownerReceivablesProvider),
          builder: (data) => _ReceivablesContent(data: data),
        ),
      ],
    );
  }
}

class _ReceivablesContent extends StatelessWidget {
  const _ReceivablesContent({required this.data});

  final OwnerReceivablesReport data;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            OwnerMetricCard(
              title: 'Total em aberto',
              value: OwnerFormatters.moneyFromCents(summary.openAmountCents),
              detail: '${summary.openCount} clientes com saldo.',
              icon: Icons.receipt_long_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Vencidos',
              value: OwnerFormatters.moneyFromCents(summary.overdueAmountCents),
              detail: summary.overdueCount == 0
                  ? 'Sem vencimentos informados.'
                  : '${summary.overdueCount} contas vencidas.',
              icon: Icons.warning_amber_rounded,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Recebido no mês',
              value: OwnerFormatters.moneyFromCents(
                summary.receivedThisMonthCents,
              ),
              detail: 'Pagamentos de fiado registrados no mês.',
              icon: Icons.event_available_outlined,
              isAvailable: true,
            ),
            OwnerMetricCard(
              title: 'Contas pagas',
              value: '${summary.paidCount}',
              detail: 'Clientes sem saldo pendente no filtro.',
              icon: Icons.check_circle_outline_rounded,
              isAvailable: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
        OwnerSectionCard(
          title: 'Clientes com saldo',
          subtitle: 'Lista de contas em aberto por cliente.',
          child: _ReceivableList(page: data.items),
        ),
      ],
    );
  }
}

class _ReceivableList extends StatelessWidget {
  const _ReceivableList({required this.page});

  final OwnerReceivableItemPage page;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma conta encontrada',
        message: 'As contas a receber aparecerão aqui quando houver fiado.',
        icon: Icons.request_quote_outlined,
      );
    }
    return Column(
      children: [
        for (final item in page.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(item.customerName),
            subtitle: Text(
              '${item.salesCount} vendas - ${_dueDateLabel(item.dueDate)}',
            ),
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.openAmountCents),
            ),
          ),
      ],
    );
  }
}

String _dueDateLabel(String? dueDate) {
  if (dueDate == null || dueDate.trim().isEmpty) {
    return 'Sem vencimento informado';
  }
  return 'Vence em ${OwnerFormatters.date(dueDate)}';
}
