import '../entities/operational_order.dart';
import '../entities/operational_order_summary.dart';

const operationalQueueStatuses = <OperationalOrderStatus>[
  OperationalOrderStatus.draft,
  OperationalOrderStatus.open,
  OperationalOrderStatus.inPreparation,
  OperationalOrderStatus.ready,
  OperationalOrderStatus.delivered,
  OperationalOrderStatus.canceled,
];

enum OperationalOrderAction {
  open,
  sendToKitchen,
  reprint,
  markInPreparation,
  markReady,
  markDelivered,
  invoice,
  cancel,
}

abstract final class OperationalOrderFlow {
  static bool canSendToKitchen({
    required OperationalOrderStatus status,
    required bool hasItems,
  }) {
    return status == OperationalOrderStatus.draft && hasItems;
  }

  static bool canReprint(OperationalOrderStatus status) {
    return status != OperationalOrderStatus.draft &&
        status != OperationalOrderStatus.canceled;
  }

  static bool canInvoice({
    required OperationalOrderStatus status,
    required bool hasItems,
    required bool hasLinkedSale,
  }) {
    return status == OperationalOrderStatus.delivered &&
        hasItems &&
        !hasLinkedSale;
  }

  static List<OperationalOrderAction> actionsForSummary(
    OperationalOrderSummary summary,
  ) {
    return actionsFor(
      status: summary.order.status,
      hasItems: summary.lineItemsCount > 0,
      hasLinkedSale: summary.hasLinkedSale,
    );
  }

  static List<OperationalOrderAction> actionsFor({
    required OperationalOrderStatus status,
    required bool hasItems,
    required bool hasLinkedSale,
  }) {
    final actions = <OperationalOrderAction>[OperationalOrderAction.open];

    if (canSendToKitchen(status: status, hasItems: hasItems)) {
      actions.add(OperationalOrderAction.sendToKitchen);
    }
    if (canReprint(status)) {
      actions.add(OperationalOrderAction.reprint);
    }
    if (status.canTransitionTo(OperationalOrderStatus.inPreparation)) {
      actions.add(OperationalOrderAction.markInPreparation);
    }
    if (status.canTransitionTo(OperationalOrderStatus.ready)) {
      actions.add(OperationalOrderAction.markReady);
    }
    if (status.canTransitionTo(OperationalOrderStatus.delivered)) {
      actions.add(OperationalOrderAction.markDelivered);
    }
    if (canInvoice(
      status: status,
      hasItems: hasItems,
      hasLinkedSale: hasLinkedSale,
    )) {
      actions.add(OperationalOrderAction.invoice);
    }
    if (!status.isTerminal) {
      actions.add(OperationalOrderAction.cancel);
    }

    return actions;
  }
}
