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

extension OperationalOrderStatusRules on OperationalOrderStatus {
  bool get isTerminal {
    return this == OperationalOrderStatus.delivered ||
        this == OperationalOrderStatus.canceled;
  }

  bool get allowsItemChanges => !isTerminal;

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

    switch (next) {
      case OperationalOrderStatus.draft:
        return false;
      case OperationalOrderStatus.open:
        return true;
      case OperationalOrderStatus.inPreparation:
        return this != OperationalOrderStatus.draft;
      case OperationalOrderStatus.ready:
        return this == OperationalOrderStatus.inPreparation;
      case OperationalOrderStatus.delivered:
        return this == OperationalOrderStatus.ready;
      case OperationalOrderStatus.canceled:
        return true;
    }
  }
}

class OperationalOrder {
  const OperationalOrder({
    required this.id,
    required this.uuid,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.closedAt,
  });

  final int id;
  final String uuid;
  final OperationalOrderStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;

  bool get isTerminal => status.isTerminal;
  bool get allowsItemChanges => status.allowsItemChanges;
}

class OperationalOrderInput {
  const OperationalOrderInput({
    this.status = OperationalOrderStatus.draft,
    this.notes,
  });

  final OperationalOrderStatus status;
  final String? notes;
}
