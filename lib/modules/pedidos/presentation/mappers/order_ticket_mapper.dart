import '../../../../app/core/formatters/app_formatters.dart';
import '../../domain/entities/operational_order.dart';
import '../providers/order_providers.dart';

class OrderTicketLine {
  const OrderTicketLine({
    required this.title,
    required this.quantityLabel,
    required this.unitPriceLabel,
    required this.totalPriceLabel,
    required this.modifierLines,
    required this.notes,
  });

  final String title;
  final String quantityLabel;
  final String unitPriceLabel;
  final String totalPriceLabel;
  final List<String> modifierLines;
  final String? notes;
}

class OrderTicketViewModel {
  const OrderTicketViewModel({
    required this.orderNumber,
    required this.statusLabel,
    required this.updatedAtLabel,
    required this.headerNotes,
    required this.totalLabel,
    required this.lines,
  });

  final String orderNumber;
  final String statusLabel;
  final String updatedAtLabel;
  final String? headerNotes;
  final String totalLabel;
  final List<OrderTicketLine> lines;
}

abstract final class OrderTicketMapper {
  static OrderTicketViewModel fromDetail(OperationalOrderDetail detail) {
    final lines = detail.items
        .map((itemDetail) {
          final item = itemDetail.item;
          final modifierLines = itemDetail.modifiers
              .map(
                (modifier) =>
                    '- ${modifier.groupNameSnapshot ?? 'Modificador'}: ${modifier.optionNameSnapshot} (${modifier.adjustmentTypeSnapshot})',
              )
              .toList(growable: false);
          return OrderTicketLine(
            title: item.productNameSnapshot,
            quantityLabel: AppFormatters.quantityFromMil(item.quantityMil),
            unitPriceLabel: AppFormatters.currencyFromCents(
              item.unitPriceCents,
            ),
            totalPriceLabel: AppFormatters.currencyFromCents(
              itemDetail.totalCents,
            ),
            modifierLines: modifierLines,
            notes: item.notes,
          );
        })
        .toList(growable: false);

    return OrderTicketViewModel(
      orderNumber: '#${detail.order.id}',
      statusLabel: _statusLabel(detail.order.status),
      updatedAtLabel: AppFormatters.shortDateTime(detail.order.updatedAt),
      headerNotes: detail.order.notes,
      totalLabel: AppFormatters.currencyFromCents(detail.totalCents),
      lines: lines,
    );
  }

  static String _statusLabel(OperationalOrderStatus status) {
    switch (status) {
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
      case OperationalOrderStatus.draft:
        return 'Rascunho';
    }
  }
}
