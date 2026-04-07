import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../comprovantes/domain/entities/commercial_receipt_request.dart';
import '../../../comprovantes/presentation/widgets/receipt_action_bar.dart';
import '../../../caixa/presentation/providers/cash_providers.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../fiado/presentation/providers/fiado_providers.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../../vendas/domain/entities/sale_detail.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';
import '../providers/sale_history_providers.dart';

class SaleDetailPage extends ConsumerWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(saleDetailProvider(saleId));
    final cancellationState = ref.watch(cancelSaleControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe da venda')),
      body: detailAsync.when(
        data: (detail) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SaleSummaryCard(detail: detail),
            const SizedBox(height: 16),
            Card(
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
                          ? 'Vendas canceladas não possuem comprovante comercial normal.'
                          : 'Visualize, salve em PDF ou compartilhe o comprovante da venda.',
                    ),
                    const SizedBox(height: 16),
                    ReceiptActionBar(
                      request: CommercialReceiptRequest.sale(
                        saleId: detail.sale.id,
                      ),
                      enabled: detail.sale.status == SaleStatus.active,
                      blockedMessage:
                          'Vendas canceladas não possuem comprovante comercial disponível.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Itens',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    for (final item in detail.items) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.productName} x${item.quantityUnits}',
                            ),
                          ),
                          Text(
                            AppFormatters.currencyFromCents(item.subtotalCents),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            if (cancellationState.hasError) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    cancellationState.error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            if (detail.sale.status == SaleStatus.active) ...[
              const SizedBox(height: 16),
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
                Chip(label: Text(sale.paymentMethod.label)),
                Chip(label: Text(sale.status.label)),
                if (sale.fiadoStatus != null)
                  Chip(label: Text('Fiado: ${sale.fiadoStatus}')),
              ],
            ),
            const SizedBox(height: 12),
            Text('Cliente: ${sale.clientName ?? 'Não informado'}'),
            Text('Data: ${AppFormatters.shortDateTime(sale.soldAt)}'),
            Text('Total: ${AppFormatters.currencyFromCents(sale.finalCents)}'),
            if (sale.saleType == SaleType.fiado && sale.fiadoDueDate != null)
              Text(
                'Vencimento: ${AppFormatters.shortDate(sale.fiadoDueDate!)}',
              ),
            if (sale.notes?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text('Observações: ${sale.notes}'),
            ],
          ],
        ),
      ),
    );
  }
}
