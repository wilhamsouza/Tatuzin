import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerBillingPage extends ConsumerWidget {
  const OwnerBillingPage({super.key});

  static const _statuses = <String>[
    'pending',
    'in_process',
    'paid',
    'failed',
    'rejected',
    'cancelled',
    'refunded',
    'unknown',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ownerBillingStatusProvider);
    final invoices = ref.watch(ownerBillingInvoicesProvider);
    final selectedStatus = ref.watch(ownerInvoiceStatusFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OwnerPageIntro(
          title: 'Assinatura e cobranças',
          subtitle:
              'Consulte o plano atual, próximas cobranças e histórico financeiro da assinatura.',
          icon: Icons.receipt_long_rounded,
        ),
        const SizedBox(height: 18),
        OwnerAsyncView(
          value: status,
          onRetry: () => ref.invalidate(ownerBillingStatusProvider),
          builder: (data) {
            return OwnerSectionCard(
              title: 'Plano atual',
              subtitle: 'Informações da assinatura em modo consulta.',
              trailing: Chip(label: Text(OwnerFormatters.status(data.status))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ownerPlanLabel(data.plan),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (data.hasProviderSubscription)
                        const Chip(label: Text('Cobrança vinculada')),
                      if (data.pendingPlan != null)
                        Chip(
                          label: Text(
                            'Troca pendente para ${ownerPlanLabel(data.pendingPlan)}',
                          ),
                        ),
                      if (data.cancelAtPeriodEnd)
                        const Chip(label: Text('Cancelamento agendado')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      _BillingInfo(
                        label: 'Próxima cobrança',
                        value: OwnerFormatters.date(data.nextPaymentDate),
                      ),
                      _BillingInfo(
                        label: 'Fim do período atual',
                        value: OwnerFormatters.date(data.currentPeriodEnd),
                      ),
                      _BillingInfo(
                        label: 'Solicitação de troca',
                        value: OwnerFormatters.date(
                          data.pendingPlanRequestedAt,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Alterações de plano serão liberadas em uma próxima etapa do painel.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        OwnerSectionCard(
          title: 'Cobranças',
          subtitle: 'Histórico de cobranças da assinatura.',
          trailing: SizedBox(
            width: 240,
            child: DropdownButtonFormField<String?>(
              initialValue: selectedStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos'),
                ),
                for (final status in _statuses)
                  DropdownMenuItem<String?>(
                    value: status,
                    child: Text(OwnerFormatters.status(status)),
                  ),
              ],
              onChanged: (value) {
                ref.read(ownerInvoicePageProvider.notifier).state = 1;
                ref.read(ownerInvoiceStatusFilterProvider.notifier).state =
                    value;
              },
            ),
          ),
          child: OwnerAsyncView(
            value: invoices,
            onRetry: () => ref.invalidate(ownerBillingInvoicesProvider),
            builder: (page) {
              if (page.items.isEmpty) {
                return const OwnerEmptyState(
                  title: 'Nenhuma cobrança encontrada',
                  message:
                      'As cobranças da assinatura aparecerão aqui quando houver histórico disponível.',
                  icon: Icons.receipt_long_outlined,
                );
              }
              return Column(
                children: [
                  for (final invoice in page.items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_rounded),
                      title: Text(
                        OwnerFormatters.moneyFromCents(
                          invoice.amountCents,
                          currency: invoice.currency,
                        ),
                      ),
                      subtitle: Text(
                        '${OwnerFormatters.status(invoice.status)} • '
                        'Vencimento ${OwnerFormatters.date(invoice.dueAt)}',
                      ),
                      trailing: invoice.invoiceUrl == null
                          ? null
                          : const Chip(label: Text('Comprovante disponível')),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${page.count} de ${page.total}'),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Página anterior',
                        onPressed: page.hasPrevious
                            ? () => ref
                                  .read(ownerInvoicePageProvider.notifier)
                                  .state--
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: 'Próxima página',
                        onPressed: page.hasNext
                            ? () => ref
                                  .read(ownerInvoicePageProvider.notifier)
                                  .state++
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BillingInfo extends StatelessWidget {
  const _BillingInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
