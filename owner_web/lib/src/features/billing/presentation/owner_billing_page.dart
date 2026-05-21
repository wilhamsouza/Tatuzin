import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_auth_controller.dart';
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
    final canManageBilling = status.valueOrNull?.canManageBilling == true;
    final invoices = canManageBilling
        ? ref.watch(ownerBillingInvoicesProvider)
        : null;
    final selectedStatus = canManageBilling
        ? ref.watch(ownerInvoiceStatusFilterProvider)
        : null;

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
                  if (data.canManageBilling)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _changePlan(context, ref, data.plan),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Alterar plano'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _refreshBilling(context, ref),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Atualizar assinatura'),
                        ),
                        if (data.cancelAtPeriodEnd)
                          OutlinedButton.icon(
                            onPressed: () => _resumeBilling(context, ref),
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('Retomar assinatura'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => _cancelBilling(context, ref),
                            icon: const Icon(Icons.event_busy_rounded),
                            label: const Text('Cancelar no fim do periodo'),
                          ),
                      ],
                    )
                  else
                    const Chip(
                      label: Text('Apenas o dono pode alterar a assinatura'),
                    ),
                ],
              ),
            );
          },
        ),
        if (canManageBilling) ...[
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
              value: invoices!,
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

Future<void> _changePlan(
  BuildContext context,
  WidgetRef ref,
  String currentPlan,
) async {
  final selected = await showDialog<String>(
    context: context,
    builder: (_) => SimpleDialog(
      title: const Text('Alterar plano'),
      children: [
        for (final plan in ['BASIC', 'PRO'])
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(plan),
            child: Text(
              '${ownerPlanLabel(plan)}${plan == currentPlan ? ' (atual)' : ''}',
            ),
          ),
      ],
    ),
  );
  if (selected == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  await _runBillingAction(context, ref, () async {
    if (currentPlan == 'FREE') {
      return ref.read(ownerApiServiceProvider).subscribe(plan: selected);
    }
    return ref.read(ownerApiServiceProvider).changePlan(plan: selected);
  });
}

Future<void> _refreshBilling(BuildContext context, WidgetRef ref) {
  return _runBillingAction(
    context,
    ref,
    () => ref.read(ownerApiServiceProvider).refreshBilling(),
  );
}

Future<void> _cancelBilling(BuildContext context, WidgetRef ref) async {
  final confirmed = await _confirmBillingAction(
    context,
    title: 'Cancelar assinatura?',
    message:
        'O cancelamento sera agendado para o fim do periodo atual, conforme regra da assinatura.',
    confirmLabel: 'Agendar cancelamento',
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runBillingAction(
    context,
    ref,
    () => ref.read(ownerApiServiceProvider).cancelSubscription(),
  );
}

Future<void> _resumeBilling(BuildContext context, WidgetRef ref) async {
  final confirmed = await _confirmBillingAction(
    context,
    title: 'Retomar assinatura?',
    message: 'O cancelamento agendado sera removido.',
    confirmLabel: 'Retomar',
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runBillingAction(
    context,
    ref,
    () => ref.read(ownerApiServiceProvider).resumeSubscription(),
  );
}

Future<bool> _confirmBillingAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

Future<void> _runBillingAction(
  BuildContext context,
  WidgetRef ref,
  Future<Object?> Function() action,
) async {
  try {
    await action();
    ref.invalidate(ownerBillingStatusProvider);
    ref.invalidate(ownerBillingInvoicesProvider);
    ref.read(ownerRefreshTickProvider.notifier).state++;
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Assinatura atualizada.')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeOwnerError(error))));
    }
  }
}
