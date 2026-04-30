import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/routes/route_names.dart';
import '../../../pedidos/domain/entities/operational_order.dart';
import '../../../pedidos/domain/entities/operational_order_item.dart';
import '../../../pedidos/domain/entities/operational_order_item_modifier.dart';
import '../../../pedidos/presentation/providers/order_providers.dart';
import '../../domain/entities/cart_enums.dart';
import '../../domain/entities/cart_item.dart';
import '../providers/cart_provider.dart';

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  late final TextEditingController _deliveryFieldController;
  late final TextEditingController _couponController;
  String? _couponFeedback;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _deliveryFieldController = TextEditingController(
      text: cart.tipoEntrega == TipoEntrega.mesa
          ? cart.numeroMesa ?? ''
          : cart.cep ?? '',
    );
    _couponController = TextEditingController(text: cart.cupomCodigo ?? '');
  }

  @override
  void dispose() {
    _deliveryFieldController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalLines = cart.items.length;
    final totalItemsLabel = cart.totalItems == 1
        ? '1 item'
        : '${cart.totalItems} itens';
    _syncControllers(cart);
    final subtotalCents = cart.subtotalCents;
    final freightCents = cart.freteCents;
    final totalCents = cart.finalTotalCents;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Carrinho da venda'),
            if (!cart.isEmpty)
              Text(
                '$totalItemsLabel em $totalLines ${totalLines == 1 ? 'produto' : 'produtos'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voltar ao painel operacional',
            onPressed: () => context.goNamed(AppRouteNames.dashboard),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: 'Continuar no PDV',
            onPressed: () => context.goNamed(AppRouteNames.sales),
            icon: const Icon(Icons.storefront_outlined),
          ),
          if (!cart.isEmpty)
            PopupMenuButton<_CartMenuAction>(
              tooltip: 'Mais ações',
              onSelected: (value) async {
                switch (value) {
                  case _CartMenuAction.operationalOrder:
                    await _createOperationalOrder(context, cart);
                  case _CartMenuAction.clear:
                    await _clearCart(context);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _CartMenuAction.operationalOrder,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long_rounded),
                    title: Text('Criar pedido de venda'),
                  ),
                ),
                PopupMenuItem(
                  value: _CartMenuAction.clear,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Limpar carrinho'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: cart.isEmpty
          ? _EmptyCartState(
              onPressed: () => context.goNamed(AppRouteNames.sales),
            )
          : _buildFilledBody(context, cart),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _buildSummaryBar(
              context,
              totalItemsLabel: totalItemsLabel,
              subtotalCents: subtotalCents,
              freightCents: freightCents,
              totalCents: totalCents,
            ),
    );
  }

  Widget _buildFilledBody(BuildContext context, CartState cart) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 190),
      children: [
        for (var index = 0; index < cart.items.length; index++) ...[
          _CartItemCard(
            item: cart.items[index],
            onRemove: () => ref
                .read(cartProvider.notifier)
                .removeItem(cart.items[index].id),
            onDecrease: () => ref
                .read(cartProvider.notifier)
                .decreaseQuantity(cart.items[index].id),
            onIncrease: () {
              final increased = ref
                  .read(cartProvider.notifier)
                  .increaseQuantity(cart.items[index].id);
              if (!increased) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Estoque insuficiente para aumentar.'),
                  ),
                );
              }
            },
            onEditNotes: () => _editItemNotes(context, cart.items[index]),
          ),
          if (index < cart.items.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              title: const Text('Opções da venda'),
              subtitle: Text(
                'Entrega, mesa ou cupom ficam aqui para não pesar a tela principal.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                _DeliverySectionCard(
                  selectedType: cart.tipoEntrega,
                  controller: _deliveryFieldController,
                  onTypeChanged: _handleDeliveryTypeChanged,
                  onFieldChanged: (value) =>
                      _handleDeliveryFieldChanged(cart.tipoEntrega, value),
                ),
                const SizedBox(height: 10),
                _CouponSectionCard(
                  controller: _couponController,
                  feedback: _couponFeedback,
                  appliedCouponCode: cart.cupomCodigo,
                  discountCents: cart.cupomDescontoCents,
                  onApply: _applyCoupon,
                  onRemove: cart.cupomCodigo == null ? null : _removeCoupon,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(
    BuildContext context, {
    required String totalItemsLabel,
    required int subtotalCents,
    required int freightCents,
    required int totalCents,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cart = ref.read(cartProvider);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                          'Total da venda',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          totalItemsLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cartDeliverySummaryLabel(cart.tipoEntrega),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppFormatters.currencyFromCents(totalCents),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CompactSummaryChip(
                    icon: Icons.receipt_long_outlined,
                    label:
                        'Subtotal ${AppFormatters.currencyFromCents(subtotalCents)}',
                  ),
                  _CompactSummaryChip(
                    icon: cart.tipoEntrega == TipoEntrega.delivery
                        ? Icons.local_shipping_outlined
                        : cart.tipoEntrega == TipoEntrega.mesa
                        ? Icons.table_restaurant_outlined
                        : Icons.store_mall_directory_outlined,
                    label: freightCents == 0
                        ? '${cartDeliverySummaryLabel(cart.tipoEntrega)} grátis'
                        : '${cartDeliverySummaryLabel(cart.tipoEntrega)} ${AppFormatters.currencyFromCents(freightCents)}',
                  ),
                  if (cart.cupomDescontoCents > 0)
                    _CompactSummaryChip(
                      icon: Icons.sell_outlined,
                      label:
                          'Desconto ${AppFormatters.currencyFromCents(cart.cupomDescontoCents)}',
                      emphasize: true,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.goNamed(AppRouteNames.sales),
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Continuar venda'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          context.pushNamed(AppRouteNames.checkout),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Finalizar venda'),
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

  void _syncControllers(CartState cart) {
    final contextualValue = cart.tipoEntrega == TipoEntrega.mesa
        ? cart.numeroMesa ?? ''
        : cart.cep ?? '';
    if (_deliveryFieldController.text != contextualValue) {
      _deliveryFieldController.value = TextEditingValue(
        text: contextualValue,
        selection: TextSelection.collapsed(offset: contextualValue.length),
      );
    }

    final couponValue = cart.cupomCodigo ?? '';
    if (_couponController.text != couponValue) {
      _couponController.value = TextEditingValue(
        text: couponValue,
        selection: TextSelection.collapsed(offset: couponValue.length),
      );
    }
  }

  void _handleDeliveryTypeChanged(TipoEntrega nextType) {
    ref.read(cartProvider.notifier).setTipoEntrega(nextType);
    _deliveryFieldController.clear();
    setState(() {
      _couponFeedback = null;
    });
  }

  void _handleDeliveryFieldChanged(TipoEntrega tipoEntrega, String value) {
    final controller = ref.read(cartProvider.notifier);
    if (tipoEntrega == TipoEntrega.delivery) {
      controller.setCep(value);
      return;
    }
    if (tipoEntrega == TipoEntrega.mesa) {
      controller.setNumeroMesa(value);
    }
  }

  void _applyCoupon() {
    final code = _couponController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _couponFeedback = 'Digite um cupom para continuar.';
      });
      return;
    }

    try {
      ref.read(cartProvider.notifier).aplicarCupom(code);
      setState(() {
        _couponFeedback =
            'Cupom aplicado ao resumo do carrinho. O checkout segue no fluxo atual.';
      });
    } catch (_) {
      setState(() {
        _couponFeedback = 'Cupom inválido ou expirado.';
      });
    }
  }

  void _removeCoupon() {
    ref.read(cartProvider.notifier).removerCupom();
    _couponController.clear();
    setState(() {
      _couponFeedback = 'Cupom removido do resumo.';
    });
  }

  Future<void> _editItemNotes(BuildContext context, CartItem item) async {
    final controller = TextEditingController(text: item.notes ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Observação de ${item.productName}'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Ex.: sem cebola, embalar separado...',
              labelText: 'Observação',
            ),
          ),
          actions: [
            if ((item.notes?.trim().isNotEmpty ?? false))
              TextButton(
                onPressed: () {
                  ref
                      .read(cartProvider.notifier)
                      .updateItemNotes(item.id, null);
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Remover'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                ref
                    .read(cartProvider.notifier)
                    .updateItemNotes(item.id, controller.text);
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Observação do item atualizada.')),
        );
    }
  }

  Future<void> _clearCart(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Limpar carrinho'),
          content: const Text('Deseja remover todos os itens do carrinho?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Limpar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      ref.read(cartProvider.notifier).clear();
    }
  }

  Future<void> _createOperationalOrder(
    BuildContext context,
    CartState cart,
  ) async {
    try {
      final repository = ref.read(operationalOrderRepositoryProvider);
      final orderId = await repository.create(
        const OperationalOrderInput(status: OperationalOrderStatus.open),
      );

      for (final item in cart.items) {
        final orderItemId = await repository.addItem(
          orderId,
          operationalOrderItemInputFromCartItem(item),
        );

        for (final modifier in item.modifiers) {
          await repository.addItemModifier(
            orderItemId,
            OperationalOrderItemModifierInput(
              modifierGroupId: modifier.modifierGroupId,
              modifierOptionId: modifier.modifierOptionId,
              groupNameSnapshot: modifier.groupName,
              optionNameSnapshot: modifier.optionName,
              adjustmentTypeSnapshot: modifier.adjustmentType,
              priceDeltaCents: modifier.priceDeltaCents,
              quantity: modifier.quantity,
            ),
          );
        }
      }

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(operationalOrderBoardProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Pedido de venda #$orderId criado com sucesso.'),
          ),
        );
      context.pushNamed(
        AppRouteNames.orderDetail,
        pathParameters: {'orderId': '$orderId'},
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao criar pedido de venda: $error')),
        );
    }
  }
}

