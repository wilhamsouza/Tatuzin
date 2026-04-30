import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_summary_block.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
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
    final layout = context.appLayout;
    final tokens = context.appColors;
    final busy =
        createState.isLoading ||
        statusState.isLoading ||
        dispatchState.isLoading ||
        reprintState.isLoading ||
        billingState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Fila de pedidos')),
      drawer: const AppMainDrawer(),
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
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space6,
              layout.pagePadding,
              layout.space4,
            ),
            child: const AppPageHeader(
              title: 'Painel operacional',
              subtitle: operationalOrderPanelSubtitle,
              badgeLabel: 'Pedidos',
              badgeIcon: Icons.receipt_long_rounded,
              emphasized: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Buscar por pedido, cliente ou atendimento',
              onChanged: (value) {
                ref.read(operationalOrderSearchQueryProvider.notifier).state =
                    value;
                setState(() {});
              },
              onClear: _clearSearch,
            ),
          ),
          boardAsync.when(
            data: (board) => Padding(
              padding: EdgeInsets.only(bottom: layout.space4),
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
            loading: () => SizedBox(height: layout.quickActionHeight + 12),
            error: (_, __) => SizedBox(height: layout.quickActionHeight + 12),
          ),
          Expanded(
            child: boardAsync.when(
              data: (board) {
                final orders = board.filterBy(selectedStatus);
                final failedPrints = board.orders
                    .where(
                      (summary) =>
                          summary.order.ticketMeta.status ==
                          OrderTicketDispatchStatus.failed,
                    )
                    .length;

                if (orders.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      layout.space4,
                      layout.pagePadding,
                      100,
                    ),
                    child: AppStateCard(
                      title: 'Nenhum pedido nessa fila',
                      message: _emptyMessage(selectedStatus),
                      tone: AppStateTone.neutral,
                      actionLabel: busy ? null : 'Novo pedido',
                      onAction: busy ? null : () => _createOrder(context),
                    ),
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
                      layout.space2,
                      layout.pagePadding,
                      100,
                    ),
                    children: [
                      AppSectionCard(
                        title: 'Resumo da fila',
                        subtitle: 'Visao rapida do que esta rodando agora.',
                        tone: AppCardTone.muted,
                        child: GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: layout.gridGap,
                          mainAxisSpacing: layout.gridGap,
                          childAspectRatio: 0.98,
                          children: [
                            AppSummaryBlock(
                              label: 'Ativos',
                              value: '${board.activeCount}',
                              caption: 'Pedidos nao encerrados',
                              icon: Icons.play_circle_outline_rounded,
                              palette: tokens.info,
                              compact: true,
                            ),
                            AppSummaryBlock(
                              label: 'Prontos para retirada',
                              value:
                                  '${board.countFor(OperationalOrderStatus.ready)}',
                              caption: 'Aguardando retirada ou entrega',
                              icon: Icons.notifications_active_rounded,
                              palette: tokens.success,
                              compact: true,
                            ),
                            AppSummaryBlock(
                              label: operationalOrderReceiptFailureSummaryLabel,
                              value: '$failedPrints',
                              caption: 'Requer atencao',
                              icon: Icons.print_disabled_outlined,
                              palette: failedPrints > 0
                                  ? tokens.danger
                                  : tokens.interactive,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: layout.sectionGap),
                      for (var index = 0; index < orders.length; index++) ...[
                        OrderQueueCard(
                          summary: orders[index],
                          onOpen: () =>
                              _openOrder(context, orders[index].order.id),
                          onSendToKitchen:
                              _canSendToKitchen(orders[index]) && !busy
                              ? () => _sendToKitchen(
                                  context,
                                  orders[index].order.id,
                                )
                              : null,
                          onReprint: _canReprint(orders[index]) && !busy
                              ? () => _reprint(context, orders[index].order.id)
                              : null,
                          onMarkInPreparation:
                              orders[index].order.status.canTransitionTo(
                                    OperationalOrderStatus.inPreparation,
                                  ) &&
                                  !busy
                              ? () => _updateStatus(
                                  context,
                                  orders[index].order.id,
                                  OperationalOrderStatus.inPreparation,
                                )
                              : null,
                          onMarkReady:
                              orders[index].order.status.canTransitionTo(
                                    OperationalOrderStatus.ready,
                                  ) &&
                                  !busy
                              ? () => _updateStatus(
                                  context,
                                  orders[index].order.id,
                                  OperationalOrderStatus.ready,
                                )
                              : null,
                          onMarkDelivered:
                              orders[index].order.status.canTransitionTo(
                                    OperationalOrderStatus.delivered,
                                  ) &&
                                  !busy
                              ? () => _updateStatus(
                                  context,
                                  orders[index].order.id,
                                  OperationalOrderStatus.delivered,
                                )
                              : null,
                          onInvoice: _canInvoice(orders[index]) && !busy
                              ? () => _invoiceOrder(
                                  context,
                                  orders[index].order.id,
                                )
                              : null,
                          onCancel: !orders[index].order.isTerminal && !busy
                              ? () => _confirmCancel(
                                  context,
                                  orders[index].order.id,
                                )
                              : null,
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

  String _emptyMessage(OperationalOrderStatus selectedStatus) {
    if (_searchController.text.trim().isNotEmpty) {
      return 'A busca atual nao encontrou pedidos com esse filtro.';
    }
    return 'Nenhum pedido em ${operationalOrderStatusLabel(selectedStatus).toLowerCase()} agora.';
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
    try {
      final result = await ref
          .read(orderKitchenDispatchControllerProvider.notifier)
          .sendToKitchen(orderId);
      if (!context.mounted) {
        return;
      }
      if (result.hasFailure) {
        _showMessage(
          context,
          '$operationalOrderSendFailureMessagePrefix ${result.failureMessage}',
        );
        return;
      }
      _showMessage(context, operationalOrderSendSuccessMessage);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao enviar pedido para separacao: $error');
    }
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
        '$operationalOrderReprintFailureMessagePrefix ${result.failureMessage}',
      );
      return;
    }
    _showMessage(context, operationalOrderReprintSuccessMessage);
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
      _showMessage(context, 'Pedido nao encontrado para faturamento.');
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
