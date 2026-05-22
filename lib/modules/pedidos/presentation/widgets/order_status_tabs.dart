import 'package:flutter/material.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_selector_chip.dart';
import '../providers/order_providers.dart';

class OrderStatusTabs extends StatelessWidget {
  const OrderStatusTabs({
    super.key,
    required this.selectedFilter,
    required this.countFor,
    required this.onChanged,
  });

  final OperationalOrderListFilter selectedFilter;
  final int Function(OperationalOrderListFilter filter) countFor;
  final ValueChanged<OperationalOrderListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          return AppSelectorChip(
            icon: _icon(filter),
            label: _label(filter),
            count: countFor(filter),
            selected: filter == selectedFilter,
            onSelected: (_) => onChanged(filter),
            tone: AppSelectorChipTone.brand,
          );
        },
        separatorBuilder: (_, __) => SizedBox(width: layout.space3),
        itemCount: _filters.length,
      ),
    );
  }
}

const _filters = <OperationalOrderListFilter>[
  OperationalOrderListFilter.all,
  OperationalOrderListFilter.pending,
  OperationalOrderListFilter.separation,
  OperationalOrderListFilter.fiado,
  OperationalOrderListFilter.completed,
  OperationalOrderListFilter.canceled,
];

String _label(OperationalOrderListFilter filter) {
  switch (filter) {
    case OperationalOrderListFilter.all:
      return 'Todos';
    case OperationalOrderListFilter.pending:
      return 'Pendente/Aberto';
    case OperationalOrderListFilter.separation:
      return 'Separacao';
    case OperationalOrderListFilter.fiado:
      return 'Fiado';
    case OperationalOrderListFilter.completed:
      return 'Concluido';
    case OperationalOrderListFilter.canceled:
      return 'Cancelado';
  }
}

IconData _icon(OperationalOrderListFilter filter) {
  switch (filter) {
    case OperationalOrderListFilter.all:
      return Icons.receipt_long_rounded;
    case OperationalOrderListFilter.pending:
      return Icons.pending_actions_rounded;
    case OperationalOrderListFilter.separation:
      return Icons.inventory_2_rounded;
    case OperationalOrderListFilter.fiado:
      return Icons.account_balance_wallet_rounded;
    case OperationalOrderListFilter.completed:
      return Icons.check_circle_rounded;
    case OperationalOrderListFilter.canceled:
      return Icons.cancel_rounded;
  }
}
