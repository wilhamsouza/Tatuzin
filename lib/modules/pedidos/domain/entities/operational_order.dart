enum OperationalOrderStatus {
  draft,
  open,
  inPreparation,
  ready,
  delivered,
  canceled,
}

extension OperationalOrderStatusX on OperationalOrderStatus {
  String get dbValue {
    switch (this) {
      case OperationalOrderStatus.draft:
        return 'draft';
      case OperationalOrderStatus.open:
        return 'open';
      case OperationalOrderStatus.inPreparation:
        return 'in_preparation';
      case OperationalOrderStatus.ready:
        return 'ready';
      case OperationalOrderStatus.delivered:
        return 'delivered';
      case OperationalOrderStatus.canceled:
        return 'canceled';
    }
  }

  static OperationalOrderStatus fromDb(String value) {
    switch (value) {
      case 'open':
        return OperationalOrderStatus.open;
      case 'in_preparation':
        return OperationalOrderStatus.inPreparation;
      case 'ready':
        return OperationalOrderStatus.ready;
      case 'delivered':
        return OperationalOrderStatus.delivered;
      case 'canceled':
        return OperationalOrderStatus.canceled;
      default:
        return OperationalOrderStatus.draft;
    }
  }
}

enum OperationalOrderServiceType { counter, pickup, delivery, table }

extension OperationalOrderServiceTypeX on OperationalOrderServiceType {
  String get dbValue {
    switch (this) {
      case OperationalOrderServiceType.counter:
        return 'counter';
      case OperationalOrderServiceType.pickup:
        return 'pickup';
      case OperationalOrderServiceType.delivery:
        return 'delivery';
      case OperationalOrderServiceType.table:
        return 'table';
    }
  }

  static OperationalOrderServiceType fromDb(String? value) {
    switch (value) {
      case 'pickup':
        return OperationalOrderServiceType.pickup;
      case 'delivery':
        return OperationalOrderServiceType.delivery;
      case 'table':
        return OperationalOrderServiceType.table;
      default:
        return OperationalOrderServiceType.counter;
    }
  }
}

enum OrderTicketDispatchStatus { pending, sent, failed }

extension OrderTicketDispatchStatusX on OrderTicketDispatchStatus {
  String get dbValue {
    switch (this) {
      case OrderTicketDispatchStatus.pending:
        return 'pending';
      case OrderTicketDispatchStatus.sent:
        return 'sent';
      case OrderTicketDispatchStatus.failed:
        return 'failed';
    }
  }

  static OrderTicketDispatchStatus fromDb(String? value) {
    switch (value) {
      case 'sent':
        return OrderTicketDispatchStatus.sent;
      case 'failed':
        return OrderTicketDispatchStatus.failed;
      default:
        return OrderTicketDispatchStatus.pending;
    }
  }
}

extension OperationalOrderStatusRules on OperationalOrderStatus {
  bool get isTerminal {
    return this == OperationalOrderStatus.delivered ||
        this == OperationalOrderStatus.canceled;
  }

  bool get allowsItemChanges {
    return this == OperationalOrderStatus.draft ||
        this == OperationalOrderStatus.open;
  }

  bool canTransitionTo(OperationalOrderStatus next) {
    if (this == next) {
      return true;
    }

    if (isTerminal) {
      return false;
    }

    if (next == OperationalOrderStatus.canceled) {
      return true;
    }

    switch (this) {
      case OperationalOrderStatus.draft:
        return next == OperationalOrderStatus.open;
      case OperationalOrderStatus.open:
        return next == OperationalOrderStatus.inPreparation;
      case OperationalOrderStatus.inPreparation:
        return next == OperationalOrderStatus.ready;
      case OperationalOrderStatus.ready:
        return next == OperationalOrderStatus.delivered;
      case OperationalOrderStatus.delivered:
      case OperationalOrderStatus.canceled:
        return false;
    }
  }
}

class OperationalOrderTicketMeta {
  const OperationalOrderTicketMeta({
    required this.status,
    required this.dispatchAttempts,
    required this.lastAttemptAt,
    required this.lastSentAt,
    required this.lastFailureMessage,
  });

  final OrderTicketDispatchStatus status;
  final int dispatchAttempts;
  final DateTime? lastAttemptAt;
  final DateTime? lastSentAt;
  final String? lastFailureMessage;

  bool get hasFailure =>
      status == OrderTicketDispatchStatus.failed &&
      (lastFailureMessage?.trim().isNotEmpty ?? false);
}

class OperationalOrder {
  const OperationalOrder({
    required this.id,
    required this.uuid,
    required this.status,
    required this.serviceType,
    required this.customerIdentifier,
    required this.customerPhone,
    required this.notes,
    required this.ticketMeta,
    required this.createdAt,
    required this.updatedAt,
    required this.sentToKitchenAt,
    required this.preparationStartedAt,
    required this.readyAt,
    required this.deliveredAt,
    required this.canceledAt,
    required this.closedAt,
  });

  final int id;
  final String uuid;
  final OperationalOrderStatus status;
  final OperationalOrderServiceType serviceType;
  final String? customerIdentifier;
  final String? customerPhone;
  final String? notes;
  final OperationalOrderTicketMeta ticketMeta;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? sentToKitchenAt;
  final DateTime? preparationStartedAt;
  final DateTime? readyAt;
  final DateTime? deliveredAt;
  final DateTime? canceledAt;
  final DateTime? closedAt;

  bool get isTerminal => status.isTerminal;
  bool get allowsItemChanges => status.allowsItemChanges;
  bool get canBeInvoiced => status == OperationalOrderStatus.delivered;

  String get customerLabel {
    final trimmed = customerIdentifier?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Sem identificacao';
  }
}

class OperationalOrderInput {
  const OperationalOrderInput({
    this.status = OperationalOrderStatus.draft,
    this.serviceType = OperationalOrderServiceType.counter,
    this.customerIdentifier,
    this.customerPhone,
    this.notes,
  });

  final OperationalOrderStatus status;
  final OperationalOrderServiceType serviceType;
  final String? customerIdentifier;
  final String? customerPhone;
  final String? notes;
}

class OperationalOrderDraftInput {
  const OperationalOrderDraftInput({
    required this.serviceType,
    this.customerIdentifier,
    this.customerPhone,
    this.notes,
  });

  final OperationalOrderServiceType serviceType;
  final String? customerIdentifier;
  final String? customerPhone;
  final String? notes;
}
