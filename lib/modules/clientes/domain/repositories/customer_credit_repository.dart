import '../entities/customer_credit_transaction.dart';

abstract interface class CustomerCreditRepository {
  Future<int> getCustomerCreditBalance(int customerId);

  Future<List<CustomerCreditTransaction>> getCustomerCreditTransactions(
    int customerId,
  );

  Future<CustomerCreditTransaction> getTransactionById(int transactionId);

  Future<CustomerCreditTransaction> addManualCredit({
    required int customerId,
    required int amountCents,
    String? description,
  });

  Future<CustomerCreditTransaction> addManualDebit({
    required int customerId,
    required int amountCents,
    String? description,
  });

  Future<CustomerCreditTransaction> applyCreditToSale({
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  });

  Future<CustomerCreditTransaction> createCreditFromOverpayment({
    required int customerId,
    required int amountCents,
    String? description,
    int? saleId,
    int? fiadoId,
    int? cashSessionId,
    int? originPaymentId,
    String type = CustomerCreditTransactionType.overpaymentCredit,
  });

  Future<CustomerCreditTransaction> createCreditFromSaleCancel({
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  });

  Future<CustomerCreditTransaction> reverseCreditTransaction({
    required int transactionId,
    String? description,
  });
}
