import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/client.dart';
import '../../domain/entities/customer_credit_transaction.dart';
import '../providers/client_providers.dart';

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
      appBar: AppBar(title: const Text('Haver do cliente')),
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
                      'Haver disponível',
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
                          onPressed: () => _openManualDialog(
                            context,
                            ref,
                            client: client,
                            isCredit: true,
                          ),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Lançar crédito'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openManualDialog(
                            context,
                            ref,
                            client: client,
                            isCredit: false,
                          ),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Lançar débito'),
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
                      title: 'Sem movimentações de haver',
                      message:
                          'Quando houver crédito, uso ou estorno, o extrato aparecerá aqui.',
                      compact: true,
                    );
                  }

                  return AppSectionCard(
                    title: 'Extrato',
                    subtitle: 'Movimentações registradas no cliente.',
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
                  message: 'Organizando o histórico de haver.',
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

  Future<void> _openManualDialog(
    BuildContext context,
    WidgetRef ref, {
    required Client? client,
    required bool isCredit,
  }) async {
    if (client == null) {
      AppFeedback.error(
        context,
        'Cliente nao foi encontrado para este extrato.',
      );
      return;
    }

    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final submitted = await showDialog<(int, String?)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isCredit ? 'Lançar crédito' : 'Lançar débito'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Valor'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  hintText: 'Opcional',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop((
                  MoneyParser.parseToCents(amountController.text),
                  descriptionController.text.trim().isEmpty
                      ? null
                      : descriptionController.text.trim(),
                ));
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    amountController.dispose();
    descriptionController.dispose();

    if (submitted == null) {
      return;
    }

    try {
      final controller = ref.read(customerCreditControllerProvider.notifier);
      final transaction = isCredit
          ? await controller.addManualCredit(
              customerId: client.id,
              amountCents: submitted.$1,
              description: submitted.$2,
            )
          : await controller.addManualDebit(
              customerId: client.id,
              amountCents: submitted.$1,
              description: submitted.$2,
            );
      if (!context.mounted) {
        return;
      }
      AppFeedback.success(
        context,
        isCredit
            ? 'Crédito lançado com sucesso.'
            : 'Débito lançado com sucesso.',
      );
      context.pushNamed(
        AppRouteNames.customerCreditReceipt,
        pathParameters: {'transactionId': '${transaction.id}'},
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel registrar o haver: $error');
    }
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
                transaction.description ?? 'Sem observação',
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
        return 'Crédito manual';
      case CustomerCreditTransactionType.manualDebit:
        return 'Débito manual';
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
        return 'Devolução em haver';
      default:
        return 'Movimentação de haver';
    }
  }
}
