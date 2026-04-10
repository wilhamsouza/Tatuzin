import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/operational_order.dart';
import '../providers/order_providers.dart';

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(operationalOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos operacionais')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrder(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo pedido'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar pedido por observacao',
              onChanged: (value) {
                ref.read(operationalOrderSearchQueryProvider.notifier).state =
                    value;
              },
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
                          const Text(
                            'Nenhum pedido operacional criado ainda.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => _createOrder(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Criar primeiro pedido'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(operationalOrdersProvider);
                    await ref.read(operationalOrdersProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return Card(
                        child: ListTile(
                          title: Text('Pedido #${order.id}'),
                          subtitle: Text(
                            [
                              _statusLabel(order.status),
                              AppFormatters.shortDateTime(order.updatedAt),
                              if (order.notes?.trim().isNotEmpty ?? false)
                                order.notes!,
                            ].join(' - '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            context.pushNamed(
                              AppRouteNames.orderDetail,
                              pathParameters: {'orderId': '${order.id}'},
                            );
                          },
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
              labelText: 'Observacao (opcional)',
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

  String _statusLabel(OperationalOrderStatus status) {
    switch (status) {
      case OperationalOrderStatus.draft:
        return 'Rascunho';
      case OperationalOrderStatus.open:
        return 'Aberto';
      case OperationalOrderStatus.inPreparation:
        return 'Em preparo';
      case OperationalOrderStatus.ready:
        return 'Pronto';
      case OperationalOrderStatus.delivered:
        return 'Entregue';
      case OperationalOrderStatus.canceled:
        return 'Cancelado';
    }
  }
}
