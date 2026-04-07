enum SaleType { cash, fiado }

extension SaleTypeX on SaleType {
  String get dbValue => this == SaleType.cash ? 'vista' : 'fiado';

  String get label => this == SaleType.cash ? 'À vista' : 'Fiado';

  bool get isCredit => this == SaleType.fiado;

  static SaleType fromDb(String value) {
    return value == 'fiado' ? SaleType.fiado : SaleType.cash;
  }
}

enum PaymentMethod { cash, pix, card, fiado }

extension PaymentMethodX on PaymentMethod {
  String get dbValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'dinheiro';
      case PaymentMethod.pix:
        return 'pix';
      case PaymentMethod.card:
        return 'cartao';
      case PaymentMethod.fiado:
        return 'fiado';
    }
  }

  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Dinheiro';
      case PaymentMethod.pix:
        return 'Pix';
      case PaymentMethod.card:
        return 'Cartão';
      case PaymentMethod.fiado:
        return 'Fiado';
    }
  }

  bool get isImmediateReceipt => this != PaymentMethod.fiado;

  static PaymentMethod fromDb(String value) {
    switch (value) {
      case 'pix':
        return PaymentMethod.pix;
      case 'cartao':
        return PaymentMethod.card;
      case 'fiado':
        return PaymentMethod.fiado;
      default:
        return PaymentMethod.cash;
    }
  }
}

enum SaleStatus { active, cancelled }

extension SaleStatusX on SaleStatus {
  String get dbValue => this == SaleStatus.active ? 'ativa' : 'cancelada';

  String get label => this == SaleStatus.active ? 'Ativa' : 'Cancelada';

  static SaleStatus fromDb(String value) {
    return value == 'cancelada' ? SaleStatus.cancelled : SaleStatus.active;
  }
}
