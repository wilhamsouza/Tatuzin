import '../../../../app/core/constants/app_constants.dart';
import '../../domain/entities/order_ticket_document.dart';
import '../../domain/entities/operational_order_detail.dart';
import '../../domain/services/order_ticket_builder.dart';

class DefaultOrderTicketBuilder implements OrderTicketBuilder {
  const DefaultOrderTicketBuilder();

  @override
  OrderTicketDocument build({
    required OperationalOrderDetail detail,
    required OrderTicketProfile profile,
  }) {
    final lines = detail.items
        .map((itemDetail) {
          final item = itemDetail.item;
          return OrderTicketLine(
            productName: item.productNameSnapshot,
            quantityMil: item.quantityMil,
            unitPriceCents: item.unitPriceCents,
            totalCents: itemDetail.totalCents,
            notes: item.notes,
            modifiers: itemDetail.modifiers
                .map(
                  (modifier) => OrderTicketModifierLine(
                    groupName: modifier.groupNameSnapshot,
                    optionName: modifier.optionNameSnapshot,
                    adjustmentType: modifier.adjustmentTypeSnapshot,
                    priceDeltaCents: modifier.priceDeltaCents,
                    quantity: modifier.quantity,
                  ),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);

    return OrderTicketDocument(
      profile: profile,
      businessName: AppConstants.defaultLocalCompanyName,
      title: profile == OrderTicketProfile.kitchen
          ? 'PEDIDO COZINHA'
          : 'TICKET OPERACIONAL',
      orderId: detail.order.id,
      status: detail.order.status,
      createdAt: detail.order.createdAt,
      updatedAt: detail.order.updatedAt,
      orderNotes: detail.order.notes,
      lineItemsCount: detail.lineItemsCount,
      totalUnits: detail.totalUnits,
      totalCents: detail.totalCents,
      showFinancialSummary: profile == OrderTicketProfile.internal,
      lines: lines,
      footerLines: <String>[
        if (profile == OrderTicketProfile.kitchen)
          'Uso interno da cozinha. Nao entregar ao cliente.',
        if (profile == OrderTicketProfile.internal)
          'Ticket interno. O comprovante comercial permanece no modulo de comprovantes.',
      ],
    );
  }
}
