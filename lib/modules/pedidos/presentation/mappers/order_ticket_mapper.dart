import '../../../../app/core/formatters/app_formatters.dart';
import '../../domain/entities/order_ticket_document.dart';
import '../support/order_ui_support.dart';

class OrderTicketInfoLine {
  const OrderTicketInfoLine({required this.label, required this.value});

  final String label;
  final String value;
}

class OrderTicketLineViewModel {
  const OrderTicketLineViewModel({
    required this.title,
    required this.quantityLabel,
    required this.summaryLabel,
    required this.modifierLines,
    required this.notes,
    required this.totalLabel,
  });

  final String title;
  final String quantityLabel;
  final String summaryLabel;
  final List<String> modifierLines;
  final String? notes;
  final String? totalLabel;
}

class OrderTicketViewModel {
  const OrderTicketViewModel({
    required this.title,
    required this.profileLabel,
    required this.businessName,
    required this.orderNumber,
    required this.statusLabel,
    required this.headerNotes,
    required this.infoLines,
    required this.lines,
    required this.footerLines,
    required this.totalLabel,
    required this.showFinancialSummary,
  });

  final String title;
  final String profileLabel;
  final String? businessName;
  final String orderNumber;
  final String statusLabel;
  final String? headerNotes;
  final List<OrderTicketInfoLine> infoLines;
  final List<OrderTicketLineViewModel> lines;
  final List<String> footerLines;
  final String totalLabel;
  final bool showFinancialSummary;
}

abstract final class OrderTicketMapper {
  static OrderTicketViewModel fromDocument(OrderTicketDocument ticket) {
    final lines = ticket.lines
        .map((line) {
          final modifierLines = line.modifiers
              .map((modifier) {
                final parts = <String>[
                  if (modifier.groupName?.trim().isNotEmpty ?? false)
                    '${modifier.groupName}:',
                  modifier.optionName,
                ];
                if (ticket.showFinancialSummary &&
                    modifier.priceDeltaCents != 0) {
                  parts.add(
                    AppFormatters.currencyFromCents(modifier.priceDeltaCents),
                  );
                }
                return parts.join(' ');
              })
              .toList(growable: false);

          return OrderTicketLineViewModel(
            title: line.productName,
            quantityLabel: AppFormatters.quantityFromMil(line.quantityMil),
            summaryLabel: ticket.showFinancialSummary
                ? '${AppFormatters.quantityFromMil(line.quantityMil)} x ${AppFormatters.currencyFromCents(line.unitPriceCents)}'
                : 'Quantidade ${AppFormatters.quantityFromMil(line.quantityMil)}',
            modifierLines: modifierLines,
            notes: line.notes,
            totalLabel: ticket.showFinancialSummary
                ? AppFormatters.currencyFromCents(line.totalCents)
                : null,
          );
        })
        .toList(growable: false);

    return OrderTicketViewModel(
      title: ticket.title,
      profileLabel: ticket.isKitchenProfile ? 'Cozinha' : 'Interno',
      businessName: ticket.businessName,
      orderNumber: '#${ticket.orderId}',
      statusLabel: operationalOrderStatusLabel(ticket.status),
      headerNotes: ticket.orderNotes,
      infoLines: [
        OrderTicketInfoLine(
          label: 'Criado em',
          value: AppFormatters.shortDateTime(ticket.createdAt),
        ),
        OrderTicketInfoLine(
          label: 'Atualizado em',
          value: AppFormatters.shortDateTime(ticket.updatedAt),
        ),
        OrderTicketInfoLine(
          label: 'Status',
          value: operationalOrderStatusLabel(ticket.status),
        ),
        OrderTicketInfoLine(label: 'Itens', value: '${ticket.totalUnits}'),
        if (ticket.showFinancialSummary)
          OrderTicketInfoLine(
            label: 'Total',
            value: AppFormatters.currencyFromCents(ticket.totalCents),
          ),
      ],
      lines: lines,
      footerLines: ticket.footerLines,
      totalLabel: AppFormatters.currencyFromCents(ticket.totalCents),
      showFinancialSummary: ticket.showFinancialSummary,
    );
  }
}
