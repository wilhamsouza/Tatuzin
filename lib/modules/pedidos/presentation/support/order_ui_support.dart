import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/operational_order.dart';

class OperationalOrderFilterOption {
  const OperationalOrderFilterOption({
    required this.label,
    required this.status,
  });

  final String label;
  final OperationalOrderStatus? status;
}

const operationalOrderFilterOptions = <OperationalOrderFilterOption>[
  OperationalOrderFilterOption(label: 'Todos', status: null),
  OperationalOrderFilterOption(
    label: 'Rascunhos',
    status: OperationalOrderStatus.draft,
  ),
  OperationalOrderFilterOption(
    label: 'Abertos',
    status: OperationalOrderStatus.open,
  ),
  OperationalOrderFilterOption(
    label: 'Em preparo',
    status: OperationalOrderStatus.inPreparation,
  ),
  OperationalOrderFilterOption(
    label: 'Prontos',
    status: OperationalOrderStatus.ready,
  ),
  OperationalOrderFilterOption(
    label: 'Entregues',
    status: OperationalOrderStatus.delivered,
  ),
  OperationalOrderFilterOption(
    label: 'Cancelados',
    status: OperationalOrderStatus.canceled,
  ),
];

String operationalOrderStatusLabel(OperationalOrderStatus status) {
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

String operationalOrderStatusDescription(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return 'Pedido ainda em montagem';
    case OperationalOrderStatus.open:
      return 'Aguardando inicio de preparo';
    case OperationalOrderStatus.inPreparation:
      return 'Producao em andamento';
    case OperationalOrderStatus.ready:
      return 'Pronto para entrega';
    case OperationalOrderStatus.delivered:
      return 'Pedido encerrado';
    case OperationalOrderStatus.canceled:
      return 'Fluxo interrompido';
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
      return AppStatusTone.success;
    case OperationalOrderStatus.canceled:
      return AppStatusTone.danger;
  }
}

IconData operationalOrderStatusIcon(OperationalOrderStatus status) {
  switch (status) {
    case OperationalOrderStatus.draft:
      return Icons.edit_note_rounded;
    case OperationalOrderStatus.open:
      return Icons.receipt_long_rounded;
    case OperationalOrderStatus.inPreparation:
      return Icons.local_fire_department_rounded;
    case OperationalOrderStatus.ready:
      return Icons.check_circle_rounded;
    case OperationalOrderStatus.delivered:
      return Icons.delivery_dining_rounded;
    case OperationalOrderStatus.canceled:
      return Icons.cancel_rounded;
  }
}

String operationalOrderElapsedLabel(OperationalOrder order, {DateTime? now}) {
  final currentTime = now ?? DateTime.now();
  final reference = order.status.isTerminal ? order.updatedAt : order.createdAt;
  final duration = currentTime.difference(reference);

  if (duration.inMinutes < 1) {
    return 'Agora mesmo';
  }
  if (duration.inMinutes < 60) {
    final minutes = duration.inMinutes;
    return '$minutes min';
  }
  if (duration.inHours < 24) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}min';
  }

  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  if (hours == 0) {
    return '${days}d';
  }
  return '${days}d ${hours}h';
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
