enum CashSessionStatus { open, closed }

extension CashSessionStatusX on CashSessionStatus {
  String get dbValue => this == CashSessionStatus.open ? 'aberto' : 'fechado';

  String get label => this == CashSessionStatus.open ? 'Aberto' : 'Fechado';

  static CashSessionStatus fromDb(String value) {
    return value == 'fechado'
        ? CashSessionStatus.closed
        : CashSessionStatus.open;
  }
}

enum CashMovementType {
  sale,
  fiadoReceipt,
  sangria,
  supply,
  adjustment,
  cancellation,
}

extension CashMovementTypeX on CashMovementType {
  String get dbValue {
    switch (this) {
      case CashMovementType.sale:
        return 'venda';
      case CashMovementType.fiadoReceipt:
        return 'recebimento_fiado';
      case CashMovementType.sangria:
        return 'sangria';
      case CashMovementType.supply:
        return 'suprimento';
      case CashMovementType.adjustment:
        return 'ajuste';
      case CashMovementType.cancellation:
        return 'cancelamento';
    }
  }

  String get label {
    switch (this) {
      case CashMovementType.sale:
        return 'Venda';
      case CashMovementType.fiadoReceipt:
        return 'Recebimento de fiado';
      case CashMovementType.sangria:
        return 'Sangria';
      case CashMovementType.supply:
        return 'Suprimento';
      case CashMovementType.adjustment:
        return 'Ajuste';
      case CashMovementType.cancellation:
        return 'Cancelamento';
    }
  }

  static CashMovementType fromDb(String value) {
    switch (value) {
      case 'recebimento_fiado':
        return CashMovementType.fiadoReceipt;
      case 'sangria':
        return CashMovementType.sangria;
      case 'suprimento':
        return CashMovementType.supply;
      case 'ajuste':
        return CashMovementType.adjustment;
      case 'cancelamento':
        return CashMovementType.cancellation;
      default:
        return CashMovementType.sale;
    }
  }
}
