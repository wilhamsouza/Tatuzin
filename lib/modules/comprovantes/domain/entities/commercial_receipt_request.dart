enum CommercialReceiptRequestType { sale, fiadoPayment, customerCredit }

class CommercialReceiptRequest {
  const CommercialReceiptRequest.sale({required this.saleId})
    : type = CommercialReceiptRequestType.sale,
      fiadoId = null,
      paymentEntryId = null,
      transactionId = null;

  const CommercialReceiptRequest.fiadoPayment({
    required this.fiadoId,
    required this.paymentEntryId,
  }) : type = CommercialReceiptRequestType.fiadoPayment,
       saleId = null,
       transactionId = null;

  const CommercialReceiptRequest.customerCredit({required this.transactionId})
    : type = CommercialReceiptRequestType.customerCredit,
      saleId = null,
      fiadoId = null,
      paymentEntryId = null;

  final CommercialReceiptRequestType type;
  final int? saleId;
  final int? fiadoId;
  final int? paymentEntryId;
  final int? transactionId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is CommercialReceiptRequest &&
        other.type == type &&
        other.saleId == saleId &&
        other.fiadoId == fiadoId &&
        other.paymentEntryId == paymentEntryId &&
        other.transactionId == transactionId;
  }

  @override
  int get hashCode =>
      Object.hash(type, saleId, fiadoId, paymentEntryId, transactionId);
}
