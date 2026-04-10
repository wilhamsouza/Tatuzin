import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/routes/route_names.dart';
import '../../../pedidos/domain/entities/operational_order.dart';
import '../../../pedidos/domain/entities/operational_order_item.dart';
import '../../../pedidos/domain/entities/operational_order_item_modifier.dart';
import '../../../pedidos/presentation/providers/order_providers.dart';
import '../../domain/entities/cart_item.dart';
import '../providers/cart_provider.dart';

class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalLines = cart.items.length;
    final totalItemsLabel = cart.totalItems == 1
        ? '1 item'
        : '${cart.totalItems} itens';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Carrinho'),
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
          if (!cart.isEmpty)
            PopupMenuButton<_CartMenuAction>(
              tooltip: 'Mais ações',
              onSelected: (value) async {
                switch (value) {
                  case _CartMenuAction.operationalOrder:
                    await _createOperationalOrder(context, ref, cart);
                  case _CartMenuAction.clear:
                    await _clearCart(context, ref);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _CartMenuAction.operationalOrder,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long_rounded),
                    title: Text('Criar pedido operacional'),
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
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 176),
              itemCount: cart.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = cart.items[index];
                return _CartItemCard(
                  item: item,
                  onRemove: () =>
                      ref.read(cartProvider.notifier).removeItem(item.id),
                  onDecrease: () =>
                      ref.read(cartProvider.notifier).decreaseQuantity(item.id),
                  onIncrease: () {
                    final increased = ref
                        .read(cartProvider.notifier)
                        .increaseQuantity(item.id);
                    if (!increased) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Estoque insuficiente para aumentar.'),
                        ),
                      );
                    }
                  },
                  onEditNotes: () => _editItemNotes(context, ref, item),
                );
              },
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo da venda',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _CartMetric(
                              label: 'Itens',
                              value: totalItemsLabel,
                              icon: Icons.shopping_bag_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _CartMetric(
                              label: 'Total',
                              value: AppFormatters.currencyFromCents(
                                cart.totalCents,
                              ),
                              icon: Icons.payments_outlined,
                              emphasize: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              context.pushNamed(AppRouteNames.checkout),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Finalizar pedido'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'O pedido operacional continua disponível no menu do carrinho.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _editItemNotes(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
  ) async {
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

  Future<void> _clearCart(BuildContext context, WidgetRef ref) async {
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
    WidgetRef ref,
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
          OperationalOrderItemInput(
            productId: item.productId,
            baseProductId: item.baseProductId,
            productNameSnapshot: item.productName,
            quantityMil: item.quantityMil,
            unitPriceCents: item.unitPriceCents,
            subtotalCents: item.subtotalCents,
            notes: item.notes,
          ),
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
      ref.invalidate(operationalOrdersProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Pedido operacional #$orderId criado com sucesso.'),
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
          SnackBar(content: Text('Falha ao criar pedido operacional: $error')),
        );
    }
  }
}

enum _CartMenuAction { operationalOrder, clear }

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

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant),
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
                        item.productName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoPill(
                            icon: Icons.sell_outlined,
                            label:
                                'Unitário ${AppFormatters.currencyFromCents(item.unitPriceCents)}',
                          ),
                          if (item.modifierUnitDeltaCents != 0)
                            _InfoPill(
                              icon: Icons.tune_rounded,
                              label:
                                  'Ajustes ${AppFormatters.currencyFromCents(item.modifierUnitDeltaCents)}',
                            ),
                          if (baseName != null && baseName.isNotEmpty)
                            _InfoPill(
                              icon: Icons.layers_outlined,
                              label: baseName,
                            ),
                        ],
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
            const SizedBox(height: 16),
            if (hasDetails) ...[
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    'Detalhes do item',
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
                    const SizedBox(height: 8),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(16),
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
              const SizedBox(height: 16),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onEditNotes,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Adicionar observação'),
                ),
              ),
              const SizedBox(height: 12),
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
                      style: theme.textTheme.titleLarge?.copyWith(
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: onDecrease,
              icon: const Icon(Icons.remove_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    quantity == 1 ? 'unidade' : 'unidades',
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartMetric extends StatelessWidget {
  const _CartMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasize ? colorScheme.primaryContainer : colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: emphasize
                ? colorScheme.onPrimaryContainer
                : colorScheme.primary,
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: emphasize
                  ? colorScheme.onPrimaryContainer.withValues(alpha: 0.78)
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: emphasize ? colorScheme.onPrimaryContainer : null,
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
