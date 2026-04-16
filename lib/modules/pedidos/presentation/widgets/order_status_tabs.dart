import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_selector_chip.dart';
import '../../../../app/theme/app_design_tokens.dart';
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
    final layout = context.appLayout;

    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final status = operationalQueueStatuses[index];
          return AppSelectorChip(
            icon: operationalOrderStatusIcon(status),
            label: operationalOrderStatusLabel(status),
            count: countFor(status),
            selected: status == selectedStatus,
            onSelected: (_) => onChanged(status),
            tone: AppSelectorChipTone.brand,
          );
        },
        separatorBuilder: (_, __) => SizedBox(width: layout.space4),
        itemCount: operationalQueueStatuses.length,
      ),
    );
  }
}
