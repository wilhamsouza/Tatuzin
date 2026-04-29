import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/operational_order.dart';

const operationalOrderPanelSubtitle =
    'Acompanhe a fila de separacao, o status dos comprovantes e o faturamento sem misturar etapas.';
const operationalOrderSeparationModeLabel = 'Modo separacao';
const operationalOrderSendToSeparationLabel = 'Enviar para separacao';
const operationalOrderPrintReceiptLabel = 'Imprimir comprovante';
const operationalOrderPrintingReceiptLabel = 'Imprimindo...';
const operationalOrderPreviewTitle = 'Previa do comprovante';
const operationalOrderPreviewLabel = 'Previa do comprovante';
const operationalOrderReceiptLabel = 'Comprovante';
const operationalOrderReceiptFailureSummaryLabel = 'Falhas comprovante';
const operationalOrderReceiptHeaderLabel = 'Cabecalho do comprovante';
const operationalOrderReceiptProfileLabel = 'Separacao';
const operationalOrderInternalProfileLabel = 'Interno';
const operationalOrderPrinterNameLabel = 'Impressora de pedidos';
const operationalOrderPrinterDialogTitle = 'Impressora de separacao';
const operationalOrderPrinterUpdatedMessage =
    'Impressora de separacao atualizada.';
const operationalOrderSeparationManifestTitle = 'ROMANEIO DE SEPARACAO';
const operationalOrderInternalPreviewTitle = 'PREVIEW OPERACIONAL';
const operationalOrderSeparationManifestFooter =
    'Uso interno da separacao. Nao entregar ao cliente.';
const operationalOrderInternalPreviewFooter =
    'Previa tecnica para conferencia e diagnostico da impressao.';
const operationalOrderSendFailureMessagePrefix =
    'Pedido enviado para separacao, mas a impressao falhou:';
const operationalOrderSendSuccessMessage =
    'Pedido enviado para separacao e comprovante impresso.';
const operationalOrderReprintFailureMessagePrefix =
    'Falha ao imprimir comprovante:';
const operationalOrderReprintSuccessMessage =
    'Comprovante impresso com sucesso.';

String operationalOrderStatusLabel(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return 'Rascunho';
    case OperationalOrderStatus.open:
      return 'Aguardando separacao';
    case OperationalOrderStatus.inPreparation:
      return 'Em separacao';
    case OperationalOrderStatus.ready:
      return 'Pronto para retirada';
    case OperationalOrderStatus.delivered:
      return 'Entregue';
    case OperationalOrderStatus.canceled:
      return 'Cancelado';
  }
}

String operationalOrderStatusDescription(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return 'Pedido ainda nao confirmado.';
    case OperationalOrderStatus.open:
      return 'Pedido confirmado e aguardando separacao das pecas.';
    case OperationalOrderStatus.inPreparation:
      return 'Produtos em separacao.';
    case OperationalOrderStatus.ready:
      return 'Pedido pronto para retirada ou entrega.';
    case OperationalOrderStatus.delivered:
      return 'Pedido entregue ao cliente.';
    case OperationalOrderStatus.canceled:
      return 'Pedido cancelado.';
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
      return Icons.inventory_2_rounded;
    case OperationalOrderStatus.ready:
      return Icons.notifications_active_rounded;
    case OperationalOrderStatus.delivered:
      return Icons.shopping_bag_rounded;
    case OperationalOrderStatus.canceled:
      return Icons.cancel_rounded;
  }
}

String operationalOrderActionLabel(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.inPreparation:
      return 'Marcar em separacao';
    case OperationalOrderStatus.ready:
      return 'Marcar pronto para retirada';
    case OperationalOrderStatus.delivered:
      return 'Marcar como entregue';
    case OperationalOrderStatus.draft:
    case OperationalOrderStatus.open:
    case OperationalOrderStatus.canceled:
      return operationalOrderStatusLabel(status);
  }
}

String operationalOrderShortActionLabel(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.inPreparation:
      return 'Em separacao';
    case OperationalOrderStatus.ready:
      return 'Pronto para retirada';
    case OperationalOrderStatus.delivered:
      return 'Entregue';
    case OperationalOrderStatus.draft:
    case OperationalOrderStatus.open:
    case OperationalOrderStatus.canceled:
      return operationalOrderStatusLabel(status);
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
      return 'Venda presencial';
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
      return Icons.local_shipping_rounded;
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
