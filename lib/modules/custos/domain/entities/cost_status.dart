enum CostStatus { pending, paid, canceled }

extension CostStatusX on CostStatus {
  String get dbValue {
    switch (this) {
      case CostStatus.pending:
        return 'pending';
      case CostStatus.paid:
        return 'paid';
      case CostStatus.canceled:
        return 'canceled';
    }
  }

  String get label {
    switch (this) {
      case CostStatus.pending:
        return 'Pendente';
      case CostStatus.paid:
        return 'Pago';
      case CostStatus.canceled:
        return 'Cancelado';
    }
  }

  static CostStatus fromDb(String value) {
    switch (value) {
      case 'paid':
        return CostStatus.paid;
      case 'canceled':
        return CostStatus.canceled;
      default:
        return CostStatus.pending;
    }
  }
}
