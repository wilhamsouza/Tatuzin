import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_detail.dart';
import '../providers/order_print_providers.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';
import '../widgets/operational_order_item_card.dart';
import '../widgets/order_item_editor_sheet.dart';
import '../widgets/order_progress_stepper.dart';
import '../widgets/order_status_badge.dart';
import 'order_ticket_preview_page.dart';

class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  late final TextEditingController _customerController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;
  OperationalOrderServiceType _serviceType =
      OperationalOrderServiceType.counter;
  String? _syncedVersion;
  bool _headerDirty = false;
  bool _notesDirty = false;

  @override
  void initState() {
    super.initState();
    _customerController = TextEditingController();
    _phoneController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(
      operationalOrderDetailProvider(widget.orderId),
    );
    final draftState = ref.watch(operationalOrderDraftControllerProvider);
    final itemState = ref.watch(operationalOrderItemControllerProvider);
    final statusState = ref.watch(operationalOrderStatusControllerProvider);
    final dispatchState = ref.watch(orderKitchenDispatchControllerProvider);
    final reprintState = ref.watch(orderTicketReprintControllerProvider);
    final billingState = ref.watch(operationalOrderBillingControllerProvider);
    final busy =
        draftState.isLoading ||
        itemState.isLoading ||
        statusState.isLoading ||
        dispatchState.isLoading ||
        reprintState.isLoading ||
        billingState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.maybeWhen(
          data: (detail) => Text(
            detail?.order.status == OperationalOrderStatus.draft
                ? 'Novo pedido'
                : 'Pedido #${widget.orderId}',
          ),
          orElse: () => Text('Pedido #${widget.orderId}'),
        ),
        actions: [
          IconButton(
            tooltip: operationalOrderSeparationModeLabel,
            onPressed: () {
              context.pushNamed(
                AppRouteNames.orderKitchen,
                pathParameters: {'orderId': '${widget.orderId}'},
              );
            },
            icon: const Icon(Icons.inventory_2_rounded),
          ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Pedido nao encontrado.'));
          }

          _syncDraftFields(detail);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              _buildHeaderSection(context, detail, busy),
              const SizedBox(height: 12),
              _buildItemsSection(context, detail, busy),
              const SizedBox(height: 12),
              _buildPaymentDeliverySection(context, detail),
              const SizedBox(height: 12),
              _buildNotesSection(context, detail, busy),
              const SizedBox(height: 12),
              _buildSummarySection(context, detail),
              const SizedBox(height: 12),
              _buildHistorySection(context, detail),
              const SizedBox(height: 12),
              _buildActionsSection(context, detail, busy),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Falha ao carregar pedido: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(
                    operationalOrderDetailProvider(widget.orderId),
                  ),
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

  Widget _buildHeaderSection(
    BuildContext context,
    OperationalOrderDetail detail,
    bool busy,
  ) {
    final order = detail.order;
    final editingEnabled = !order.isTerminal;

    return AppSectionCard(
      title: 'Pedido #${order.id}',
      subtitle:
          '${AppFormatters.shortDateTime(order.createdAt)} | ${operationalOrderServiceTypeLabel(order.serviceType)}',
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
                      order.customerLabel,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OrderStatusBadge(status: order.status),
                        AppStatusBadge(
                          label: orderTicketDispatchStatusLabel(
                            order.ticketMeta.status,
                          ),
                          tone: orderTicketDispatchStatusTone(
                            order.ticketMeta.status,
                          ),
                          icon: orderTicketDispatchStatusIcon(
                            order.ticketMeta.status,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppFormatters.currencyFromCents(detail.totalCents),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.schedule_rounded,
                label: 'Criado ${AppFormatters.shortDateTime(order.createdAt)}',
              ),
              _InfoChip(
                icon: Icons.timelapse_rounded,
                label: 'Tempo ${operationalOrderElapsedLabel(order)}',
              ),
              _InfoChip(
                icon: operationalOrderServiceTypeIcon(order.serviceType),
                label: operationalOrderServiceTypeLabel(order.serviceType),
              ),
              if (order.customerPhone?.trim().isNotEmpty ?? false)
                _InfoChip(
                  icon: Icons.phone_rounded,
                  label: order.customerPhone!.trim(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OperationalOrderServiceType.values
                  .map(
                    (serviceType) => Padding(
                      padding: EdgeInsets.only(
                        right:
                            serviceType ==
                                OperationalOrderServiceType.values.last
                            ? 0
                            : 8,
                      ),
                      child: ChoiceChip(
                        avatar: Icon(
                          operationalOrderServiceTypeIcon(serviceType),
                          size: 18,
                        ),
                        label: Text(
                          operationalOrderServiceTypeLabel(serviceType),
                          softWrap: false,
                          overflow: TextOverflow.fade,
                        ),
                        selected: _serviceType == serviceType,
                        onSelected: editingEnabled && !busy
                            ? (_) {
                                setState(() {
                                  _serviceType = serviceType;
                                  _headerDirty = true;
                                });
                              }
                            : null,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _customerController,
            enabled: editingEnabled && !busy,
            labelText: 'Cliente ou identificador',
            hintText: 'Ex.: Ana, retirada Joao, Mesa 08',
            onChanged: (_) => setState(() => _headerDirty = true),
          ),
          const SizedBox(height: 10),
          AppInput(
            controller: _phoneController,
            enabled: editingEnabled && !busy,
            labelText: 'Telefone (opcional)',
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _headerDirty = true),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: editingEnabled && !busy && _headerDirty
                  ? () => _saveDraft(context, showFeedback: true)
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _headerDirty ? 'Salvar cabecalho' : 'Cabecalho salvo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(
    BuildContext context,
    OperationalOrderDetail detail,
    bool busy,
  ) {
    return AppSectionCard(
      title: 'Itens do pedido',
      subtitle: detail.items.isEmpty
          ? 'Busque um produto, escolha variacao e quantidade.'
          : '${detail.lineItemsCount} produto(s) | ${detail.totalUnits} peca(s)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: detail.order.allowsItemChanges && !busy
                  ? () => _addItem(context)
                  : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar produto'),
            ),
          ),
          const SizedBox(height: 12),
          if (detail.items.isEmpty)
            const Text('Nenhum item adicionado ainda.')
          else
            ...detail.items.map(
              (itemDetail) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OperationalOrderItemCard(
                  itemDetail: itemDetail,
                  onEdit: detail.order.allowsItemChanges && !busy
                      ? () => _editItem(context, itemDetail)
                      : null,
                  onRemove: detail.order.allowsItemChanges && !busy
                      ? () => _removeItem(context, itemDetail)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(
    BuildContext context,
    OperationalOrderDetail detail,
    bool busy,
  ) {
    return AppSectionCard(
      title: 'Observacao geral',
      subtitle: 'Recado opcional para separar ou entregar o pedido.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppInput(
            controller: _notesController,
            enabled: !detail.order.isTerminal && !busy,
            labelText: 'Observacao geral do pedido',
            minLines: 3,
            maxLines: 4,
            onChanged: (_) => setState(() => _notesDirty = true),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: !detail.order.isTerminal && !busy && _notesDirty
                  ? () => _saveDraft(context, showFeedback: true)
                  : null,
              icon: const Icon(Icons.notes_rounded),
              label: Text(
                _notesDirty ? 'Salvar observacao' : 'Observacao salva',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDeliverySection(
    BuildContext context,
    OperationalOrderDetail detail,
  ) {
    final order = detail.order;

    return AppSectionCard(
      title: 'Atendimento',
      subtitle: 'Somente os dados que o pedido ja guarda hoje.',
      child: Column(
        children: [
          _SummaryRow(
            label: 'Canal',
            value: operationalOrderServiceTypeLabel(order.serviceType),
          ),
          _SummaryRow(label: 'Cliente', value: order.customerLabel),
          if (order.customerPhone?.trim().isNotEmpty ?? false)
            _SummaryRow(label: 'Contato', value: order.customerPhone!.trim()),
        ],
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context,
    OperationalOrderDetail detail,
  ) {
    final order = detail.order;

    return AppSectionCard(
      title: 'Total',
      subtitle: 'Resumo dos produtos deste pedido.',
      child: Column(
        children: [
          _SummaryRow(label: 'Produtos', value: '${detail.lineItemsCount}'),
          _SummaryRow(label: 'Pecas', value: '${detail.totalUnits}'),
          _SummaryRow(
            label: 'Total do pedido',
            value: AppFormatters.currencyFromCents(detail.totalCents),
            emphasize: true,
          ),
          if (detail.linkedSaleId != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  context.pushNamed(
                    AppRouteNames.saleReceipt,
                    pathParameters: {'saleId': '${detail.linkedSaleId}'},
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text('Abrir venda #${detail.linkedSaleId}'),
              ),
            ),
          ],
          if (order.ticketMeta.hasFailure) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                order.ticketMeta.lastFailureMessage ??
                    'Falha ao imprimir comprovante.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    OperationalOrderDetail detail,
  ) {
    final order = detail.order;
    final events = <_HistoryEvent>[
      _HistoryEvent('Criado', order.createdAt, true),
      _HistoryEvent(
        'Confirmado',
        order.sentToKitchenAt,
        order.sentToKitchenAt != null,
      ),
      _HistoryEvent(
        'Em separacao',
        order.preparationStartedAt,
        order.preparationStartedAt != null,
      ),
      _HistoryEvent('Separado', order.readyAt, order.readyAt != null),
      _HistoryEvent('Concluido', order.deliveredAt, order.deliveredAt != null),
      if (order.canceledAt != null)
        _HistoryEvent('Cancelado', order.canceledAt, true),
    ];

    return AppSectionCard(
      title: 'Historico',
      subtitle: 'Linha do tempo simples do pedido.',
      child: Column(
        children: [
          for (var index = 0; index < events.length; index++) ...[
            _HistoryRow(event: events[index]),
            if (index != events.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsSection(
    BuildContext context,
    OperationalOrderDetail detail,
    bool busy,
  ) {
    final primary = _primaryActionFor(detail);
    final canPrint =
        detail.order.status != OperationalOrderStatus.draft &&
        detail.order.status != OperationalOrderStatus.canceled;

    return AppSectionCard(
      title: 'Proximo passo',
      subtitle: 'Uma acao principal por vez; o restante fica em apoio.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderProgressStepper(status: detail.order.status),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: primary == null || busy ? null : primary.onPressed,
              icon: Icon(primary?.icon ?? Icons.check_rounded),
              label: Text(primary?.label ?? 'Pedido encerrado'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: (!busy && (_headerDirty || _notesDirty))
                    ? () => _saveDraft(context, showFeedback: true)
                    : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar alteracoes'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openTicketPreview(context),
                icon: const Icon(Icons.preview_rounded),
                label: const Text('Gerar lista'),
              ),
              OutlinedButton.icon(
                onPressed: canPrint && !busy ? () => _reprint(context) : null,
                icon: const Icon(Icons.print_rounded),
                label: const Text('Imprimir'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  context.pushNamed(
                    AppRouteNames.orderKitchen,
                    pathParameters: {'orderId': '${widget.orderId}'},
                  );
                },
                icon: const Icon(Icons.inventory_2_rounded),
                label: const Text(operationalOrderSeparationListLabel),
              ),
              if (!detail.order.isTerminal)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _confirmCancel(context),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('Cancelar pedido'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  _OrderPrimaryAction? _primaryActionFor(OperationalOrderDetail detail) {
    final order = detail.order;
    if (detail.linkedSaleId != null) {
      return _OrderPrimaryAction(
        label: 'Ver venda vinculada',
        icon: Icons.receipt_long_rounded,
        onPressed: () {
          context.pushNamed(
            AppRouteNames.saleReceipt,
            pathParameters: {'saleId': '${detail.linkedSaleId}'},
          );
        },
      );
    }
    switch (order.status) {
      case OperationalOrderStatus.draft:
        return _OrderPrimaryAction(
          label: 'Confirmar pedido',
          icon: Icons.check_rounded,
          onPressed: detail.hasItems ? () => _sendToKitchen(context) : null,
        );
      case OperationalOrderStatus.open:
        return _OrderPrimaryAction(
          label: 'Enviar para separacao',
          icon: Icons.inventory_2_rounded,
          onPressed: () =>
              _updateStatus(context, OperationalOrderStatus.inPreparation),
        );
      case OperationalOrderStatus.inPreparation:
        return _OrderPrimaryAction(
          label: 'Marcar separado',
          icon: Icons.check_circle_rounded,
          onPressed: () => _updateStatus(context, OperationalOrderStatus.ready),
        );
      case OperationalOrderStatus.ready:
        return _OrderPrimaryAction(
          label: 'Finalizar venda',
          icon: Icons.point_of_sale_rounded,
          onPressed: detail.hasItems
              ? () => _finishReadyOrderAsSale(context, detail)
              : null,
        );
      case OperationalOrderStatus.delivered:
        return _OrderPrimaryAction(
          label: 'Finalizar venda',
          icon: Icons.point_of_sale_rounded,
          onPressed: detail.order.canBeInvoiced && detail.hasItems
              ? () => _invoice(context, detail)
              : null,
        );
      case OperationalOrderStatus.canceled:
        return null;
    }
  }

  void _syncDraftFields(OperationalOrderDetail detail) {
    final version = detail.order.updatedAt.toIso8601String();
    if (_syncedVersion == version) {
      return;
    }

    if (!_headerDirty) {
      _serviceType = detail.order.serviceType;
      _customerController.text = detail.order.customerIdentifier ?? '';
      _phoneController.text = detail.order.customerPhone ?? '';
    }
    if (!_notesDirty) {
      _notesController.text = detail.order.notes ?? '';
    }
    _syncedVersion = version;
  }

  Future<void> _addItem(BuildContext context) async {
    final result = await showModalBottomSheet<OrderItemEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const OrderItemEditorSheet(),
    );
    if (result == null) {
      return;
    }

    try {
      await ref
          .read(operationalOrderItemControllerProvider.notifier)
          .addItemWithModifiers(
            orderId: widget.orderId,
            productId: result.productId,
            baseProductId: result.baseProductId,
            productVariantId: result.productVariantId,
            variantSkuSnapshot: result.variantSkuSnapshot,
            variantColorSnapshot: result.variantColorSnapshot,
            variantSizeSnapshot: result.variantSizeSnapshot,
            productName: result.productName,
            unitPriceCents: result.unitPriceCents,
            quantityUnits: result.quantityUnits,
            notes: result.notes,
            modifiers: result.modifiers,
          );
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Item adicionado ao pedido.');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao adicionar item: $error');
    }
  }

  Future<void> _editItem(
    BuildContext context,
    OperationalOrderItemDetail itemDetail,
  ) async {
    final result = await showModalBottomSheet<OrderItemEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OrderItemEditorSheet(
        seed: OrderItemEditorSeed(
          orderItemId: itemDetail.item.id,
          productId: itemDetail.item.productId,
          baseProductId: itemDetail.item.baseProductId,
          productVariantId: itemDetail.item.productVariantId,
          variantSkuSnapshot: itemDetail.item.variantSkuSnapshot,
          variantColorSnapshot: itemDetail.item.variantColorSnapshot,
          variantSizeSnapshot: itemDetail.item.variantSizeSnapshot,
          productName: itemDetail.item.productNameSnapshot,
          unitPriceCents: itemDetail.item.unitPriceCents,
          quantityUnits: itemDetail.quantityUnits,
          notes: itemDetail.item.notes,
          selectedModifierOptionIds: itemDetail.modifiers
              .map((modifier) => modifier.modifierOptionId)
              .whereType<int>()
              .toSet(),
        ),
      ),
    );
    if (result == null) {
      return;
    }
    try {
      await ref
          .read(operationalOrderItemControllerProvider.notifier)
          .updateItemWithModifiers(
            orderId: widget.orderId,
            orderItemId: itemDetail.item.id,
            productId: result.productId,
            baseProductId: result.baseProductId,
            productVariantId: result.productVariantId,
            variantSkuSnapshot: result.variantSkuSnapshot,
            variantColorSnapshot: result.variantColorSnapshot,
            variantSizeSnapshot: result.variantSizeSnapshot,
            productName: result.productName,
            unitPriceCents: result.unitPriceCents,
            quantityUnits: result.quantityUnits,
            notes: result.notes,
            modifiers: result.modifiers,
          );
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Item atualizado.');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao atualizar item: $error');
    }
  }

  Future<void> _removeItem(
    BuildContext context,
    OperationalOrderItemDetail itemDetail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover item'),
          content: Text(
            'Remover ${itemDetail.item.productNameSnapshot} do pedido?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(operationalOrderItemControllerProvider.notifier)
          .removeItem(orderId: widget.orderId, orderItemId: itemDetail.item.id);
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Item removido.');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Falha ao remover item: $error');
    }
  }

  Future<bool> _saveDraft(
    BuildContext context, {
    required bool showFeedback,
  }) async {
    try {
      await ref
          .read(operationalOrderDraftControllerProvider.notifier)
          .save(
            orderId: widget.orderId,
            serviceType: _serviceType,
            customerIdentifier: _cleanNullable(_customerController.text),
            customerPhone: _cleanNullable(_phoneController.text),
            notes: _cleanNullable(_notesController.text),
          );
      if (!mounted || !context.mounted) {
        return false;
      }
      setState(() {
        _headerDirty = false;
        _notesDirty = false;
      });
      if (showFeedback) {
        _showMessage(context, 'Rascunho atualizado.');
      }
      return true;
    } catch (error) {
      if (!mounted || !context.mounted) {
        return false;
      }
      _showMessage(context, 'Falha ao salvar rascunho: $error');
      return false;
    }
  }

  Future<bool> _persistDraftIfNeeded(BuildContext context) async {
    if (!_headerDirty && !_notesDirty) {
      return true;
    }
    return _saveDraft(context, showFeedback: false);
  }

  Future<void> _sendToKitchen(BuildContext context) async {
    if (!await _persistDraftIfNeeded(context)) {
      return;
    }

    try {
      final result = await ref
          .read(orderKitchenDispatchControllerProvider.notifier)
          .sendToKitchen(widget.orderId);
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

  Future<void> _reprint(BuildContext context) async {
    try {
      final result = await ref
          .read(orderTicketReprintControllerProvider.notifier)
          .reprint(widget.orderId);
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
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(
        context,
        '$operationalOrderReprintFailureMessagePrefix $error',
      );
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    OperationalOrderStatus status,
  ) async {
    if (!await _persistDraftIfNeeded(context)) {
      return;
    }

    try {
      await ref
          .read(operationalOrderStatusControllerProvider.notifier)
          .updateStatus(orderId: widget.orderId, status: status);
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

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar pedido'),
          content: const Text(
            'Deseja cancelar este pedido? O fluxo operacional sera encerrado.',
          ),
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
    await _updateStatus(context, OperationalOrderStatus.canceled);
  }

  Future<void> _invoice(
    BuildContext context,
    OperationalOrderDetail detail,
  ) async {
    if (!await _persistDraftIfNeeded(context)) {
      return;
    }
    if (!context.mounted) {
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

  Future<void> _finishReadyOrderAsSale(
    BuildContext context,
    OperationalOrderDetail detail,
  ) async {
    if (!await _persistDraftIfNeeded(context)) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final paymentMethod = await _pickImmediatePaymentMethod(context);
    if (paymentMethod == null || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(operationalOrderStatusControllerProvider.notifier)
          .updateStatus(
            orderId: widget.orderId,
            status: OperationalOrderStatus.delivered,
          );
      final refreshed = await ref.read(
        operationalOrderDetailProvider(widget.orderId).future,
      );
      if (!context.mounted) {
        return;
      }
      if (refreshed == null) {
        _showMessage(context, 'Pedido nao encontrado para faturamento.');
        return;
      }
      final sale = await ref
          .read(operationalOrderBillingControllerProvider.notifier)
          .invoice(detail: refreshed, paymentMethod: paymentMethod);
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
      _showMessage(context, 'Falha ao finalizar venda: $error');
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

  void _openTicketPreview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderTicketPreviewPage(orderId: widget.orderId),
      ),
    );
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
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

class _OrderPrimaryAction {
  const _OrderPrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class _HistoryEvent {
  const _HistoryEvent(this.label, this.dateTime, this.done);

  final String label;
  final DateTime? dateTime;
  final bool done;
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});

  final _HistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = event.done
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.55);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(Icons.circle, size: 10, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            event.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: event.done ? null : colorScheme.onSurfaceVariant,
              fontWeight: event.done ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          event.dateTime == null
              ? '-'
              : AppFormatters.shortDateTime(event.dateTime!),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: style, textAlign: TextAlign.right),
        ],
      ),
    );
  }
}
