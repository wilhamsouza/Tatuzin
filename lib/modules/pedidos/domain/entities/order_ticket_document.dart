import '../entities/operational_order.dart';

enum OrderTicketProfile { kitchen, internal }

class OrderTicketDocument {
  const OrderTicketDocument({
    required this.profile,
    required this.businessName,
    required this.title,
    required this.orderId,
    required this.status,
    required this.serviceType,
    required this.customerIdentifier,
    required this.customerPhone,
    required this.createdAt,
    required this.updatedAt,
    required this.orderNotes,
    required this.lineItemsCount,
    required this.totalUnits,
    required this.totalCents,
    required this.showFinancialSummary,
    required this.lines,
    this.footerLines = const <String>[],
  });

  final OrderTicketProfile profile;
  final String? businessName;
  final String title;
  final int orderId;
  final OperationalOrderStatus status;
  final OperationalOrderServiceType serviceType;
  final String? customerIdentifier;
  final String? customerPhone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? orderNotes;
  final int lineItemsCount;
  final int totalUnits;
  final int totalCents;
  final bool showFinancialSummary;
  final List<OrderTicketLine> lines;
  final List<String> footerLines;

  bool get isKitchenProfile => profile == OrderTicketProfile.kitchen;
}

class OrderTicketLine {
  const OrderTicketLine({
    required this.productName,
    required this.quantityMil,
    required this.unitPriceCents,
    required this.totalCents,
    required this.notes,
    required this.modifiers,
  });

  final String productName;
  final int quantityMil;
  final int unitPriceCents;
  final int totalCents;
  final String? notes;
  final List<OrderTicketModifierLine> modifiers;
}

class OrderTicketModifierLine {
  const OrderTicketModifierLine({
    required this.groupName,
    required this.optionName,
    required this.adjustmentType,
    required this.priceDeltaCents,
    required this.quantity,
  });

  final String? groupName;
  final String optionName;
  final String adjustmentType;
  final int priceDeltaCents;
  final int quantity;
}