enum _CartMenuAction { operationalOrder, clear }

OperationalOrderItemInput operationalOrderItemInputFromCartItem(CartItem item) {
  return OperationalOrderItemInput(
    productId: item.productId,
    baseProductId: item.baseProductId,
    productVariantId: item.productVariantId,
    variantSkuSnapshot: item.variantSku,
    variantColorSnapshot: item.variantColorLabel,
    variantSizeSnapshot: item.variantSizeLabel,
    productNameSnapshot: item.productName,
    quantityMil: item.quantityMil,
    unitPriceCents: item.unitPriceCents,
    subtotalCents: item.subtotalCents,
    notes: item.notes,
  );
}

String cartDeliverySummaryLabel(TipoEntrega tipoEntrega) {
  switch (tipoEntrega) {
    case TipoEntrega.delivery:
      return 'Frete';
    case TipoEntrega.retirada:
      return 'Retirada';
    case TipoEntrega.mesa:
      return 'Atendimento em mesa';
  }
}

String? cartDeliveryFieldLabel(TipoEntrega tipoEntrega) {
  switch (tipoEntrega) {
    case TipoEntrega.delivery:
      return 'CEP';
    case TipoEntrega.mesa:
      return 'Número da mesa';
    case TipoEntrega.retirada:
      return null;
  }
}

