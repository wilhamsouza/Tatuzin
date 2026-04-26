import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../domain/entities/operational_order.dart';
import '../providers/order_print_providers.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';
import '../widgets/kitchen_printer_config_dialog.dart';
import '../widgets/operational_order_item_card.dart';
import '../widgets/order_status_badge.dart';

class KitchenOrderViewPage extends ConsumerWidget {
  const KitchenOrderViewPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(operationalOrderDetailProvider(orderId));
    final statusState = ref.watch(operationalOrderStatusControllerProvider);
    final reprintState = ref.watch(orderTicketReprintControllerProvider);
    final isBusy = statusState.isLoading || reprintState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo cozinha'),
        actions: [
          IconButton(
            tooltip: 'Configurar impressora',
            onPressed: () => _openPrinterConfig(context, ref),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Pedido nao encontrado.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
            children: [
              AppCard(
                padding: const EdgeInsets.all(18),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surface,
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
                                'Pedido #${detail.order.id}',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                detail.order.customerLabel,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${operationalOrderServiceTypeLabel(detail.order.serviceType)} | ${AppFormatters.shortDateTime(detail.order.updatedAt)}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ],
                          ),
                        ),
                        OrderStatusBadge(status: detail.order.status),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('Itens ${detail.totalUnits}')),
                        Chip(
                          label: Text(
                            'Tempo ${operationalOrderElapsedLabel(detail.order)}',
                          ),
                        ),
                      ],
                    ),
                    if (detail.order.notes?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          detail.order.notes!.trim(),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (detail.items.isEmpty)
                const AppCard(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Nenhum item no pedido ainda.'),
                  ),
                )
              else
                ...detail.items.map(
                  (itemDetail) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OperationalOrderItemCard(
                      itemDetail: itemDetail,
                      showPrices: false,
                      kitchenMode: true,
                    ),
                  ),
                ),
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
                  onPressed: () =>
                      ref.invalidate(operationalOrderDetailProvider(orderId)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: detailAsync.when(
          data: (detail) {
            if (detail == null) {
              return const SizedBox.shrink();
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _KitchenActionButton(
                      label: 'Em preparo',
                      icon: Icons.local_fire_department_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.inPreparation,
                              ) &&
                              !isBusy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.inPreparation,
                            )
                          : null,
                    ),
                    _KitchenActionButton(
                      label: 'Pronto',
                      icon: Icons.check_circle_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.ready,
                              ) &&
                              !isBusy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.ready,
                            )
                          : null,
                    ),
                    _KitchenActionButton(
                      label: 'Entregue',
                      icon: Icons.delivery_dining_rounded,
                      onPressed:
                          detail.order.status.canTransitionTo(
                                OperationalOrderStatus.delivered,
                              ) &&
                              !isBusy
                          ? () => _updateStatus(
                              context,
                              ref,
                              OperationalOrderStatus.delivered,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : () => _reprint(context, ref),
                    icon: reprintState.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded),
                    label: Text(
                      reprintState.isLoading
                          ? 'Reimprimindo...'
                          : 'Reimprimir ticket',
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );
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

  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(orderTicketReprintControllerProvider.notifier)
        .reprint(orderId);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.hasFailure
                ? 'Falha ao reimprimir ticket: ${result.failureMessage}'
                : 'Ticket reimpresso com sucesso.',
          ),
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
}

class _KitchenActionButton extends StatelessWidget {
  const _KitchenActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
