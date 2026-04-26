import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_detail.dart';
import '../../domain/entities/purchase_item.dart';
import '../../domain/entities/purchase_payment.dart';
import '../../domain/entities/purchase_status.dart';
import '../providers/purchase_providers.dart';
import '../widgets/purchase_status_badge.dart';
import '../widgets/purchase_summary.dart';
import 'purchase_form_page.dart';

class PurchaseDetailPage extends ConsumerWidget {
  const PurchaseDetailPage({super.key, required this.purchaseId});

  final int purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(purchaseDetailProvider(purchaseId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe da compra')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(purchaseDetailProvider(purchaseId));
          await ref.read(purchaseDetailProvider(purchaseId).future);
        },
        child: detailAsync.when(
          data: (detail) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _PurchaseHeader(detail: detail),
              if (_shouldShowSyncNotice(detail.purchase)) ...[
                const SizedBox(height: 16),
                _PurchaseSyncNotice(purchase: detail.purchase),
              ],
              const SizedBox(height: 16),
              AppSectionCard(
                title: 'Resumo financeiro',
                subtitle: 'Totais e status de pagamento da compra.',
                child: PurchaseSummary(
                  subtotalCents: detail.purchase.subtotalCents,
                  discountCents: detail.purchase.discountCents,
                  surchargeCents: detail.purchase.surchargeCents,
                  freightCents: detail.purchase.freightCents,
                  finalAmountCents: detail.purchase.finalAmountCents,
                  paidAmountCents: detail.purchase.paidAmountCents,
                  pendingAmountCents: detail.purchase.pendingAmountCents,
                ),
              ),
              const SizedBox(height: 16),
              AppSectionCard(
                title: 'Itens',
                subtitle: 'Produtos recebidos e custos registrados.',
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < detail.items.length;
                      index++
                    ) ...[
                      _PurchaseItemRow(item: detail.items[index]),
                      if (index < detail.items.length - 1)
                        const Divider(height: 24),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSectionCard(
                title: 'Pagamentos',
                subtitle: 'Saidas ja registradas no caixa para esta compra.',
                child: detail.payments.isEmpty
                    ? const Text('Nenhum pagamento registrado ainda.')
                    : Column(
                        children: [
                          for (
                            var index = 0;
                            index < detail.payments.length;
                            index++
                          ) ...[
                            _PaymentRow(payment: detail.payments[index]),
                            if (index < detail.payments.length - 1)
                              const Divider(height: 24),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              AppSectionCard(
                title: 'Acoes',
                subtitle: 'Gerencie o ciclo da compra sem sair do modulo.',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          detail.purchase.pendingAmountCents > 0 &&
                              detail.purchase.status != PurchaseStatus.cancelada
                          ? () => _registerPayment(context, ref, detail)
                          : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Pagar'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          detail.payments.isEmpty &&
                              detail.purchase.status != PurchaseStatus.cancelada
                          ? () async {
                              final updated = await context.pushNamed(
                                AppRouteNames.purchaseForm,
                                extra: PurchaseFormArgs(initialDetail: detail),
                              );
                              if (updated == true) {
                                ref.invalidate(
                                  purchaseDetailProvider(purchaseId),
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          detail.purchase.status != PurchaseStatus.cancelada
                          ? () => _cancelPurchase(context, ref, detail)
                          : null,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar compra'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppSectionCard(
                title: 'Falha ao carregar compra',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(purchaseDetailProvider(purchaseId)),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _registerPayment(
    BuildContext context,
    WidgetRef ref,
    PurchaseDetail detail,
  ) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    var selectedMethod = PaymentMethod.cash;

    final submitted = await showDialog<_PaymentDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Registrar pagamento'),
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
                      initialValue: selectedMethod,
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
                          child: Text('Cartao'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => selectedMethod = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observacao',
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
                  onPressed: () => Navigator.of(context).pop(
                    _PaymentDialogResult(
                      amountCents: MoneyParser.parseToCents(
                        amountController.text,
                      ),
                      paymentMethod: selectedMethod,
                      notes: notesController.text,
                    ),
                  ),
                  child: const Text('Registrar'),
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
      await ref
          .read(purchaseRepositoryProvider)
          .registerPayment(
            PurchasePaymentInput(
              purchaseId: detail.purchase.id,
              amountCents: submitted.amountCents,
              paymentMethod: submitted.paymentMethod,
              notes: submitted.notes,
            ),
          );
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(purchaseDetailProvider(detail.purchase.id));
      ref.invalidate(purchaseListProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento registrado com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao registrar pagamento: $error')),
      );
    }
  }

  Future<void> _cancelPurchase(
    BuildContext context,
    WidgetRef ref,
    PurchaseDetail detail,
  ) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar compra'),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo do cancelamento',
              hintText: 'Opcional',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(reasonController.text),
              child: const Text('Confirmar cancelamento'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();

    if (reason == null) {
      return;
    }

    try {
      await ref
          .read(purchaseRepositoryProvider)
          .cancel(detail.purchase.id, reason: reason);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(purchaseDetailProvider(detail.purchase.id));
      ref.invalidate(purchaseListProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compra cancelada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao cancelar compra: $error')),
      );
    }
  }
}

class _PurchaseHeader extends StatelessWidget {
  const _PurchaseHeader({required this.detail});

  final PurchaseDetail detail;

  @override
  Widget build(BuildContext context) {
    final purchase = detail.purchase;
    return AppSectionCard(
      title: purchase.supplierName,
      subtitle:
          'Compra em ${AppFormatters.shortDate(purchase.purchasedAt)}${purchase.dueDate == null ? '' : ' | vence ${AppFormatters.shortDate(purchase.dueDate!)}'}',
      trailing: PurchaseStatusBadge(status: purchase.status),
      child: Column(
        children: [
          if (_shouldShowSyncNotice(purchase)) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: _PurchaseSyncHeaderBadge(),
            ),
            const SizedBox(height: 16),
          ],
          _InfoLine(
            label: 'Valor final',
            value: AppFormatters.currencyFromCents(purchase.finalAmountCents),
          ),
          const Divider(height: 24),
          _InfoLine(
            label: 'Pendente',
            value: AppFormatters.currencyFromCents(purchase.pendingAmountCents),
          ),
          if (purchase.documentNumber?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Documento', value: purchase.documentNumber!),
          ],
          if (purchase.notes?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Observacao', value: purchase.notes!),
          ],
        ],
      ),
    );
  }
}

class _PurchaseSyncNotice extends StatelessWidget {
  const _PurchaseSyncNotice({required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    final label = _noticeLabel(purchase);
    final description = _noticeDescription(purchase);
    final tone =
        purchase.syncStatus == SyncStatus.syncError ||
            purchase.syncStatus == SyncStatus.conflict
        ? AppStatusTone.warning
        : AppStatusTone.info;
    final icon = purchase.syncStatus == SyncStatus.conflict
        ? Icons.warning_amber_rounded
        : purchase.isLocalOnly
        ? Icons.cloud_off_rounded
        : Icons.sync_problem_rounded;
    return AppSectionCard(
      title: 'Sincronizacao',
      subtitle: 'Status remoto desta compra mista.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppStatusBadge(label: label, tone: tone, icon: icon),
          const SizedBox(height: 12),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          if (purchase.syncIssueMessage?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              purchase.syncIssueMessage!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

bool _shouldShowSyncNotice(Purchase purchase) {
  return purchase.isLocalOnly ||
      purchase.syncStatus == SyncStatus.pendingUpload ||
      purchase.syncStatus == SyncStatus.pendingUpdate ||
      purchase.syncStatus == SyncStatus.syncError ||
      purchase.syncStatus == SyncStatus.conflict ||
      (purchase.syncIssueMessage?.trim().isNotEmpty ?? false);
}

class _PurchaseSyncHeaderBadge extends StatelessWidget {
  const _PurchaseSyncHeaderBadge();

  @override
  Widget build(BuildContext context) {
    return const AppStatusBadge(
      label: 'Sync em acompanhamento',
      tone: AppStatusTone.info,
      icon: Icons.sync_problem_rounded,
    );
  }
}

String _noticeLabel(Purchase purchase) {
  if (purchase.isLocalOnly) {
    return 'Compra salva somente localmente';
  }
  return switch (purchase.syncStatus) {
    null => 'Sincronizacao em andamento',
    SyncStatus.pendingUpload => 'Envio remoto pendente',
    SyncStatus.pendingUpdate => 'Atualizacao remota pendente',
    SyncStatus.syncError => 'Falha de sincronizacao',
    SyncStatus.conflict => 'Conflito de sincronizacao',
    _ => 'Sincronizacao em andamento',
  };
}

String _noticeDescription(Purchase purchase) {
  if (purchase.isLocalOnly) {
    return 'Compra com insumo salva localmente. A sincronizacao remota desse tipo de compra sera habilitada em fase futura.';
  }
  return purchase.syncIssueMessage?.trim().isNotEmpty == true
      ? purchase.syncIssueMessage!.trim()
      : 'A compra esta no fluxo normal de sincronizacao e sera reenviada assim que as dependencias remotas estiverem prontas.';
}

class _PurchaseItemRow extends StatelessWidget {
  const _PurchaseItemRow({required this.item});

  final PurchaseItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.itemNameSnapshot} (${item.unitMeasureSnapshot})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _MetaChip(label: 'Tipo', value: item.itemType.label),
            if (item.variantSummary != null)
              _MetaChip(label: 'Variante', value: item.variantSummary!),
            if ((item.variantSkuSnapshot ?? '').trim().isNotEmpty)
              _MetaChip(label: 'SKU', value: item.variantSkuSnapshot!.trim()),
            _MetaChip(
              label: 'Quantidade',
              value: AppFormatters.quantityFromMil(item.quantityMil),
            ),
            _MetaChip(
              label: 'Custo',
              value: AppFormatters.currencyFromCents(item.unitCostCents),
            ),
            _MetaChip(
              label: 'Subtotal',
              value: AppFormatters.currencyFromCents(item.subtotalCents),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final PurchasePayment payment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.paymentMethod.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                AppFormatters.shortDateTime(payment.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (payment.notes?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(payment.notes!),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(payment.amountCents),
          style: Theme.of(context).textTheme.titleMedium,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _PaymentDialogResult {
  const _PaymentDialogResult({
    required this.amountCents,
    required this.paymentMethod,
    required this.notes,
  });

  final int amountCents;
  final PaymentMethod paymentMethod;
  final String notes;
}
