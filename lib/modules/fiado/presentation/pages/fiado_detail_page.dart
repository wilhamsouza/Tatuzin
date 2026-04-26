import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../caixa/presentation/providers/cash_providers.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../comprovantes/domain/entities/commercial_receipt_request.dart';
import '../../../comprovantes/presentation/widgets/receipt_action_bar.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/fiado_detail.dart';
import '../../domain/entities/fiado_payment_input.dart';
import '../providers/fiado_providers.dart';

class FiadoDetailPage extends ConsumerWidget {
  const FiadoDetailPage({super.key, required this.fiadoId});

  final int fiadoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(fiadoDetailProvider(fiadoId));
    final paymentState = ref.watch(fiadoPaymentControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do fiado')),
      body: detailAsync.when(
        data: (detail) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.account.clientName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppStatusBadge(
                          label: 'Cupom ${detail.account.receiptNumber}',
                          tone: AppStatusTone.neutral,
                        ),
                        AppStatusBadge(
                          label: _statusLabel(detail),
                          tone: _toneForStatus(detail),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Saldo em aberto',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatters.currencyFromCents(detail.account.openCents),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Valor original: ${AppFormatters.currencyFromCents(detail.account.originalCents)}',
                    ),
                    Text(
                      'Vencimento: ${AppFormatters.shortDate(detail.account.dueDate)}',
                    ),
                    const SizedBox(height: 16),
                    ReceiptActionBar(
                      request: CommercialReceiptRequest.sale(
                        saleId: detail.account.saleId,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (paymentState.hasError) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    paymentState.error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            if (!detail.account.isSettled && !detail.account.isCancelled) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: paymentState.isLoading
                    ? null
                    : () => _registerPayment(context, ref, detail),
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  paymentState.isLoading
                      ? 'Registrando...'
                      : 'Receber pagamento',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lançamentos',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    for (final entry in detail.entries) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_entryTitle(entry.entryType)),
                        subtitle: Text(
                          [
                            AppFormatters.shortDateTime(entry.registeredAt),
                            if (entry.paymentMethod != null)
                              entry.paymentMethod!.label,
                            if (entry.notes?.isNotEmpty ?? false) entry.notes!,
                          ].join(' | '),
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppFormatters.currencyFromCents(
                                entry.amountCents,
                              ),
                            ),
                            if (entry.entryType == 'pagamento')
                              IconButton(
                                tooltip: 'Comprovante do recebimento',
                                onPressed: () => context.pushNamed(
                                  AppRouteNames.fiadoPaymentReceipt,
                                  pathParameters: {
                                    'fiadoId': '${detail.account.id}',
                                    'entryId': '${entry.id}',
                                  },
                                ),
                                icon: const Icon(Icons.receipt_long_outlined),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Falha ao carregar o fiado: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(fiadoDetailProvider(fiadoId)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _registerPayment(
    BuildContext context,
    WidgetRef ref,
    FiadoDetail detail,
  ) async {
    final amountController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(detail.account.openCents),
    );
    final notesController = TextEditingController();
    var selectedPaymentMethod = PaymentMethod.cash;
    var convertOverpaymentToCredit = false;

    final submitted = await showDialog<FiadoPaymentInput>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Receber pagamento'),
              content: SingleChildScrollView(
                child: Column(
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
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: selectedPaymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pagamento',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: PaymentMethod.cash,
                          child: Text('Dinheiro'),
                        ),
                        DropdownMenuItem(
                          value: PaymentMethod.pix,
                          child: Text('Pix'),
                        ),
                        DropdownMenuItem(
                          value: PaymentMethod.card,
                          child: Text('Cartão'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => selectedPaymentMethod = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: convertOverpaymentToCredit,
                      onChanged: (value) {
                        setState(() => convertOverpaymentToCredit = value);
                      },
                      title: const Text('Converter excedente em haver'),
                      subtitle: const Text(
                        'Se o pagamento passar do saldo aberto, o excedente vira crédito do cliente.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observação',
                        hintText: 'Opcional',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      FiadoPaymentInput(
                        fiadoId: detail.account.id,
                        amountCents: MoneyParser.parseToCents(
                          amountController.text,
                        ),
                        paymentMethod: selectedPaymentMethod,
                        notes: notesController.text.trim(),
                        convertOverpaymentToCredit: convertOverpaymentToCredit,
                      ),
                    );
                  },
                  child: const Text('Confirmar pagamento'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    notesController.dispose();

    if (submitted == null) {
      return;
    }

    try {
      final updatedDetail = await ref
          .read(fiadoPaymentControllerProvider.notifier)
          .registerPayment(submitted);
      ref.invalidate(fiadoListProvider);
      ref.invalidate(fiadoDetailProvider(detail.account.id));
      ref.invalidate(clientListProvider);
      ref.invalidate(customerCreditBalanceProvider(detail.account.clientId));
      ref.invalidate(
        customerCreditTransactionsProvider(detail.account.clientId),
      );
      ref.invalidate(currentCashSessionProvider);
      ref.invalidate(currentCashMovementsProvider);
      ref.invalidate(cashSessionHistoryProvider);
      ref.invalidate(saleHistoryListProvider);
      ref.invalidate(saleDetailProvider(detail.account.saleId));
      ref.invalidate(operationalDashboardSnapshotProvider);

      if (!context.mounted) {
        return;
      }

      final latestPayment = updatedDetail.entries.firstWhere(
        (entry) => entry.entryType == 'pagamento',
      );
      final paidCents = submitted.amountCents > detail.account.openCents
          ? detail.account.openCents
          : submitted.amountCents;
      final generatedCreditCents = submitted.convertOverpaymentToCredit
          ? submitted.amountCents - paidCents
          : 0;

      if (generatedCreditCents > 0) {
        final transactions = await ref.read(
          customerCreditTransactionsProvider(detail.account.clientId).future,
        );
        final latestCredit = transactions.firstWhere(
          (transaction) =>
              transaction.originPaymentId == latestPayment.id &&
              transaction.type == 'overpayment_credit',
        );
        if (!context.mounted) {
          return;
        }
        context.pushNamed(
          AppRouteNames.customerCreditReceipt,
          pathParameters: {'transactionId': '${latestCredit.id}'},
          extra: true,
        );
      } else {
        context.pushNamed(
          AppRouteNames.fiadoPaymentReceipt,
          pathParameters: {
            'fiadoId': '${detail.account.id}',
            'entryId': '${latestPayment.id}',
          },
          extra: true,
        );
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  AppStatusTone _toneForStatus(FiadoDetail detail) {
    if (detail.account.isCancelled) {
      return AppStatusTone.danger;
    }
    if (detail.account.isSettled) {
      return AppStatusTone.success;
    }
    final isOverdue =
        !detail.account.isCancelled &&
        !detail.account.isSettled &&
        detail.account.dueDate.isBefore(DateTime.now());
    if (isOverdue) {
      return AppStatusTone.warning;
    }
    return detail.account.status == 'parcial'
        ? AppStatusTone.info
        : AppStatusTone.neutral;
  }

  String _statusLabel(FiadoDetail detail) {
    switch (detail.account.status) {
      case 'pendente':
        return 'Pendente';
      case 'parcial':
        return 'Parcial';
      case 'quitado':
        return 'Quitado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return detail.account.status;
    }
  }

  String _entryTitle(String type) {
    switch (type) {
      case 'abertura':
        return 'Abertura da nota';
      case 'pagamento':
        return 'Pagamento';
      case 'cancelamento':
        return 'Cancelamento';
      default:
        return type;
    }
  }
}
