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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrinho'),
        actions: [
          if (!cart.isEmpty)
            TextButton(
              onPressed: () => _clearCart(context, ref),
              child: const Text('Limpar'),
            ),
        ],
      ),
      body: cart.isEmpty
          ? const Center(child: Text('Adicione produtos para montar a venda.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 160),
              itemCount: cart.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = cart.items[index];
                return Card(
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      'Unitario ${AppFormatters.currencyFromCents(item.unitPriceCents)}',
                                      if (item.modifierUnitDeltaCents != 0)
                                        'Ajustes ${AppFormatters.currencyFromCents(item.modifierUnitDeltaCents)}',
                                      'Estoque ${item.availableStockUnits}',
                                    ].join(' | '),
                                  ),
                                  if (item.baseProductName?.trim().isNotEmpty ??
                                      false) ...[
                                    const SizedBox(height: 4),
                                    Text('Base: ${item.baseProductName}'),
                                  ],
                                  if (item.modifiers.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    ...item.modifiers.map(
                                      (modifier) => Text(
                                        '- ${modifier.groupName}: ${modifier.optionName} (${modifier.adjustmentType})',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                  if (item.notes?.trim().isNotEmpty ??
                                      false) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Obs.: ${item.notes!}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remover item',
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .removeItem(item.id),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .decreaseQuantity(item.id),
                              icon: const Icon(Icons.remove),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${item.quantityUnits}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  Text(
                                    'quantidade',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: () {
                                final increased = ref
                                    .read(cartProvider.notifier)
                                    .increaseQuantity(item.id);
                                if (!increased) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Estoque insuficiente para aumentar.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add),
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Subtotal',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppFormatters.currencyFromCents(
                                    item.subtotalCents,
                                  ),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo da venda',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _CartMetric(
                              label: 'Itens',
                              value: '${cart.totalItems}',
                            ),
                          ),
                          Expanded(
                            child: _CartMetric(
                              label: 'Total',
                              value: AppFormatters.currencyFromCents(
                                cart.totalCents,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _createOperationalOrder(context, ref, cart),
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text('Criar pedido operacional'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              context.pushNamed(AppRouteNames.checkout),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Ir para checkout'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
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

class _CartMetric extends StatelessWidget {
  const _CartMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
