import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/routes/route_names.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_summary.dart';
import '../providers/order_print_providers.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';
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
    final selectedStatus = ref.watch(operationalOrderStatusFilterProvider);
    final createState = ref.watch(createOperationalOrderControllerProvider);
    final statusState = ref.watch(operationalOrderStatusControllerProvider);
    final dispatchState = ref.watch(orderKitchenDispatchControllerProvider);
    final reprintState = ref.watch(orderTicketReprintControllerProvider);
    final billingState = ref.watch(operationalOrderBillingControllerProvider);
    final busy =
        createState.isLoading ||
        statusState.isLoading ||
        dispatchState.isLoading ||
        reprintState.isLoading ||
        billingState.isLoading;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Fila de pedidos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : () => _createOrder(context),
        icon: createState.isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_rounded),
        label: const Text('Novo pedido'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppCard(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Painel operacional',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Busque por numero do pedido, cliente ou tipo de atendimento e acompanhe a fila da cozinha sem misturar com faturamento.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  AppInput(
                    controller: _searchController,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Buscar por pedido, cliente ou atendimento',
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
          boardAsync.when(
            data: (board) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OrderStatusTabs(
                selectedStatus: selectedStatus,
                countFor: board.countFor,
                onChanged: (status) {
                  ref
                          .read(operationalOrderStatusFilterProvider.notifier)
                          .state =
                      status;
                },
              ),
            ),
            loading: () => const SizedBox(height: 52),
            error: (_, __) => const SizedBox(height: 52),
          ),
          Expanded(
            child: boardAsync.when(
              data: (board) {
                final orders = board.filterBy(selectedStatus);
                if (orders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasQuery
                                ? 'Nenhum pedido encontrado com os filtros atuais.'
                                : 'Nenhum pedido em ${operationalOrderStatusLabel(selectedStatus).toLowerCase()} agora.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => _createOrder(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Novo pedido'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final failedPrints = board.orders
                    .where(
                      (summary) =>
                          summary.order.ticketMeta.status ==
                          OrderTicketDispatchStatus.failed,
                    )
                    .length;

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(operationalOrderBoardProvider);
                    await ref.read(operationalOrderBoardProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: orders.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                                  label: 'Ativos',
                                  value: '${board.activeCount}',
                                ),
                              ),
                              Expanded(
                                child: _StatBlock(
                                  label: 'Prontos',
                                  value:
                                      '${board.countFor(OperationalOrderStatus.ready)}',
                                ),
                              ),
                              Expanded(
                                child: _StatBlock(
                                  label: 'Falhas ticket',
                                  value: '$failedPrints',
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final summary = orders[index - 1];
                      return OrderQueueCard(
                        summary: summary,
                        onOpen: () => _openOrder(context, summary.order.id),
                        onSendToKitchen: _canSendToKitchen(summary) && !busy
                            ? () => _sendToKitchen(context, summary.order.id)
                            : null,
                        onReprint: _canReprint(summary) && !busy
                            ? () => _reprint(context, summary.order.id)
                            : null,
                        onMarkInPreparation:
                            summary.order.status.canTransitionTo(
                                  OperationalOrderStatus.inPreparation,
                                ) &&
                                !busy
                            ? () => _updateStatus(
                                context,
                                summary.order.id,
                                OperationalOrderStatus.inPreparation,
                              )
                            : null,
                        onMarkReady:
                            summary.order.status.canTransitionTo(
                                  OperationalOrderStatus.ready,
                                ) &&
                                !busy
                            ? () => _updateStatus(
                                context,
                                summary.order.id,
                                OperationalOrderStatus.ready,
                              )
                            : null,
                        onMarkDelivered:
                            summary.order.status.canTransitionTo(
                                  OperationalOrderStatus.delivered,
                                ) &&
                                !busy
                            ? () => _updateStatus(
                                context,
                                summary.order.id,
                                OperationalOrderStatus.delivered,
                              )
                            : null,
                        onInvoice: _canInvoice(summary) && !busy
                            ? () => _invoiceOrder(context, summary.order.id)
                            : null,
                        onCancel: !summary.order.isTerminal && !busy
                            ? () => _confirmCancel(context, summary.order.id)
                            : null,
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

  Future<void> _sendToKitchen(BuildContext context, int orderId) async {
    final result = await ref
        .read(orderKitchenDispatchControllerProvider.notifier)
        .sendToKitchen(orderId);
    if (!context.mounted) {
      return;
    }
    if (result.hasFailure) {
      _showMessage(
        context,
        'Pedido enviado para cozinha, mas a impressao falhou: ${result.failureMessage}',
      );
      return;
    }
    _showMessage(context, 'Pedido enviado para cozinha e ticket impresso.');
  }

  Future<void> _reprint(BuildContext context, int orderId) async {
    final result = await ref
        .read(orderTicketReprintControllerProvider.notifier)
        .reprint(orderId);
    if (!context.mounted) {
      return;
    }
    if (result.hasFailure) {
      _showMessage(
        context,
        'Falha ao reimprimir ticket: ${result.failureMessage}',
      );
      return;
    }
    _showMessage(context, 'Ticket reimpresso com sucesso.');
  }

  Future<void> _updateStatus(
    BuildContext context,
    int orderId,
    OperationalOrderStatus status,
  ) async {
    try {
      await ref
          .read(operationalOrderStatusControllerProvider.notifier)
          .updateStatus(orderId: orderId, status: status);
      if (!context.mounted) {
        return;
      }
      _showMessage(
        context,
        'Pedido atualizado para ${operationalOrderStatusLabel(status)}.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao atualizar pedido: $error');
    }
  }

  Future<void> _confirmCancel(BuildContext context, int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar pedido'),
          content: Text('Deseja cancelar o pedido #$orderId?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancelar pedido'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _updateStatus(context, orderId, OperationalOrderStatus.canceled);
  }

  Future<void> _invoiceOrder(BuildContext context, int orderId) async {
    final detail = await ref.read(
      operationalOrderDetailProvider(orderId).future,
    );
    if (!context.mounted) {
      return;
    }
    if (detail == null) {
      if (context.mounted) {
        _showMessage(context, 'Pedido nao encontrado para faturamento.');
      }
      return;
    }

    final paymentMethod = await _pickImmediatePaymentMethod(context);
    if (paymentMethod == null || !context.mounted) {
      return;
    }

    try {
      final sale = await ref
          .read(operationalOrderBillingControllerProvider.notifier)
          .invoice(detail: detail, paymentMethod: paymentMethod);
      if (!context.mounted) {
        return;
      }
      context.pushNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '${sale.saleId}'},
        extra: true,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao faturar pedido: $error');
    }
  }

  Future<PaymentMethod?> _pickImmediatePaymentMethod(
    BuildContext context,
  ) async {
    return showDialog<PaymentMethod>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Forma de pagamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Dinheiro'),
                onTap: () => Navigator.of(context).pop(PaymentMethod.cash),
              ),
              ListTile(
                title: const Text('Pix'),
                onTap: () => Navigator.of(context).pop(PaymentMethod.pix),
              ),
              ListTile(
                title: const Text('Cartao'),
                onTap: () => Navigator.of(context).pop(PaymentMethod.card),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _canSendToKitchen(OperationalOrderSummary summary) {
    return summary.order.status == OperationalOrderStatus.draft &&
        summary.totalUnits > 0;
  }

  bool _canReprint(OperationalOrderSummary summary) {
    return summary.order.status != OperationalOrderStatus.draft &&
        summary.order.status != OperationalOrderStatus.canceled;
  }

  bool _canInvoice(OperationalOrderSummary summary) {
    return summary.order.status == OperationalOrderStatus.delivered &&
        summary.totalUnits > 0 &&
        !summary.hasLinkedSale;
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
