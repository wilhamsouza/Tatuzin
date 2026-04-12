import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/operational_order.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';
import '../widgets/order_status_badge.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(operationalOrderSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(operationalOrdersProvider);
    final selectedStatus = ref.watch(operationalOrderStatusFilterProvider);
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos operacionais')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrder(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo pedido'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Painel de operacao',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Busque por numero do pedido, observacao ou nome de item e filtre o fluxo de producao.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  AppInput(
                    controller: _searchController,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Buscar por pedido, observacao ou item',
                    suffixIcon: hasQuery
                        ? IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                    onChanged: (value) {
                      ref
                              .read(
                                operationalOrderSearchQueryProvider.notifier,
                              )
                              .state =
                          value;
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final option = operationalOrderFilterOptions[index];
                return ChoiceChip(
                  label: Text(option.label),
                  selected: selectedStatus == option.status,
                  onSelected: (_) {
                    ref
                            .read(operationalOrderStatusFilterProvider.notifier)
                            .state =
                        option.status;
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: operationalOrderFilterOptions.length,
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasQuery || selectedStatus != null
                                ? 'Nenhum pedido encontrado com os filtros atuais.'
                                : 'Nenhum pedido operacional criado ainda.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => _createOrder(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Criar pedido'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final activeCount = orders
                    .where((order) => !order.order.status.isTerminal)
                    .length;

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(operationalOrdersProvider);
                    await ref.read(operationalOrdersProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: orders.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return AppCard(
                          padding: const EdgeInsets.all(14),
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatBlock(
                                  label: 'Pedidos na tela',
                                  value: '${orders.length}',
                                ),
                              ),
                              Expanded(
                                child: _StatBlock(
                                  label: 'Ativos',
                                  value: '$activeCount',
                                ),
                              ),
                              Expanded(
                                child: _StatBlock(
                                  label: 'Prontos',
                                  value:
                                      '${orders.where((order) => order.order.status == OperationalOrderStatus.ready).length}',
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final summary = orders[index - 1];
                      final order = summary.order;
                      return AppCard(
                        onTap: () {
                          context.pushNamed(
                            AppRouteNames.orderDetail,
                            pathParameters: {'orderId': '${order.id}'},
                          );
                        },
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pedido #${order.id}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      OrderStatusBadge(status: order.status),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _OrderMetaChip(
                                  icon: Icons.layers_rounded,
                                  label:
                                      '${summary.totalUnits} item${summary.totalUnits == 1 ? '' : 's'}',
                                ),
                                _OrderMetaChip(
                                  icon: Icons.payments_outlined,
                                  label: AppFormatters.currencyFromCents(
                                    summary.totalCents,
                                  ),
                                ),
                                _OrderMetaChip(
                                  icon: Icons.update_rounded,
                                  label: AppFormatters.shortDateTime(
                                    order.updatedAt,
                                  ),
                                ),
                                _OrderMetaChip(
                                  icon: Icons.schedule_rounded,
                                  label:
                                      'Tempo ${operationalOrderElapsedLabel(order)}',
                                ),
                              ],
                            ),
                            if (order.notes?.trim().isNotEmpty ?? false) ...[
                              const SizedBox(height: 12),
                              Text(
                                operationalOrderShortNotes(order.notes),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Falha ao carregar pedidos: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrder(BuildContext context, WidgetRef ref) async {
    final notesController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Novo pedido operacional'),
          content: TextField(
            controller: notesController,
            decoration: const InputDecoration(
              labelText: 'Observacao inicial (opcional)',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Criar'),
            ),
          ],
        );
      },
    );

    if (created != true) {
      notesController.dispose();
      return;
    }

    try {
      final id = await ref
          .read(createOperationalOrderControllerProvider.notifier)
          .create(notes: notesController.text);
      if (!context.mounted) {
        return;
      }
      context.pushNamed(
        AppRouteNames.orderDetail,
        pathParameters: {'orderId': '$id'},
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao criar pedido: $error')),
        );
    } finally {
      notesController.dispose();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(operationalOrderSearchQueryProvider.notifier).state = '';
    setState(() {});
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OrderMetaChip extends StatelessWidget {
  const _OrderMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
