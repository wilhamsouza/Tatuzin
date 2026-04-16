import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/client.dart';
import '../../domain/entities/customer_credit_transaction.dart';
import '../providers/client_providers.dart';
import '../support/customer_credit_action_dialog.dart';

class ClientCreditStatementPage extends ConsumerWidget {
  const ClientCreditStatementPage({
    super.key,
    required this.clientId,
    this.initialClient,
  });

  final int clientId;
  final Client? initialClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(
      customerCreditTransactionsProvider(clientId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Extrato do cliente')),
      body: FutureBuilder<Client?>(
        future: ref.read(localClientRepositoryProvider).findById(clientId),
        initialData: initialClient,
        builder: (context, snapshot) {
          final client = snapshot.data ?? initialClient;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppSectionCard(
                title: client?.name ?? 'Cliente',
                subtitle:
                    'Extrato de haver do mais recente para o mais antigo.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Haver disponivel',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatters.currencyFromCents(
                        client?.creditBalanceCents ?? 0,
                      ),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => openCustomerCreditActionDialog(
                            context,
                            ref,
                            client: client,
                            isCredit: true,
                          ),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Adicionar haver'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => openCustomerCreditActionDialog(
                            context,
                            ref,
                            client: client,
                            isCredit: false,
                          ),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Registrar pendencia'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              transactionsAsync.when(
                data: (transactions) {
                  if (transactions.isEmpty) {
                    return const AppStateCard(
                      title: 'Sem movimentacoes de haver',
                      message:
                          'Quando houver adicao de haver, uso ou estorno, o extrato aparecera aqui.',
                      compact: true,
                    );
                  }

                  return AppSectionCard(
                    title: 'Extrato',
                    subtitle: 'Movimentacoes registradas no cliente.',
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < transactions.length;
                          index++
                        ) ...[
                          _CreditTransactionTile(
                            transaction: transactions[index],
                            onOpenReceipt: () => context.pushNamed(
                              AppRouteNames.customerCreditReceipt,
                              pathParameters: {
                                'transactionId': '${transactions[index].id}',
                              },
                            ),
                          ),
                          if (index < transactions.length - 1)
                            const Divider(height: 18),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const AppStateCard(
                  title: 'Carregando extrato',
                  message: 'Organizando o historico de haver.',
                  compact: true,
                  tone: AppStateTone.loading,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Falha ao carregar extrato',
                  message: '$error',
                  compact: true,
                  tone: AppStateTone.error,
                  actionLabel: 'Tentar novamente',
                  onAction: () {
                    ref.invalidate(
                      customerCreditTransactionsProvider(clientId),
                    );
                    ref.invalidate(clientListProvider);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CreditTransactionTile extends StatelessWidget {
  const _CreditTransactionTile({
    required this.transaction,
    required this.onOpenReceipt,
  });

  final CustomerCreditTransaction transaction;
  final VoidCallback onOpenReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCredit = transaction.isCredit;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCredit
                ? colorScheme.primaryContainer.withValues(alpha: 0.72)
                : colorScheme.errorContainer.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            isCredit ? Icons.add_rounded : Icons.remove_rounded,
            color: isCredit ? colorScheme.primary : colorScheme.error,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labelForType(transaction.type),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                transaction.description ?? 'Sem observacao',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppFormatters.shortDateTime(transaction.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isCredit ? '+' : '-'}${AppFormatters.currencyFromCents(transaction.absoluteAmountCents)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: isCredit ? colorScheme.primary : colorScheme.error,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Saldo ${AppFormatters.currencyFromCents(transaction.balanceAfterCents)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: 'Comprovante do haver',
              onPressed: onOpenReceipt,
              icon: const Icon(Icons.receipt_long_outlined),
            ),
          ],
        ),
      ],
    );
  }

  static String _labelForType(String type) {
    switch (type) {
      case CustomerCreditTransactionType.manualCredit:
        return 'Haver manual';
      case CustomerCreditTransactionType.manualDebit:
        return 'Pendencia manual';
      case CustomerCreditTransactionType.overpaymentCredit:
        return 'Excedente em haver';
      case CustomerCreditTransactionType.saleCancelCredit:
        return 'Cancelamento em haver';
      case CustomerCreditTransactionType.changeLeftAsCredit:
        return 'Troco em haver';
      case CustomerCreditTransactionType.creditUsedInSale:
        return 'Haver usado em venda';
      case CustomerCreditTransactionType.creditReversal:
        return 'Estorno de haver';
      case CustomerCreditTransactionType.saleReturnCredit:
        return 'Devolucao em haver';
      default:
        return 'Movimentacao de haver';
    }
  }
}
