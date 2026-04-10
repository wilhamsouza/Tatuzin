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
}

class OperationalOrderInput {
  const OperationalOrderInput({
    this.status = OperationalOrderStatus.draft,
    this.notes,
  });

  final OperationalOrderStatus status;
  final String? notes;
}
