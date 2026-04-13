import 'package:flutter/material.dart';

import '../../domain/entities/operational_order.dart';
import '../../domain/services/order_status_rules.dart';
import '../support/order_ui_support.dart';

class OrderStatusTabs extends StatelessWidget {
  const OrderStatusTabs({
    super.key,
    required this.selectedStatus,
    required this.countFor,
    required this.onChanged,
  });

  final OperationalOrderStatus selectedStatus;
  final int Function(OperationalOrderStatus status) countFor;
  final ValueChanged<OperationalOrderStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final status = operationalQueueStatuses[index];
          final selected = status == selectedStatus;
          return ChoiceChip(
            avatar: Icon(operationalOrderStatusIcon(status), size: 18),
            label: Text(
              '${operationalOrderStatusLabel(status)} (${countFor(status)})',
            ),
            selected: selected,
            onSelected: (_) => onChanged(status),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: operationalQueueStatuses.length,
      ),
    );
  }
}
