class CustomerCreditTransactionType {
  const CustomerCreditTransactionType._();

  static const manualCredit = 'manual_credit';
  static const manualDebit = 'manual_debit';
  static const overpaymentCredit = 'overpayment_credit';
  static const saleReturnCredit = 'sale_return_credit';
  static const saleCancelCredit = 'sale_cancel_credit';
  static const changeLeftAsCredit = 'change_left_as_credit';
  static const creditUsedInSale = 'credit_used_in_sale';
  static const creditReversal = 'credit_reversal';
}

class CustomerCreditTransaction {
  const CustomerCreditTransaction({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amountCents,
    required this.description,
    required this.saleId,
    required this.fiadoId,
    required this.cashSessionId,
    required this.originPaymentId,
    required this.reversedTransactionId,
    required this.isReversed,
    required this.createdAt,
    required this.updatedAt,
    required this.balanceBeforeCents,
    required this.balanceAfterCents,
    this.customerName,
  });

  final int id;
  final int customerId;
  final String type;
  final int amountCents;
  final String? description;
  final int? saleId;
  final int? fiadoId;
  final int? cashSessionId;
  final int? originPaymentId;
  final int? reversedTransactionId;
  final bool isReversed;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int balanceBeforeCents;
  final int balanceAfterCents;
  final String? customerName;

  bool get isCredit => amountCents > 0;
  bool get isDebit => amountCents < 0;
  int get absoluteAmountCents => amountCents.abs();
}
