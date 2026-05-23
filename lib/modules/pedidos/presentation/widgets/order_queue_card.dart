import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/operational_order_summary.dart';
import '../support/order_ui_support.dart';
import 'order_status_badge.dart';

class OrderQueueCard extends StatelessWidget {
  const OrderQueueCard({
    super.key,
    required this.summary,
    required this.onOpen,
    this.onPrimaryAction,
    this.primaryActionLabel,
    this.primaryActionIcon,
  });

  final OperationalOrderSummary summary;
  final VoidCallback onOpen;
  final VoidCallback? onPrimaryAction;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final channel = operationalOrderServiceTypeLabel(order.serviceType);

    return AppCard(
      onTap: onOpen,
      padding: EdgeInsets.all(layout.compactCardPadding + 2),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: layout.space2 / 2),
                    Text(
                      '#${order.id} · ${AppFormatters.shortDateTime(order.createdAt)} · $channel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: layout.space4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.currencyFromCents(summary.totalCents),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: layout.space2),
                  OrderStatusBadge(
                    status: order.status,
                    label: _statusLabel(summary),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: layout.space3),
          Row(
            children: [
              Icon(
                Icons.checkroom_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: layout.space2),
              Expanded(
                child: Text(
                  '${summary.totalUnits} peca(s) · ${summary.lineItemsCount} produto(s)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onPrimaryAction != null && primaryActionLabel != null) ...[
                SizedBox(width: layout.space3),
                FilledButton.tonalIcon(
                  onPressed: onPrimaryAction,
                  icon: Icon(primaryActionIcon ?? Icons.arrow_forward_rounded),
                  label: Text(primaryActionLabel!),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
          if (order.notes?.trim().isNotEmpty ?? false) ...[
            SizedBox(height: layout.space3),
            Text(
              operationalOrderShortNotes(order.notes, maxLength: 80),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? operationalOrderListPrimaryActionLabel(
  OperationalOrderSummary summary,
) {
  final order = summary.order;
  if (order.status == OperationalOrderStatus.draft && summary.totalUnits > 0) {
    return 'Confirmar';
  }
  if (order.status == OperationalOrderStatus.open) {
    return 'Separar';
  }
  if (order.status == OperationalOrderStatus.inPreparation) {
    return 'Separado';
  }
  if (order.status == OperationalOrderStatus.ready) {
    return 'Finalizar venda';
  }
  if (order.status == OperationalOrderStatus.delivered &&
      summary.linkedSaleId != null) {
    return 'Ver venda';
  }
  if (order.status == OperationalOrderStatus.delivered &&
      summary.linkedSaleId == null) {
    return 'Finalizar venda';
  }
  return null;
}

IconData? operationalOrderListPrimaryActionIcon(
  OperationalOrderSummary summary,
) {
  switch (summary.order.status) {
    case OperationalOrderStatus.draft:
      return Icons.check_rounded;
    case OperationalOrderStatus.open:
      return Icons.inventory_2_rounded;
    case OperationalOrderStatus.inPreparation:
      return Icons.check_circle_rounded;
    case OperationalOrderStatus.ready:
      return Icons.point_of_sale_rounded;
    case OperationalOrderStatus.delivered:
      return Icons.receipt_long_rounded;
    case OperationalOrderStatus.canceled:
      return null;
  }
}

String _statusLabel(OperationalOrderSummary summary) {
  if (summary.order.status == OperationalOrderStatus.delivered &&
      summary.linkedSaleId == null) {
    return 'Pronto para venda';
  }
  return operationalOrderStatusLabel(summary.order.status);
}
