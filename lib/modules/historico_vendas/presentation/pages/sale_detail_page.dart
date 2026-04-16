import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/routes/route_names.dart';
import '../../../caixa/presentation/providers/cash_providers.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../comprovantes/domain/entities/commercial_receipt_request.dart';
import '../../../comprovantes/presentation/widgets/receipt_action_bar.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../fiado/presentation/providers/fiado_providers.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/sale_detail.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_item_detail.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';
import '../../domain/entities/sale_return.dart';
import '../providers/sale_history_providers.dart';

class SaleDetailPage extends ConsumerWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(saleDetailProvider(saleId));
    final returnsAsync = ref.watch(saleReturnsProvider(saleId));
    final cancellationState = ref.watch(cancelSaleControllerProvider);
    final exchangeState = ref.watch(saleExchangeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe da venda')),
      body: detailAsync.when(
        data: (detail) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SaleSummaryCard(detail: detail),
            const SizedBox(height: 16),
            _ReceiptCard(detail: detail),
            const SizedBox(height: 16),
            _SaleItemsCard(detail: detail),
            const SizedBox(height: 16),
            _SaleReturnsCard(returnsAsync: returnsAsync),
            if (cancellationState.hasError || exchangeState.hasError) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    cancellationState.error?.toString() ??
                        exchangeState.error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            if (detail.sale.status == SaleStatus.active) ...[
              const SizedBox(height: 16),
              if (_hasExchangeableItems(detail.items))
                FilledButton.icon(
                  onPressed: exchangeState.isLoading
                      ? null
                      : () => _openReturnFlow(context, ref, detail),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    exchangeState.isLoading
                        ? 'Registrando troca...'
                        : 'Registrar troca ou devolucao',
                  ),
                ),
              if (_hasExchangeableItems(detail.items))
                const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: cancellationState.isLoading
                    ? null
                    : () => _cancelSale(context, ref, detail),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(
                  cancellationState.isLoading
                      ? 'Cancelando...'
                      : 'Cancelar venda',
                ),
              ),
            ],
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Falha ao carregar a venda: $error'),
          ),
        ),
      ),
    );
  }

  bool _hasExchangeableItems(List<SaleItemDetail> items) {
    return items.any((item) => item.productVariantId != null);
  }

  Future<void> _openReturnFlow(
    BuildContext context,
    WidgetRef ref,
    SaleDetail detail,
  ) async {
    final draft = await showModalBottomSheet<_SaleReturnDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SaleReturnSheet(detail: detail),
    );
    if (draft == null) {
      return;
    }

    try {
      final result = await ref
          .read(saleExchangeControllerProvider.notifier)
          .registerReturn(draft.toInput(detail.sale.id));

      ref.invalidate(saleHistoryListProvider);
      ref.invalidate(saleDetailProvider(detail.sale.id));
      ref.invalidate(saleReturnsProvider(detail.sale.id));
      ref.invalidate(productListProvider);
      ref.invalidate(salesCatalogProvider);
      ref.invalidate(clientListProvider);
      ref.invalidate(currentCashSessionProvider);
      ref.invalidate(currentCashMovementsProvider);
      ref.invalidate(cashSessionHistoryProvider);
      ref.invalidate(fiadoListProvider);
      ref.invalidate(dashboardMetricsProvider);
      if (detail.sale.clientId != null) {
        ref.invalidate(customerCreditBalanceProvider(detail.sale.clientId!));
        ref.invalidate(
          customerCreditTransactionsProvider(detail.sale.clientId!),
        );
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_buildReturnResultMessage(result))),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  String _buildReturnResultMessage(SaleReturnResult result) {
    final segments = <String>['Operacao registrada com sucesso.'];
    if (result.appliedDiscountCents > 0) {
      segments.add(
        'Credito usado na nova venda: ${AppFormatters.currencyFromCents(result.appliedDiscountCents)}.',
      );
    }
    if (result.creditedAmountCents > 0) {
      segments.add(
        'Haver gerado: ${AppFormatters.currencyFromCents(result.creditedAmountCents)}.',
      );
    }
    if (result.refundAmountCents > 0) {
      segments.add(
        'Estorno financeiro: ${AppFormatters.currencyFromCents(result.refundAmountCents)}.',
      );
    }
    if (result.replacementReceiptNumber != null) {
      segments.add('Nova venda: ${result.replacementReceiptNumber}.');
    }
    return segments.join(' ');
  }

  Future<void> _cancelSale(
    BuildContext context,
    WidgetRef ref,
    SaleDetail detail,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar venda'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Motivo obrigatorio'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Confirmar cancelamento'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (confirmed == null || confirmed.trim().isEmpty) {
      return;
    }

    try {
      await ref
          .read(cancelSaleControllerProvider.notifier)
          .cancel(saleId: detail.sale.id, reason: confirmed);
      ref.invalidate(saleHistoryListProvider);
      ref.invalidate(saleDetailProvider(detail.sale.id));
      ref.invalidate(productListProvider);
      ref.invalidate(salesCatalogProvider);
      ref.invalidate(clientListProvider);
      if (detail.sale.clientId != null) {
        ref.invalidate(customerCreditBalanceProvider(detail.sale.clientId!));
        ref.invalidate(
          customerCreditTransactionsProvider(detail.sale.clientId!),
        );
      }
      ref.invalidate(currentCashSessionProvider);
      ref.invalidate(currentCashMovementsProvider);
      ref.invalidate(cashSessionHistoryProvider);
      ref.invalidate(fiadoListProvider);
      ref.invalidate(dashboardMetricsProvider);
      if (detail.sale.fiadoId != null) {
        ref.invalidate(fiadoDetailProvider(detail.sale.fiadoId!));
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda cancelada com sucesso.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }
}

