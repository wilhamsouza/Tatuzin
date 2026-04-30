import '../../../../app/core/constants/app_constants.dart';
import '../../domain/entities/order_ticket_document.dart';
import '../../domain/entities/operational_order_detail.dart';
import '../../domain/services/order_ticket_builder.dart';
import '../../presentation/support/order_ui_support.dart';

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
            variantSku: item.variantSkuSnapshot,
            variantColor: item.variantColorSnapshot,
            variantSize: item.variantSizeSnapshot,
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
          ? operationalOrderSeparationManifestTitle
          : operationalOrderInternalPreviewTitle,
      orderId: detail.order.id,
      status: detail.order.status,
      serviceType: detail.order.serviceType,
      customerIdentifier: detail.order.customerIdentifier,
      customerPhone: detail.order.customerPhone,
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
          operationalOrderSeparationManifestFooter,
        if (profile == OrderTicketProfile.internal)
          operationalOrderInternalPreviewFooter,
      ],
    );
  }
}
