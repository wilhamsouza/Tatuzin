import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_record.dart';
import '../providers/sale_history_providers.dart';

class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  late final TextEditingController _searchController;
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(saleHistorySearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(saleHistoryListProvider);
    final selectedStatus = ref.watch(saleHistoryStatusFilterProvider);
    final selectedType = ref.watch(saleHistoryTypeFilterProvider);
    final fromDate = ref.watch(saleHistoryFromProvider);
    final toDate = ref.watch(saleHistoryToProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final filtersActive =
        selectedStatus != null ||
        selectedType != null ||
        fromDate != null ||
        toDate != null;
    final canClearSearch = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de vendas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: AppInput(
                    controller: _searchController,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar cliente, cupom ou produto',
                    suffixIcon: canClearSearch
                        ? IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _searchController.clear();
                              ref
                                      .read(
                                        saleHistorySearchQueryProvider.notifier,
                                      )
                                      .state =
                                  '';
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                    onChanged: (value) {
                      ref.read(saleHistorySearchQueryProvider.notifier).state =
                          value;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _filtersExpanded = !_filtersExpanded);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.tune_rounded, size: 18),
                        if (filtersActive)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (filtersActive && !_filtersExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filtros ativos aplicados',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<SaleStatus?>(
                              initialValue: selectedStatus,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                isDense: true,
                              ),
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
                                ref
                                        .read(
                                          saleHistoryStatusFilterProvider
                                              .notifier,
                                        )
                                        .state =
                                    value;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<SaleType?>(
                              initialValue: selectedType,
                              decoration: const InputDecoration(
                                labelText: 'Tipo',
                                isDense: true,
                              ),
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
                                ref
                                        .read(
                                          saleHistoryTypeFilterProvider
                                              .notifier,
                                        )
                                        .state =
                                    value;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(
                                context,
                                initialValue: fromDate,
                                onSelected: (value) =>
                                    ref
                                            .read(
                                              saleHistoryFromProvider.notifier,
                                            )
                                            .state =
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(
                                context,
                                initialValue: toDate,
                                onSelected: (value) =>
                                    ref
                                            .read(
                                              saleHistoryToProvider.notifier,
                                            )
                                            .state =
                                        value,
                              ),
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                toDate == null
                                    ? 'Fim'
                                    : AppFormatters.shortDate(toDate),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (filtersActive) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              ref
                                      .read(
                                        saleHistoryStatusFilterProvider
                                            .notifier,
                                      )
                                      .state =
                                  null;
                              ref
                                      .read(
                                        saleHistoryTypeFilterProvider.notifier,
                                      )
                                      .state =
                                  null;
                              ref.read(saleHistoryFromProvider.notifier).state =
                                  null;
                              ref.read(saleHistoryToProvider.notifier).state =
                                  null;
                            },
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 18,
                            ),
                            label: const Text('Limpar filtros'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            crossFadeState: _filtersExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
          Expanded(
            child: salesAsync.when(
              data: (sales) {
                if (sales.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: AppStateCard(
                      title: 'Nenhuma venda encontrada',
                      message:
                          'Ajuste a busca ou os filtros para localizar outra venda.',
                      compact: true,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(saleHistoryListProvider);
                    await ref.read(saleHistoryListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: sales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _SaleHistoryTile(sale: sales[index]);
                    },
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: AppStateCard(
                  title: 'Carregando histórico',
                  message: 'Buscando vendas do período selecionado.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppStateCard(
                    title: 'Falha ao carregar histórico',
                    message: 'Puxe a tela para atualizar ou tente novamente.',
                    tone: AppStateTone.error,
                    compact: true,
                    actionLabel: 'Tentar novamente',
                    onAction: () => ref.invalidate(saleHistoryListProvider),
                  ),
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
          padding: const EdgeInsets.all(14),
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
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sale.clientName ?? 'Cliente não informado',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppFormatters.shortDateTime(sale.soldAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AppStatusBadge(
                        label: sale.status.label,
                        tone: sale.status == SaleStatus.active
                            ? AppStatusTone.success
                            : AppStatusTone.danger,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AppStatusBadge(
                    label: sale.saleType.label,
                    tone: AppStatusTone.info,
                  ),
                  AppStatusBadge(
                    label: sale.paymentMethod.label,
                    tone: AppStatusTone.neutral,
                  ),
                  if (sale.fiadoStatus != null)
                    AppStatusBadge(
                      label: 'Fiado ${sale.fiadoStatus}',
                      tone: AppStatusTone.warning,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => context.pushNamed(
                      AppRouteNames.saleDetail,
                      pathParameters: {'saleId': '${sale.id}'},
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: const Text('Detalhes'),
                  ),
                  if (sale.status == SaleStatus.active)
                    OutlinedButton.icon(
                      onPressed: () => context.pushNamed(
                        AppRouteNames.saleReceipt,
                        pathParameters: {'saleId': '${sale.id}'},
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text('Comprovante'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
