import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/operational_order.dart';

String operationalOrderStatusLabel(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return 'Rascunho';
    case OperationalOrderStatus.open:
      return 'Enviado';
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

String operationalOrderStatusDescription(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return 'Pedido em montagem no balcao';
    case OperationalOrderStatus.open:
      return 'Pedido enviado para a fila da cozinha';
    case OperationalOrderStatus.inPreparation:
      return 'Cozinha preparando o pedido';
    case OperationalOrderStatus.ready:
      return 'Pedido pronto para retirada ou entrega';
    case OperationalOrderStatus.delivered:
      return 'Fluxo operacional concluido, pronto para faturar';
    case OperationalOrderStatus.canceled:
      return 'Pedido interrompido';
  }
}

AppStatusTone operationalOrderStatusTone(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return AppStatusTone.neutral;
    case OperationalOrderStatus.open:
      return AppStatusTone.info;
    case OperationalOrderStatus.inPreparation:
      return AppStatusTone.warning;
    case OperationalOrderStatus.ready:
      return AppStatusTone.success;
    case OperationalOrderStatus.delivered:
      return AppStatusTone.neutral;
    case OperationalOrderStatus.canceled:
      return AppStatusTone.danger;
  }
}

IconData operationalOrderStatusIcon(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return Icons.edit_note_rounded;
    case OperationalOrderStatus.open:
      return Icons.send_to_mobile_rounded;
    case OperationalOrderStatus.inPreparation:
      return Icons.local_fire_department_rounded;
    case OperationalOrderStatus.ready:
      return Icons.notifications_active_rounded;
    case OperationalOrderStatus.delivered:
      return Icons.delivery_dining_rounded;
    case OperationalOrderStatus.canceled:
      return Icons.cancel_rounded;
  }
}

String operationalOrderServiceTypeLabel(
  OperationalOrderServiceType serviceType,
) {
  switch (serviceType) {
    case OperationalOrderServiceType.counter:
      return 'Balcao';
    case OperationalOrderServiceType.pickup:
      return 'Retirada';
    case OperationalOrderServiceType.delivery:
      return 'Delivery';
    case OperationalOrderServiceType.table:
      return 'Mesa';
  }
}

String operationalOrderServiceTypeHint(
  OperationalOrderServiceType serviceType,
) {
  switch (serviceType) {
    case OperationalOrderServiceType.counter:
      return 'Consumo imediato no balcao';
    case OperationalOrderServiceType.pickup:
      return 'Cliente retira no local';
    case OperationalOrderServiceType.delivery:
      return 'Sai para entrega';
    case OperationalOrderServiceType.table:
      return 'Atendimento em mesa';
  }
}

IconData operationalOrderServiceTypeIcon(
  OperationalOrderServiceType serviceType,
) {
  switch (serviceType) {
    case OperationalOrderServiceType.counter:
      return Icons.storefront_rounded;
    case OperationalOrderServiceType.pickup:
      return Icons.shopping_bag_rounded;
    case OperationalOrderServiceType.delivery:
      return Icons.delivery_dining_rounded;
    case OperationalOrderServiceType.table:
      return Icons.table_restaurant_rounded;
  }
}

String orderTicketDispatchStatusLabel(OrderTicketDispatchStatus status) {
  switch (status) {
    case OrderTicketDispatchStatus.pending:
      return 'Nao enviado';
    case OrderTicketDispatchStatus.sent:
      return 'Enviado';
    case OrderTicketDispatchStatus.failed:
      return 'Falhou';
  }
}

AppStatusTone orderTicketDispatchStatusTone(OrderTicketDispatchStatus status) {
  switch (status) {
    case OrderTicketDispatchStatus.pending:
      return AppStatusTone.neutral;
    case OrderTicketDispatchStatus.sent:
      return AppStatusTone.success;
    case OrderTicketDispatchStatus.failed:
      return AppStatusTone.danger;
  }
}

IconData orderTicketDispatchStatusIcon(OrderTicketDispatchStatus status) {
  switch (status) {
    case OrderTicketDispatchStatus.pending:
      return Icons.print_disabled_rounded;
    case OrderTicketDispatchStatus.sent:
      return Icons.print_rounded;
    case OrderTicketDispatchStatus.failed:
      return Icons.error_outline_rounded;
  }
}

String operationalOrderElapsedLabel(OperationalOrder order, {DateTime? now}) {
  final currentTime = now ?? DateTime.now();
  final reference = order.status.isTerminal
      ? (order.closedAt ?? order.updatedAt)
      : order.createdAt;
  final duration = currentTime.difference(reference);

  if (duration.inMinutes < 1) {
    return 'Agora mesmo';
  }
  if (duration.inMinutes < 60) {
    return '${duration.inMinutes} min';
  }
  if (duration.inHours < 24) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}min';
  }

  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  return hours == 0 ? '${days}d' : '${days}d ${hours}h';
}

String operationalOrderShortNotes(String? value, {int maxLength = 92}) {
  final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 1)}...';
}

String operationalOrderModifierLabel(String optionName, String adjustmentType) {
  if (adjustmentType == 'remove') {
    return 'Sem $optionName';
  }
  return optionName;
}
