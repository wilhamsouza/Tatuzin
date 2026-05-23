import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_summary.dart';
import '../providers/order_providers.dart';
import '../widgets/order_queue_card.dart';
import '../widgets/order_status_tabs.dart';

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
    final boardAsync = ref.watch(operationalOrderBoardProvider);
    final selectedFilter = ref.watch(operationalOrderStatusFilterProvider);
    final createState = ref.watch(createOperationalOrderControllerProvider);
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: [
          TextButton.icon(
            onPressed: createState.isLoading
                ? null
                : () => _createOrder(context),
            icon: createState.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text('Novo'),
          ),
        ],
      ),
      drawer: const AppMainDrawer(),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space4,
              layout.pagePadding,
              layout.space3,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Buscar pedido ou cliente',
              onChanged: (value) {
                ref.read(operationalOrderSearchQueryProvider.notifier).state =
                    value;
                setState(() {});
              },
              onClear: _clearSearch,
            ),
          ),
          boardAsync.when(
            data: (board) => OrderStatusTabs(
              selectedFilter: selectedFilter,
              countFor: board.countForListFilter,
              onChanged: (filter) {
                ref.read(operationalOrderStatusFilterProvider.notifier).state =
                    filter;
              },
            ),
            loading: () => const SizedBox(height: 48),
            error: (_, __) => const SizedBox(height: 48),
          ),
          Expanded(
            child: boardAsync.when(
              data: (board) {
                final orders = board.filterByListFilter(selectedFilter);
                if (orders.isEmpty) {
                  return _OrdersEmptyState(
                    selectedFilter: selectedFilter,
                    hasSearch: _searchController.text.trim().isNotEmpty,
                    onCreate: createState.isLoading
                        ? null
                        : () => _createOrder(context),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(operationalOrderBoardProvider);
                    await ref.read(operationalOrderBoardProvider.future);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      layout.space3,
                      layout.pagePadding,
                      96,
                    ),
                    children: [
                      for (var index = 0; index < orders.length; index++) ...[
                        OrderQueueCard(
                          summary: orders[index],
                          onOpen: () =>
                              _openOrder(context, orders[index].order.id),
                          primaryActionLabel:
                              operationalOrderListPrimaryActionLabel(
                                orders[index],
                              ),
                          primaryActionIcon:
                              operationalOrderListPrimaryActionIcon(
                                orders[index],
                              ),
                          onPrimaryAction: () =>
                              _runOrderPrimaryAction(context, orders[index]),
                        ),
                        if (index != orders.length - 1)
                          SizedBox(height: layout.blockGap),
                      ],
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding + layout.space4),
                child: AppStateCard(
                  title: 'Falha ao carregar pedidos',
                  message: '$error',
                  tone: AppStateTone.error,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(operationalOrderBoardProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrder(BuildContext context) async {
    try {
      final id = await ref
          .read(createOperationalOrderControllerProvider.notifier)
          .createDraft();
      if (!context.mounted) {
        return;
      }
      _openOrder(context, id);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao criar pedido: $error');
    }
  }

  void _openOrder(BuildContext context, int orderId) {
    context.pushNamed(
      AppRouteNames.orderDetail,
      pathParameters: {'orderId': '$orderId'},
    );
  }

  void _runOrderPrimaryAction(
    BuildContext context,
    OperationalOrderSummary summary,
  ) {
    final linkedSaleId = summary.linkedSaleId;
    if (summary.order.status == OperationalOrderStatus.delivered &&
        linkedSaleId != null) {
      context.pushNamed(
        AppRouteNames.saleDetail,
        pathParameters: {'saleId': '$linkedSaleId'},
      );
      return;
    }
    _openOrder(context, summary.order.id);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(operationalOrderSearchQueryProvider.notifier).state = '';
    setState(() {});
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OrdersEmptyState extends StatelessWidget {
  const _OrdersEmptyState({
    required this.selectedFilter,
    required this.hasSearch,
    required this.onCreate,
  });

  final OperationalOrderListFilter selectedFilter;
  final bool hasSearch;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.space4,
        layout.pagePadding,
        100,
      ),
      child: AppStateCard(
        title: 'Nenhum pedido encontrado',
        message: hasSearch
            ? 'A busca atual nao encontrou pedidos com esse filtro.'
            : _emptyMessage(selectedFilter),
        tone: AppStateTone.neutral,
        actionLabel: onCreate == null ? null : 'Novo pedido',
        onAction: onCreate,
      ),
    );
  }

  String _emptyMessage(OperationalOrderListFilter filter) {
    switch (filter) {
      case OperationalOrderListFilter.all:
        return 'Crie o primeiro pedido para separar as pecas antes da venda.';
      case OperationalOrderListFilter.pending:
        return 'Nao ha pedidos pendentes ou abertos agora.';
      case OperationalOrderListFilter.separation:
        return 'Nao ha pedidos em separacao agora.';
      case OperationalOrderListFilter.fiado:
        return 'Fiado continua no modulo proprio; pedidos ainda nao guardam essa informacao.';
      case OperationalOrderListFilter.completed:
        return 'Nenhum pedido vendido nesse filtro.';
      case OperationalOrderListFilter.canceled:
        return 'Nenhum pedido cancelado nesse filtro.';
    }
  }
}
