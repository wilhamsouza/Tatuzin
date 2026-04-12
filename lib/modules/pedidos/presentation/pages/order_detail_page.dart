import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../../vendas/domain/entities/checkout_input.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/presentation/providers/sales_providers.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_detail.dart';
import '../providers/order_print_providers.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';
import '../widgets/add_order_item_sheet.dart';
import '../widgets/kitchen_printer_config_dialog.dart';
import '../widgets/operational_order_item_card.dart';
import '../widgets/order_progress_stepper.dart';
import '../widgets/order_status_badge.dart';
import 'order_ticket_preview_page.dart';

class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(operationalOrderDetailProvider(orderId));
    final statusState = ref.watch(operationalOrderStatusControllerProvider);
    final addItemState = ref.watch(addOperationalOrderItemControllerProvider);
    final printState = ref.watch(orderKitchenPrintControllerProvider);
    final busy =
        statusState.isLoading || addItemState.isLoading || printState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #$orderId'),
        actions: [
          IconButton(
            tooltip: 'Modo cozinha',
            onPressed: () {
              context.pushNamed(
                AppRouteNames.orderKitchen,
                pathParameters: {'orderId': '$orderId'},
              );
            },
            icon: const Icon(Icons.soup_kitchen_rounded),
          ),
        ],
      ),
      floatingActionButton: orderAsync.maybeWhen(
        data: (detail) {
          if (detail == null || !detail.order.allowsItemChanges) {
            return null;
          }
          return FloatingActionButton.extended(
            onPressed: busy ? null : () => _addItem(context, ref),
            icon: addItemState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(
              addItemState.isLoading ? 'Adicionando...' : 'Adicionar item',
            ),
          );
        },
        orElse: () => null,
      ),
      body: orderAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Pedido nao encontrado.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              _OrderOverviewCard(detail: detail),
              const SizedBox(height: 12),
              AppSectionCard(
                title: 'Fluxo do pedido',
                subtitle: operationalOrderStatusDescription(
                  detail.order.status,
                ),
                child: OrderProgressStepper(status: detail.order.status),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                title: 'Acoes operacionais',
                subtitle:
                    'Atualize o fluxo sem gambiarras locais. As mudancas passam pelo repositorio e invalidam os dados da tela.',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusActionButton(
                      label: 'Marcar aberto',
                      icon: Icons.receipt_long_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.open,
                              ) &&
                              !busy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.open,
                            )
                          : null,
                    ),
                    _StatusActionButton(
                      label: 'Iniciar preparo',
                      icon: Icons.local_fire_department_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.inPreparation,
                              ) &&
                              !busy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.inPreparation,
                            )
                          : null,
                    ),
                    _StatusActionButton(
                      label: 'Marcar pronto',
                      icon: Icons.check_circle_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.ready,
                              ) &&
                              !busy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.ready,
                            )
                          : null,
                    ),
                    _StatusActionButton(
                      label: 'Marcar entregue',
                      icon: Icons.delivery_dining_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.delivered,
                              ) &&
                              !busy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.delivered,
                            )
                          : null,
                    ),
                    _StatusActionButton(
                      label: 'Cancelar pedido',
                      icon: Icons.cancel_rounded,
                      isDanger: true,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.canceled,
                              ) &&
                              !busy
                          ? () => _confirmAndCancel(context, ref)
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                title: 'Itens do pedido',
                subtitle: detail.items.isEmpty
                    ? 'Nenhum item adicionado ainda.'
                    : '${detail.lineItemsCount} linha(s) • ${detail.totalUnits} item(ns)',
                child: detail.items.isEmpty
                    ? const Text('Adicione itens para iniciar a producao.')
                    : Column(
                        children: detail.items
                            .map(
                              (itemDetail) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: OperationalOrderItemCard(
                                  itemDetail: itemDetail,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                title: 'Ticket e cozinha',
                subtitle:
                    'Acesse o preview interno, o modo cozinha e a impressao termica a partir do mesmo documento operacional.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder(
                      future: ref.read(kitchenPrinterConfigProvider.future),
                      builder: (context, snapshot) {
                        final config = snapshot.data;
                        return Text(
                          config == null
                              ? 'Impressora: nao configurada'
                              : 'Impressora: ${config.displayName} • ${config.targetLabel}',
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _openTicketPreview(context),
                          icon: const Icon(Icons.preview_rounded),
                          label: const Text('Preview ticket'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            context.pushNamed(
                              AppRouteNames.orderKitchen,
                              pathParameters: {'orderId': '$orderId'},
                            );
                          },
                          icon: const Icon(Icons.soup_kitchen_rounded),
                          label: const Text('Modo cozinha'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: busy
                              ? null
                              : () => _openPrinterConfig(context, ref),
                          icon: const Icon(Icons.settings_rounded),
                          label: const Text('Impressora'),
                        ),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _printKitchen(context, ref),
                          icon: printState.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.print_rounded),
                          label: Text(
                            printState.isLoading
                                ? 'Imprimindo...'
                                : 'Imprimir cozinha',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                title: 'Conversao em venda',
                subtitle:
                    'Separada das acoes de producao para evitar misturar cozinha, expedicao e fechamento comercial.',
                child: detail.linkedSaleId != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Venda #${detail.linkedSaleId} ja vinculada a este pedido.',
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () {
                              context.pushNamed(
                                AppRouteNames.saleReceipt,
                                pathParameters: {
                                  'saleId': '${detail.linkedSaleId}',
                                },
                              );
                            },
                            icon: const Icon(Icons.point_of_sale_rounded),
                            label: const Text('Abrir venda vinculada'),
                          ),
                        ],
                      )
                    : FilledButton.icon(
                        onPressed: _canConvertToSale(detail) && !busy
                            ? () => _convertToSale(context, ref, detail)
                            : null,
                        icon: const Icon(Icons.point_of_sale_rounded),
                        label: Text(_convertButtonLabel(detail)),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Falha ao carregar pedido: $error')),
      ),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<AddOperationalOrderItemResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddOrderItemSheet(),
    );
    if (result == null) {
      return;
    }

    try {
      await ref
          .read(addOperationalOrderItemControllerProvider.notifier)
          .addItemWithModifiers(
            orderId: orderId,
            product: result.product,
            quantityUnits: result.quantityUnits,
            notes: result.notes,
            modifiers: result.modifiers,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Item adicionado ao pedido.')),
        );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao adicionar item: $error')),
        );
    }
  }

  void _openTicketPreview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderTicketPreviewPage(orderId: orderId),
      ),
    );
  }

  Future<void> _openPrinterConfig(BuildContext context, WidgetRef ref) async {
    final config = await ref.read(kitchenPrinterConfigProvider.future);
    if (!context.mounted) {
      return;
    }
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => KitchenPrinterConfigDialog(initialConfig: config),
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Impressora da cozinha atualizada.')),
        );
    }
  }

  Future<void> _printKitchen(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(orderKitchenPrintControllerProvider.notifier)
          .printOrder(orderId);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Ticket da cozinha enviado.')),
        );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao imprimir cozinha: $error')),
        );
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    OperationalOrderStatus status,
  ) async {
    try {
      await ref
          .read(operationalOrderStatusControllerProvider.notifier)
          .updateStatus(orderId: orderId, status: status);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Pedido atualizado para ${operationalOrderStatusLabel(status)}.',
            ),
          ),
        );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao atualizar pedido: $error')),
        );
    }
  }

  Future<void> _confirmAndCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar pedido'),
          content: const Text(
            'Deseja cancelar este pedido? O fluxo normal nao podera ser retomado sem regra explicita.',
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
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _updateStatus(context, ref, OperationalOrderStatus.canceled);
  }

  Future<void> _convertToSale(
    BuildContext context,
    WidgetRef ref,
    OperationalOrderDetail detail,
  ) async {
    if (detail.items.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha itens para converter em venda.')),
      );
      return;
    }

    if (detail.order.status == OperationalOrderStatus.canceled) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido cancelado nao pode ser convertido em venda.'),
        ),
      );
      return;
    }

    if (detail.order.status == OperationalOrderStatus.delivered) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pedido ja esta encerrado. Vincule a venda existente se necessario.',
          ),
        ),
      );
      return;
    }

    final confirmed = await _confirmConvertToSale(context, detail);
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final paymentMethod = await _pickImmediatePaymentMethod(context);
    if (paymentMethod == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final List<CartItem> cartItems = detail.items
        .map<CartItem>((entry) {
          final item = entry.item;
          final modifiers = entry.modifiers
              .map(
                (modifier) => CartItemModifier(
                  modifierGroupId: modifier.modifierGroupId,
                  modifierOptionId: modifier.modifierOptionId,
                  groupName: modifier.groupNameSnapshot ?? 'Modificador',
                  optionName: modifier.optionNameSnapshot,
                  adjustmentType: modifier.adjustmentTypeSnapshot,
                  priceDeltaCents: modifier.priceDeltaCents,
                  quantity: modifier.quantity,
                ),
              )
              .toList(growable: false);
          return CartItem(
            id: 'order_item_${item.id}',
            productId: item.productId,
            productName: item.productNameSnapshot,
            primaryPhotoPath: null,
            baseProductId: item.baseProductId,
            baseProductName: null,
            quantityMil: item.quantityMil,
            availableStockMil: item.quantityMil,
            unitPriceCents: item.unitPriceCents,
            unitMeasure: 'un',
            productType: 'unidade',
            modifiers: modifiers,
            notes: item.notes,
          );
        })
        .toList(growable: false);

    final checkoutInput = CheckoutInput(
      items: cartItems,
      saleType: SaleType.cash,
      paymentMethod: paymentMethod,
      operationalOrderId: orderId,
      notes: 'Venda originada do pedido operacional #$orderId.',
    );

    try {
      final sale = await ref
          .read(saleRepositoryProvider)
          .completeCashSale(input: checkoutInput);
      if (!context.mounted) {
        return;
      }
      ref.invalidate(operationalOrderDetailProvider(orderId));
      ref.invalidate(operationalOrdersProvider);
      context.pushNamed(
        AppRouteNames.saleReceipt,
        pathParameters: {'saleId': '${sale.saleId}'},
        extra: true,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Falha ao converter: $error')));
    }
  }

  Future<bool?> _confirmConvertToSale(
    BuildContext context,
    OperationalOrderDetail detail,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar conversao'),
          content: Text(
            'Gerar venda para o pedido #$orderId com ${detail.totalUnits} item(ns), total de ${AppFormatters.currencyFromCents(detail.totalCents)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Converter'),
            ),
          ],
        );
      },
    );
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

  bool _canConvertToSale(OperationalOrderDetail detail) {
    return detail.items.isNotEmpty &&
        detail.linkedSaleId == null &&
        detail.order.status != OperationalOrderStatus.canceled &&
        detail.order.status != OperationalOrderStatus.delivered;
  }

  String _convertButtonLabel(OperationalOrderDetail detail) {
    if (detail.items.isEmpty) {
      return 'Sem itens';
    }
    if (detail.order.status == OperationalOrderStatus.canceled) {
      return 'Pedido cancelado';
    }
    if (detail.order.status == OperationalOrderStatus.delivered) {
      return 'Pedido encerrado';
    }
    return 'Converter em venda';
  }
}

class _OrderOverviewCard extends StatelessWidget {
  const _OrderOverviewCard({required this.detail});

  final OperationalOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.surface,
          Theme.of(context).colorScheme.surfaceContainerLow,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
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
                      'Pedido #${order.id}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    OrderStatusBadge(status: order.status),
                  ],
                ),
              ),
              Text(
                AppFormatters.currencyFromCents(detail.totalCents),
                style: theme.textTheme.headlineSmall?.copyWith(
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
              _OverviewChip(
                icon: Icons.event_rounded,
                label: 'Criado ${AppFormatters.shortDateTime(order.createdAt)}',
              ),
              _OverviewChip(
                icon: Icons.update_rounded,
                label:
                    'Atualizado ${AppFormatters.shortDateTime(order.updatedAt)}',
              ),
              _OverviewChip(
                icon: Icons.schedule_rounded,
                label: 'Tempo ${operationalOrderElapsedLabel(order)}',
              ),
              _OverviewChip(
                icon: Icons.layers_rounded,
                label:
                    '${detail.totalUnits} item(ns) • ${detail.lineItemsCount} linha(s)',
              ),
            ],
          ),
          if (order.notes?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                order.notes!.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({required this.icon, required this.label});

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

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isDanger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    if (isDanger) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
