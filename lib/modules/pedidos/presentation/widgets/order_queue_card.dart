import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_selector_chip.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/operational_order.dart';
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
    final layout = context.appLayout;
    final tokens = context.appColors;

    return AppCard(
      onTap: onOpen,
      padding: EdgeInsets.all(layout.cardPadding),
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
                    SizedBox(height: layout.space2),
                    Text(
                      order.customerLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: layout.space6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OrderStatusBadge(status: order.status),
                  SizedBox(height: layout.space3),
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
          SizedBox(height: layout.sectionGap),
          Wrap(
            spacing: layout.space3,
            runSpacing: layout.space3,
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
            SizedBox(height: layout.blockGap),
            Text(
              operationalOrderShortNotes(order.notes),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (order.ticketMeta.hasFailure) ...[
            SizedBox(height: layout.blockGap),
            AppCard(
              tone: AppCardTone.danger,
              padding: EdgeInsets.all(layout.compactCardPadding),
              child: Text(
                operationalOrderShortNotes(order.ticketMeta.lastFailureMessage),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.danger.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          SizedBox(height: layout.sectionGap),
          Wrap(
            spacing: layout.space3,
            runSpacing: layout.space3,
            children: [
              _ActionChip(
                icon: Icons.open_in_new_rounded,
                label: 'Abrir',
                onPressed: onOpen,
              ),
              if (onSendToKitchen != null)
                _ActionChip(
                  icon: Icons.send_rounded,
                  label: operationalOrderSendToSeparationLabel,
                  onPressed: onSendToKitchen!,
                ),
              if (onReprint != null)
                _ActionChip(
                  icon: Icons.print_rounded,
                  label: operationalOrderPrintReceiptLabel,
                  onPressed: onReprint!,
                ),
              if (onMarkInPreparation != null)
                _ActionChip(
                  icon: Icons.inventory_2_rounded,
                  label: operationalOrderShortActionLabel(
                    OperationalOrderStatus.inPreparation,
                  ),
                  onPressed: onMarkInPreparation!,
                ),
              if (onMarkReady != null)
                _ActionChip(
                  icon: Icons.notifications_active_rounded,
                  label: operationalOrderShortActionLabel(
                    OperationalOrderStatus.ready,
                  ),
                  onPressed: onMarkReady!,
                ),
              if (onMarkDelivered != null)
                _ActionChip(
                  icon: Icons.shopping_bag_rounded,
                  label: operationalOrderShortActionLabel(
                    OperationalOrderStatus.delivered,
                  ),
                  onPressed: onMarkDelivered!,
                ),
              if (onInvoice != null)
                _ActionChip(
                  icon: Icons.point_of_sale_rounded,
                  label: 'Finalizar venda',
                  onPressed: onInvoice!,
                  tone: AppSelectorChipTone.brand,
                ),
              if (onCancel != null)
                _ActionChip(
                  icon: Icons.cancel_rounded,
                  label: 'Cancelar',
                  onPressed: onCancel!,
                  tone: AppSelectorChipTone.danger,
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
    return AppSelectorChip(
      icon: icon,
      label: label,
      selected: true,
      tone: AppSelectorChipTone.info,
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = AppSelectorChipTone.neutral,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final AppSelectorChipTone tone;

  @override
  Widget build(BuildContext context) {
    return AppSelectorChip(
      icon: icon,
      label: label,
      selected: true,
      tone: tone,
      onSelected: (_) => onPressed(),
    );
  }
}