String? cartDeliveryHintText(TipoEntrega tipoEntrega) {
  switch (tipoEntrega) {
    case TipoEntrega.delivery:
      return 'Ex.: 01310-100';
    case TipoEntrega.mesa:
      return 'Ex.: 12';
    case TipoEntrega.retirada:
      return null;
  }
}

IconData cartDeliveryIcon(TipoEntrega tipoEntrega) {
  switch (tipoEntrega) {
    case TipoEntrega.delivery:
      return Icons.local_shipping_outlined;
    case TipoEntrega.retirada:
      return Icons.store_mall_directory_outlined;
    case TipoEntrega.mesa:
      return Icons.table_restaurant_outlined;
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.onRemove,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEditNotes,
  });

  final CartItem item;
  final VoidCallback onRemove;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEditNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasDetails =
        item.modifiers.isNotEmpty || (item.notes?.trim().isNotEmpty ?? false);
    final baseName = item.baseProductName?.trim();
    final detailLine = [
      AppFormatters.currencyFromCents(item.unitPriceCents),
      if (item.modifierUnitDeltaCents != 0)
        'Ajustes ${AppFormatters.currencyFromCents(item.modifierUnitDeltaCents)}',
      if (baseName != null && baseName.isNotEmpty) baseName,
    ].join(' • ');

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CartThumbnail(path: item.primaryPhotoPath),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detailLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remover item',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasDetails) ...[
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    'Complementos e observação',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    item.modifiers.isNotEmpty
                        ? '${item.modifiers.length} ${item.modifiers.length == 1 ? 'modificador' : 'modificadores'}'
                        : 'Observação personalizada',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    const SizedBox(height: 6),
                    if (item.modifiers.isNotEmpty)
                      Column(
                        children: item.modifiers
                            .map(
                              (modifier) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ModifierTile(modifier: modifier),
                              ),
                            )
                            .toList(),
                      ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Observação',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: onEditNotes,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                child: Text(
                                  item.notes?.trim().isNotEmpty ?? false
                                      ? 'Editar'
                                      : 'Adicionar',
                                ),
                              ),
                            ],
                          ),
                          Text(
                            item.notes?.trim().isNotEmpty ?? false
                                ? item.notes!.trim()
                                : 'Nenhuma observação informada para este item.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onEditNotes,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Adicionar observação'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _QuantityControl(
                  quantity: item.quantityUnits,
                  onDecrease: onDecrease,
                  onIncrease: onIncrease,
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Subtotal',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatters.currencyFromCents(item.subtotalCents),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartThumbnail extends StatelessWidget {
  const _CartThumbnail({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPath = path?.trim().isNotEmpty ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPath
            ? Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _thumbnailPlaceholder(colorScheme),
              )
            : _thumbnailPlaceholder(colorScheme),
      ),
    );
  }

  Widget _thumbnailPlaceholder(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
      child: Icon(Icons.inventory_2_outlined, color: colorScheme.primary),
    );
  }
}

