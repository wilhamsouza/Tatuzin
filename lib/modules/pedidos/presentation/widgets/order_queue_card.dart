import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/operational_order_summary.dart';
import '../support/order_ui_support.dart';
import 'order_status_badge.dart';

class OrderQueueCard extends StatelessWidget {
  const OrderQueueCard({
    super.key,
    required this.summary,
    required this.onOpen,
    this.onSendToKitchen,
    this.onReprint,
    this.onMarkInPreparation,
    this.onMarkReady,
    this.onMarkDelivered,
    this.onInvoice,
    this.onCancel,
  });

  final OperationalOrderSummary summary;
  final VoidCallback onOpen;
  final VoidCallback? onSendToKitchen;
  final VoidCallback? onReprint;
  final VoidCallback? onMarkInPreparation;
  final VoidCallback? onMarkReady;
  final VoidCallback? onMarkDelivered;
  final VoidCallback? onInvoice;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final theme = Theme.of(context);

    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(16),
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.customerLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OrderStatusBadge(status: order.status),
                  const SizedBox(height: 6),
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: operationalOrderServiceTypeIcon(order.serviceType),
                label: operationalOrderServiceTypeLabel(order.serviceType),
              ),
              _MetaChip(
                icon: Icons.schedule_rounded,
                label: AppFormatters.shortDateTime(order.createdAt),
              ),
              _MetaChip(
                icon: Icons.layers_rounded,
                label: '${summary.totalUnits} item(ns)',
              ),
              _MetaChip(
                icon: Icons.payments_outlined,
                label: AppFormatters.currencyFromCents(summary.totalCents),
              ),
              _MetaChip(
                icon: Icons.timelapse_rounded,
                label: 'Tempo ${operationalOrderElapsedLabel(order)}',
              ),
              if (order.customerPhone?.trim().isNotEmpty ?? false)
                _MetaChip(
                  icon: Icons.phone_rounded,
                  label: order.customerPhone!.trim(),
                ),
            ],
          ),
          if (order.notes?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text(
              operationalOrderShortNotes(order.notes),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (order.ticketMeta.hasFailure) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                operationalOrderShortNotes(order.ticketMeta.lastFailureMessage),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: Icons.open_in_new_rounded,
                label: 'Abrir',
                onPressed: onOpen,
              ),
              if (onSendToKitchen != null)
                _ActionChip(
                  icon: Icons.send_rounded,
                  label: 'Enviar para cozinha',
                  onPressed: onSendToKitchen!,
                ),
              if (onReprint != null)
                _ActionChip(
                  icon: Icons.print_rounded,
                  label: 'Reimprimir',
                  onPressed: onReprint!,
                ),
              if (onMarkInPreparation != null)
                _ActionChip(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Marcar em preparo',
                  onPressed: onMarkInPreparation!,
                ),
              if (onMarkReady != null)
                _ActionChip(
                  icon: Icons.notifications_active_rounded,
                  label: 'Marcar pronto',
                  onPressed: onMarkReady!,
                ),
              if (onMarkDelivered != null)
                _ActionChip(
                  icon: Icons.delivery_dining_rounded,
                  label: 'Marcar entregue',
                  onPressed: onMarkDelivered!,
                ),
              if (onInvoice != null)
                _ActionChip(
                  icon: Icons.point_of_sale_rounded,
                  label: 'Faturar',
                  onPressed: onInvoice!,
                ),
              if (onCancel != null)
                _ActionChip(
                  icon: Icons.cancel_rounded,
                  label: 'Cancelar',
                  onPressed: onCancel!,
                  danger: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: Icon(
        icon,
        size: 18,
        color: danger ? colorScheme.error : colorScheme.primary,
      ),
      label: Text(label),
      onPressed: onPressed,
      side: BorderSide(
        color: danger
            ? colorScheme.error.withValues(alpha: 0.4)
            : colorScheme.outlineVariant,
      ),
      backgroundColor: danger
          ? colorScheme.errorContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLow,
    );
  }
}
