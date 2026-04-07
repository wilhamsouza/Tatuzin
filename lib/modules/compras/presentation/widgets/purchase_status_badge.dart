import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/purchase_status.dart';

class PurchaseStatusBadge extends StatelessWidget {
  const PurchaseStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final PurchaseStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(
      label: status.label,
      tone: _toneForStatus(status),
      icon: compact ? null : _iconForStatus(status),
    );
  }

  AppStatusTone _toneForStatus(PurchaseStatus status) {
    switch (status) {
      case PurchaseStatus.paga:
        return AppStatusTone.success;
      case PurchaseStatus.parcialmentePaga:
        return AppStatusTone.info;
      case PurchaseStatus.cancelada:
        return AppStatusTone.danger;
      case PurchaseStatus.aberta:
        return AppStatusTone.warning;
      case PurchaseStatus.recebida:
        return AppStatusTone.neutral;
      case PurchaseStatus.rascunho:
        return AppStatusTone.neutral;
    }
  }

  IconData _iconForStatus(PurchaseStatus status) {
    switch (status) {
      case PurchaseStatus.paga:
        return Icons.check_circle_outline_rounded;
      case PurchaseStatus.parcialmentePaga:
        return Icons.schedule_rounded;
      case PurchaseStatus.cancelada:
        return Icons.cancel_outlined;
      case PurchaseStatus.aberta:
        return Icons.pending_actions_rounded;
      case PurchaseStatus.recebida:
        return Icons.inventory_2_outlined;
      case PurchaseStatus.rascunho:
        return Icons.edit_note_rounded;
    }
  }
}
