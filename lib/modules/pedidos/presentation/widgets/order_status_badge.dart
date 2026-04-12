import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/entities/operational_order.dart';
import '../support/order_ui_support.dart';

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
  });

  final OperationalOrderStatus status;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(
      label: operationalOrderStatusLabel(status),
      tone: operationalOrderStatusTone(status),
      icon: showIcon ? operationalOrderStatusIcon(status) : null,
    );
  }
}
