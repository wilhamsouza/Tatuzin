import '../../../app/core/database/app_database.dart';
import '../domain/entities/customer_credit_transaction.dart';
import '../domain/repositories/customer_credit_repository.dart';
import 'customer_credit_database_support.dart';

class SqliteCustomerCreditRepository implements CustomerCreditRepository {
  SqliteCustomerCreditRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<CustomerCreditTransaction> addManualCredit({
    required int customerId,
    required int amountCents,
    String? description,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) {
      return CustomerCreditDatabaseSupport.addManualCredit(
        txn,
        customerId: customerId,
        amountCents: amountCents,
        description: description,
      );
    });
  }

  @override
  Future<CustomerCreditTransaction> addManualDebit({
    required int customerId,
    required int amountCents,
    String? description,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) {
      return CustomerCreditDatabaseSupport.addManualDebit(
        txn,
        customerId: customerId,
        amountCents: amountCents,
        description: description,
      );
    });
  }

  @override
  Future<CustomerCreditTransaction> applyCreditToSale({
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) {
      return CustomerCreditDatabaseSupport.applyCreditToSale(
        txn,
        customerId: customerId,
        saleId: saleId,
        amountCents: amountCents,
        description: description,
      );
    });
  }

  @override
  Future<CustomerCreditTransaction> createCreditFromOverpayment({
    required int customerId,
    required int amountCents,
    String? description,
    int? saleId,
    int? fiadoId,
    int? cashSessionId,
    int? originPaymentId,
    String type = CustomerCreditTransactionType.overpaymentCredit,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) {
      return CustomerCreditDatabaseSupport.createCreditFromOverpayment(
        txn,
        customerId: customerId,
        amountCents: amountCents,
        description: description,
        saleId: saleId,
        fiadoId: fiadoId,
        cashSessionId: cashSessionId,
        originPaymentId: originPaymentId,
        type: type,
      );
    });
  }

  @override
  Future<CustomerCreditTransaction> createCreditFromSaleCancel({
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) {
      return CustomerCreditDatabaseSupport.createCreditFromSaleCancel(
        txn,
        customerId: customerId,
        saleId: saleId,
        amountCents: amountCents,
        description: description,
      );
    });
  }

  @override
  Future<int> getCustomerCreditBalance(int customerId) async {
    final database = await _appDatabase.database;
    return CustomerCreditDatabaseSupport.getCustomerBalance(
      database,
      customerId,
    );
  }

  @override
  Future<List<CustomerCreditTransaction>> getCustomerCreditTransactions(
    int customerId,
  ) async {
    final database = await _appDatabase.database;
    return CustomerCreditDatabaseSupport.listTransactions(database, customerId);
  }

  @override
  Future<CustomerCreditTransaction> getTransactionById(
    int transactionId,
  ) async {
    final database = await _appDatabase.database;
    return CustomerCreditDatabaseSupport.getTransactionById(
      database,
      transactionId,
    );
  }

  @override
  Future<CustomerCreditTransaction> reverseCreditTransaction({
    required int transactionId,
    String? description,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((txn) {
      return CustomerCreditDatabaseSupport.reverseCreditTransaction(
        txn,
        transactionId: transactionId,
        description: description,
      );
    });
  }
}
