enum PurchaseStatus {
  rascunho,
  aberta,
  recebida,
  parcialmentePaga,
  paga,
  cancelada,
}

extension PurchaseStatusX on PurchaseStatus {
  String get dbValue {
    switch (this) {
      case PurchaseStatus.rascunho:
        return 'rascunho';
      case PurchaseStatus.aberta:
        return 'aberta';
      case PurchaseStatus.recebida:
        return 'recebida';
      case PurchaseStatus.parcialmentePaga:
        return 'parcialmente_paga';
      case PurchaseStatus.paga:
        return 'paga';
      case PurchaseStatus.cancelada:
        return 'cancelada';
    }
  }

  String get label {
    switch (this) {
      case PurchaseStatus.rascunho:
        return 'Rascunho';
      case PurchaseStatus.aberta:
        return 'Aberta';
      case PurchaseStatus.recebida:
        return 'Recebida';
      case PurchaseStatus.parcialmentePaga:
        return 'Parcialmente paga';
      case PurchaseStatus.paga:
        return 'Paga';
      case PurchaseStatus.cancelada:
        return 'Cancelada';
    }
  }

  bool get isPendingPayment =>
      this == PurchaseStatus.aberta ||
      this == PurchaseStatus.recebida ||
      this == PurchaseStatus.parcialmentePaga;

  bool get isEditable =>
      this != PurchaseStatus.cancelada && this != PurchaseStatus.paga;

  static PurchaseStatus fromDb(String value) {
    switch (value) {
      case 'rascunho':
        return PurchaseStatus.rascunho;
      case 'aberta':
        return PurchaseStatus.aberta;
      case 'parcialmente_paga':
        return PurchaseStatus.parcialmentePaga;
      case 'paga':
        return PurchaseStatus.paga;
      case 'cancelada':
        return PurchaseStatus.cancelada;
      default:
        return PurchaseStatus.recebida;
    }
  }
}
