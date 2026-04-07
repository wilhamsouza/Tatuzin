enum CommercialReceiptRequestType { sale, fiadoPayment }

class CommercialReceiptRequest {
  const CommercialReceiptRequest.sale({required this.saleId})
    : type = CommercialReceiptRequestType.sale,
      fiadoId = null,
      paymentEntryId = null;

  const CommercialReceiptRequest.fiadoPayment({
    required this.fiadoId,
    required this.paymentEntryId,
  }) : type = CommercialReceiptRequestType.fiadoPayment,
       saleId = null;

  final CommercialReceiptRequestType type;
  final int? saleId;
  final int? fiadoId;
  final int? paymentEntryId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is CommercialReceiptRequest &&
        other.type == type &&
        other.saleId == saleId &&
        other.fiadoId == fiadoId &&
        other.paymentEntryId == paymentEntryId;
  }

  @override
  int get hashCode => Object.hash(type, saleId, fiadoId, paymentEntryId);
}
