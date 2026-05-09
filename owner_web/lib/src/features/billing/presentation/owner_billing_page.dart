import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';

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
        OwnerAsyncView(
          value: status,
          onRetry: () => ref.invalidate(ownerBillingStatusProvider),
          builder: (data) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plano ${data.plan}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        Chip(label: Text(OwnerFormatters.status(data.status))),
                        if (data.maskedProviderSubscriptionId != null)
                          Chip(label: Text(data.maskedProviderSubscriptionId!)),
                        if (data.pendingPlan != null)
                          Chip(
                            label: Text('Troca pendente ${data.pendingPlan}'),
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
                          label: 'Próxima renovação',
                          value: OwnerFormatters.date(data.nextPaymentDate),
                        ),
                        _BillingInfo(
                          label: 'Fim do período',
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
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cobranças',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String?>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          for (final status in _statuses)
                            DropdownMenuItem<String?>(
                              value: status,
                              child: Text(status),
                            ),
                        ],
                        onChanged: (value) {
                          ref.read(ownerInvoicePageProvider.notifier).state = 1;
                          ref
                                  .read(
                                    ownerInvoiceStatusFilterProvider.notifier,
                                  )
                                  .state =
                              value;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OwnerAsyncView(
                  value: invoices,
                  onRetry: () => ref.invalidate(ownerBillingInvoicesProvider),
                  builder: (page) {
                    if (page.items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Nenhuma cobrança encontrada ainda.'),
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
                                : const Chip(
                                    label: Text('Link seguro disponível'),
                                  ),
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
              ],
            ),
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
