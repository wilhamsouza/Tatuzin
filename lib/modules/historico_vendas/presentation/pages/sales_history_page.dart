import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_record.dart';
import '../providers/sale_history_providers.dart';

class SalesHistoryPage extends ConsumerWidget {
  const SalesHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(saleHistoryListProvider);
    final selectedStatus = ref.watch(saleHistoryStatusFilterProvider);
    final selectedType = ref.watch(saleHistoryTypeFilterProvider);
    final fromDate = ref.watch(saleHistoryFromProvider);
    final toDate = ref.watch(saleHistoryToProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de vendas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por cliente, produto ou cupom',
              ),
              onChanged: (value) {
                ref.read(saleHistorySearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SaleStatus?>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem<SaleStatus?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      for (final status in SaleStatus.values)
                        DropdownMenuItem<SaleStatus?>(
                          value: status,
                          child: Text(status.label),
                        ),
                    ],
                    onChanged: (value) {
                      ref.read(saleHistoryStatusFilterProvider.notifier).state =
                          value;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<SaleType?>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      const DropdownMenuItem<SaleType?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      for (final type in SaleType.values)
                        DropdownMenuItem<SaleType?>(
                          value: type,
                          child: Text(type.label),
                        ),
                    ],
                    onChanged: (value) {
                      ref.read(saleHistoryTypeFilterProvider.notifier).state =
                          value;
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(
                      context,
                      initialValue: fromDate,
                      onSelected: (value) =>
                          ref.read(saleHistoryFromProvider.notifier).state =
                              value,
                    ),
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(
                      fromDate == null
                          ? 'Início'
                          : AppFormatters.shortDate(fromDate),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(
                      context,
                      initialValue: toDate,
                      onSelected: (value) =>
                          ref.read(saleHistoryToProvider.notifier).state =
                              value,
                    ),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      toDate == null ? 'Fim' : AppFormatters.shortDate(toDate),
                    ),
                  ),
                ),
                if (fromDate != null || toDate != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Limpar período',
                    onPressed: () {
                      ref.read(saleHistoryFromProvider.notifier).state = null;
                      ref.read(saleHistoryToProvider.notifier).state = null;
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: salesAsync.when(
              data: (sales) {
                if (sales.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma venda encontrada para os filtros.'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(saleHistoryListProvider);
                    await ref.read(saleHistoryListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: sales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _SaleHistoryTile(sale: sales[index]);
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Falha ao carregar histórico: $error'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime? initialValue,
    required ValueChanged<DateTime?> onSelected,
  }) async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialValue ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5),
    );

    if (selected == null) {
      return;
    }

    onSelected(
      DateTime(
        selected.year,
        selected.month,
        selected.day,
        initialValue?.hour ?? 0,
        initialValue?.minute ?? 0,
      ),
    );
  }
}

class _SaleHistoryTile extends StatelessWidget {
  const _SaleHistoryTile({required this.sale});

  final SaleRecord sale;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(
          AppRouteNames.saleDetail,
          pathParameters: {'saleId': '${sale.id}'},
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cupom ${sale.receiptNumber}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sale.clientName ?? 'Cliente não informado',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        AppFormatters.currencyFromCents(sale.finalCents),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (sale.status == SaleStatus.active)
                        IconButton(
                          tooltip: 'Ver comprovante',
                          onPressed: () => context.pushNamed(
                            AppRouteNames.saleReceipt,
                            pathParameters: {'saleId': '${sale.id}'},
                          ),
                          icon: const Icon(Icons.receipt_long_outlined),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusBadge(
                    label: sale.saleType.label,
                    tone: AppStatusTone.info,
                  ),
                  AppStatusBadge(
                    label: sale.paymentMethod.label,
                    tone: AppStatusTone.neutral,
                  ),
                  AppStatusBadge(
                    label: sale.status.label,
                    tone: sale.status == SaleStatus.active
                        ? AppStatusTone.success
                        : AppStatusTone.danger,
                  ),
                  if (sale.fiadoStatus != null)
                    AppStatusBadge(
                      label: 'Fiado: ${sale.fiadoStatus}',
                      tone: AppStatusTone.warning,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(AppFormatters.shortDateTime(sale.soldAt)),
            ],
          ),
        ),
      ),
    );
  }
}