class _DeliverySectionCard extends StatelessWidget {
  const _DeliverySectionCard({
    required this.selectedType,
    required this.controller,
    required this.onTypeChanged,
    required this.onFieldChanged,
  });

  final TipoEntrega selectedType;
  final TextEditingController controller;
  final ValueChanged<TipoEntrega> onTypeChanged;
  final ValueChanged<String> onFieldChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tipo de entrega',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TipoEntrega.values
                .map(
                  (type) => ChoiceChip(
                    selected: selectedType == type,
                    avatar: Icon(cartDeliveryIcon(type), size: 18),
                    label: Text(type.label),
                    onSelected: (_) => onTypeChanged(type),
                  ),
                )
                .toList(growable: false),
          ),
          if (cartDeliveryFieldLabel(selectedType) != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: selectedType == TipoEntrega.mesa
                  ? TextInputType.number
                  : TextInputType.streetAddress,
              decoration: InputDecoration(
                labelText: cartDeliveryFieldLabel(selectedType),
                hintText: cartDeliveryHintText(selectedType),
                isDense: true,
              ),
              onChanged: onFieldChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _CouponSectionCard extends StatelessWidget {
  const _CouponSectionCard({
    required this.controller,
    required this.feedback,
    required this.appliedCouponCode,
    required this.discountCents,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final String? feedback;
  final String? appliedCouponCode;
  final int discountCents;
  final VoidCallback onApply;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
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
                  'Cupom',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (appliedCouponCode != null)
                Chip(
                  label: Text(
                    '$appliedCouponCode (- ${AppFormatters.currencyFromCents(discountCents)})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código do cupom',
                    hintText: 'Ex.: TATU5',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: onApply,
                child: const Text('Aplicar'),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Remover cupom',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
          if (feedback != null) ...[
            const SizedBox(height: 8),
            Text(
              feedback!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: onDecrease,
              icon: const Icon(Icons.remove_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$quantity',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    quantity == 1 ? 'un.' : 'un.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              visualDensity: VisualDensity.compact,
              onPressed: onIncrease,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModifierTile extends StatelessWidget {
  const _ModifierTile({required this.modifier});

  final CartItemModifier modifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPriceDelta = modifier.totalDeltaCents != 0;
    final quantityLabel = modifier.quantity > 1
        ? '${modifier.quantity}x'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modifier.groupName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quantityLabel == null
                      ? modifier.optionName
                      : '$quantityLabel ${modifier.optionName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (hasPriceDelta)
            Text(
              AppFormatters.currencyFromCents(modifier.totalDeltaCents),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactSummaryChip extends StatelessWidget {
  const _CompactSummaryChip({
    required this.icon,
    required this.label,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: emphasize
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: emphasize
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: emphasize ? colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.shopping_cart_checkout_rounded,
                  size: 42,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Seu carrinho está vazio',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Adicione produtos para montar a venda e seguir para a finalização.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.storefront_rounded),
                label: const Text('Voltar para vendas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