class _SaleSummaryCard extends StatelessWidget {
  const _SaleSummaryCard({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final sale = detail.sale;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cupom ${sale.receiptNumber}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(sale.saleType.label)),
                Chip(label: Text(sale.paymentDisplayLabel)),
                Chip(label: Text(sale.status.label)),
                if (sale.fiadoStatus != null)
                  Chip(label: Text('Fiado: ${sale.fiadoStatus}')),
              ],
            ),
            const SizedBox(height: 12),
            Text('Cliente: ${sale.clientName ?? 'Nao informado'}'),
            Text('Data: ${AppFormatters.shortDateTime(sale.soldAt)}'),
            Text('Total: ${AppFormatters.currencyFromCents(sale.finalCents)}'),
            if (sale.creditUsedCents > 0)
              Text(
                'Haver utilizado: ${AppFormatters.currencyFromCents(sale.creditUsedCents)}',
              ),
            if (sale.creditGeneratedCents > 0)
              Text(
                'Haver gerado: ${AppFormatters.currencyFromCents(sale.creditGeneratedCents)}',
              ),
            if (sale.immediateReceivedCents > 0)
              Text(
                'Recebido agora: ${AppFormatters.currencyFromCents(sale.immediateReceivedCents)}',
              ),
            if (sale.saleType == SaleType.fiado && sale.fiadoDueDate != null)
              Text(
                'Vencimento: ${AppFormatters.shortDate(sale.fiadoDueDate!)}',
              ),
            if (sale.notes?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text('Observacoes: ${sale.notes}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comprovante',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              detail.sale.status == SaleStatus.cancelled
                  ? 'Vendas canceladas nao possuem comprovante comercial normal.'
                  : 'Visualize, salve em PDF ou compartilhe o comprovante da venda.',
            ),
            const SizedBox(height: 16),
            ReceiptActionBar(
              request: CommercialReceiptRequest.sale(saleId: detail.sale.id),
              enabled: detail.sale.status == SaleStatus.active,
              blockedMessage:
                  'Vendas canceladas nao possuem comprovante comercial disponivel.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleItemsCard extends StatelessWidget {
  const _SaleItemsCard({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Itens', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var index = 0; index < detail.items.length; index++) ...[
              _SaleItemRow(item: detail.items[index]),
              if (index < detail.items.length - 1) const Divider(height: 18),
            ],
            if (detail.items.isEmpty)
              Text(
                'Nenhum item encontrado na venda.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SaleItemRow extends StatelessWidget {
  const _SaleItemRow({required this.item});

  final SaleItemDetail item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.quantityUnits} x ${AppFormatters.currencyFromCents(item.unitPriceCents)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (item.variantSummary != null ||
                  (item.variantSkuSnapshot ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (item.variantSummary != null)
                      _InfoPill(label: item.variantSummary!),
                    if ((item.variantSkuSnapshot ?? '').trim().isNotEmpty)
                      _InfoPill(label: 'SKU ${item.variantSkuSnapshot!.trim()}'),
                  ],
                ),
              ],
              if (item.itemNotes?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Text(
                  'Obs.: ${item.itemNotes!}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(item.subtotalCents),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SaleReturnsCard extends StatelessWidget {
  const _SaleReturnsCard({required this.returnsAsync});

  final AsyncValue<List<SaleReturnRecord>> returnsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trocas e devolucoes', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            returnsAsync.when(
              data: (returns) {
                if (returns.isEmpty) {
                  return Text(
                    'Nenhuma troca ou devolucao registrada nesta venda.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < returns.length; index++) ...[
                      _SaleReturnRecordCard(record: returns[index]),
                      if (index < returns.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (error, _) => Text(
                'Falha ao carregar o historico da troca: $error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleReturnRecordCard extends StatelessWidget {
  const _SaleReturnRecordCard({required this.record});

  final SaleReturnRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.mode.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                AppFormatters.shortDateTime(record.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (record.reason?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(
              record.reason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final item in record.items) ...[
            _SaleReturnItemRow(item: item),
            if (item != record.items.last) const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (record.appliedDiscountCents > 0)
                _InfoPill(
                  label:
                      'Usado na nova venda ${AppFormatters.currencyFromCents(record.appliedDiscountCents)}',
                ),
              if (record.creditedAmountCents > 0)
                _InfoPill(
                  label:
                      'Haver ${AppFormatters.currencyFromCents(record.creditedAmountCents)}',
                ),
              if (record.refundAmountCents > 0)
                _InfoPill(
                  label:
                      'Estorno ${AppFormatters.currencyFromCents(record.refundAmountCents)}',
                ),
            ],
          ),
          if (record.replacementSaleId != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.saleDetail,
                  pathParameters: {'saleId': '${record.replacementSaleId}'},
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: Text(
                  record.replacementSaleReceiptNumber == null
                      ? 'Ver nova venda'
                      : 'Ver nova venda ${record.replacementSaleReceiptNumber}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SaleReturnItemRow extends StatelessWidget {
  const _SaleReturnItemRow({required this.item});

  final SaleReturnItemRecord item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.quantityUnits} peca(s) devolvida(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (item.variantSummary != null ||
                  (item.variantSkuSnapshot ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (item.variantSummary != null)
                      _InfoPill(label: item.variantSummary!),
                    if ((item.variantSkuSnapshot ?? '').trim().isNotEmpty)
                      _InfoPill(
                        label: 'SKU ${item.variantSkuSnapshot!.trim()}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppFormatters.currencyFromCents(item.subtotalCents),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SaleReturnSheet extends ConsumerStatefulWidget {
  const _SaleReturnSheet({required this.detail});

  final SaleDetail detail;

  @override
  ConsumerState<_SaleReturnSheet> createState() => _SaleReturnSheetState();
}

class _SaleReturnSheetState extends ConsumerState<_SaleReturnSheet> {
  late final TextEditingController _reasonController;
  late final TextEditingController _searchController;
  SaleReturnMode _mode = SaleReturnMode.returnOnly;
  int? _selectedSaleItemId;
  int _selectedQuantityUnits = 1;
  Product? _selectedReplacementProduct;
  int _replacementQuantityUnits = 1;
  PaymentMethod _replacementPaymentMethod = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _searchController = TextEditingController();
    final firstItem = _eligibleItems.firstOrNull;
    _selectedSaleItemId = firstItem?.id;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<SaleItemDetail> get _eligibleItems => widget.detail.items
      .where((item) => item.productVariantId != null)
      .toList(growable: false);

  SaleItemDetail? get _selectedSaleItem {
    final selectedId = _selectedSaleItemId;
    if (selectedId == null) {
      return null;
    }
    for (final item in _eligibleItems) {
      if (item.id == selectedId) {
        return item;
      }
    }
    return null;
  }

  CartItem? get _replacementCartItem {
    final product = _selectedReplacementProduct;
    if (product == null) {
      return null;
    }
    return CartItem.fromProduct(
      product,
    ).copyWith(quantityMil: _replacementQuantityUnits * 1000);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedSaleItem = _selectedSaleItem;
    final returnedValueCents = selectedSaleItem == null
        ? 0
        : selectedSaleItem.unitPriceCents * _selectedQuantityUnits;
    final replacementItem = _replacementCartItem;
    final replacementValueCents = replacementItem?.subtotalCents ?? 0;
    final differenceCents = replacementValueCents - returnedValueCents;
    final productsAsync = ref.watch(
      saleExchangeProductLookupProvider(_searchController.text),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Troca simples vinculada',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Devolva a peca original e, se quiser, gere a nova venda da troca agora.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: ValueKey('sale-item-${_selectedSaleItemId ?? 'none'}'),
                initialValue: _selectedSaleItemId,
                items: _eligibleItems
                    .map(
                      (item) => DropdownMenuItem<int>(
                        value: item.id,
                        child: Text(
                          item.variantSummary == null
                              ? item.productName
                              : '${item.productName} - ${item.variantSummary}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  setState(() {
                    _selectedSaleItemId = value;
                    _selectedQuantityUnits = 1;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Item original da venda',
                ),
              ),
              const SizedBox(height: 12),
              if (selectedSaleItem != null)
                Row(
                  children: [
                    Expanded(
                      child: _QuantitySelector(
                        label: 'Quantidade devolvida',
                        value: _selectedQuantityUnits,
                        maxValue: selectedSaleItem.quantityUnits,
                        onChanged: (value) {
                          setState(() => _selectedQuantityUnits = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryMetric(
                        label: 'Valor devolvido',
                        value: AppFormatters.currencyFromCents(
                          returnedValueCents,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              SegmentedButton<SaleReturnMode>(
                segments: const [
                  ButtonSegment<SaleReturnMode>(
                    value: SaleReturnMode.returnOnly,
                    label: Text('Devolucao'),
                    icon: Icon(Icons.undo_rounded),
                  ),
                  ButtonSegment<SaleReturnMode>(
                    value: SaleReturnMode.exchangeWithNewSale,
                    label: Text('Troca'),
                    icon: Icon(Icons.swap_horiz_rounded),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) {
                    return;
                  }
                  setState(() {
                    _mode = selection.first;
                    if (_mode == SaleReturnMode.returnOnly) {
                      _selectedReplacementProduct = null;
                      _replacementQuantityUnits = 1;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ex.: cliente trocou o tamanho',
                ),
              ),
              if (_mode == SaleReturnMode.exchangeWithNewSale) ...[
                const SizedBox(height: 16),
                Text(
                  'Nova variante',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Buscar por nome, SKU, cor ou tamanho',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                productsAsync.when(
                  data: (products) {
                    if (products.isEmpty) {
                      return Text(
                        'Nenhuma variante disponivel para a busca informada.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    }

                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: products.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final isSelected =
                              _selectedReplacementProduct?.id == product.id &&
                              _selectedReplacementProduct?.sellableVariantId ==
                                  product.sellableVariantId;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            title: Text(product.displayName),
                            subtitle: Text(
                              [
                                if ((product.sellableVariantSku ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  'SKU ${product.sellableVariantSku}',
                                'Estoque ${product.stockUnits}',
                                AppFormatters.currencyFromCents(
                                  product.salePriceCents,
                                ),
                              ].join(' - '),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedReplacementProduct = product;
                                _replacementQuantityUnits =
                                    _selectedQuantityUnits > product.stockUnits
                                    ? product.stockUnits
                                    : _selectedQuantityUnits;
                                if (_replacementQuantityUnits <= 0) {
                                  _replacementQuantityUnits = 1;
                                }
                              });
                            },
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (error, _) => Text(
                    'Falha ao buscar variantes: $error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
                if (_selectedReplacementProduct != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuantitySelector(
                          label: 'Quantidade da nova peca',
                          value: _replacementQuantityUnits,
                          maxValue: _selectedReplacementProduct!.stockUnits,
                          onChanged: (value) {
                            setState(() => _replacementQuantityUnits = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryMetric(
                          label: 'Nova venda',
                          value: AppFormatters.currencyFromCents(
                            replacementValueCents,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentMethod>(
                    key: ValueKey('payment-${_replacementPaymentMethod.name}'),
                    initialValue: _replacementPaymentMethod,
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
                      if (value == null) {
                        return;
                      }
                      setState(() => _replacementPaymentMethod = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Forma de pagamento da diferenca',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              _ExchangeFinancialHint(
                mode: _mode,
                differenceCents: differenceCents,
                saleHasClient: widget.detail.sale.clientId != null,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Fechar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: selectedSaleItem == null
                          ? null
                          : () => _submit(context),
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    final selectedSaleItem = _selectedSaleItem;
    if (selectedSaleItem == null) {
      return;
    }
    if (_mode == SaleReturnMode.exchangeWithNewSale &&
        _replacementCartItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione a nova variante para concluir a troca.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _SaleReturnDraft(
        mode: _mode,
        reason: _reasonController.text,
        returnedItem: SaleReturnItemInput(
          saleItemId: selectedSaleItem.id,
          quantityMil: _selectedQuantityUnits * 1000,
          reason: _reasonController.text,
        ),
        replacementItems: _replacementCartItem == null
            ? const <CartItem>[]
            : <CartItem>[_replacementCartItem!],
        replacementPaymentMethod: _replacementPaymentMethod,
      ),
    );
  }
}

class _QuantitySelector extends StatelessWidget {
  const _QuantitySelector({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int maxValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeMax = maxValue <= 0 ? 1 : maxValue;
    return DropdownButtonFormField<int>(
      key: ValueKey('$label-$value-$safeMax'),
      initialValue: value > safeMax ? safeMax : value,
      items: List.generate(
        safeMax,
        (index) => DropdownMenuItem<int>(
          value: index + 1,
          child: Text('${index + 1}'),
        ),
      ),
      onChanged: (newValue) {
        if (newValue == null) {
          return;
        }
        onChanged(newValue);
      },
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExchangeFinancialHint extends StatelessWidget {
  const _ExchangeFinancialHint({
    required this.mode,
    required this.differenceCents,
    required this.saleHasClient,
  });

  final SaleReturnMode mode;
  final int differenceCents;
  final bool saleHasClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final message = switch (mode) {
      SaleReturnMode.returnOnly => saleHasClient
          ? 'Sem nova venda: o valor devolvido vira haver do cliente.'
          : 'Sem nova venda: o valor devolvido vira estorno financeiro.',
      SaleReturnMode.exchangeWithNewSale => differenceCents > 0
          ? 'A nova peca ficou mais cara. O sistema vai cobrar apenas a diferenca.'
          : differenceCents < 0
          ? saleHasClient
                ? 'A troca ficou menor. O restante vira haver do cliente.'
                : 'A troca ficou menor. O restante vira estorno financeiro.'
          : 'A troca ficou no mesmo valor. A nova venda sai zerada.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SaleReturnDraft {
  const _SaleReturnDraft({
    required this.mode,
    required this.reason,
    required this.returnedItem,
    required this.replacementItems,
    required this.replacementPaymentMethod,
  });

  final SaleReturnMode mode;
  final String? reason;
  final SaleReturnItemInput returnedItem;
  final List<CartItem> replacementItems;
  final PaymentMethod replacementPaymentMethod;

  SaleReturnInput toInput(int saleId) {
    return SaleReturnInput(
      saleId: saleId,
      mode: mode,
      reason: reason,
      returnedItems: <SaleReturnItemInput>[returnedItem],
      replacementItems: replacementItems,
      replacementPaymentMethod: replacementPaymentMethod,
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
