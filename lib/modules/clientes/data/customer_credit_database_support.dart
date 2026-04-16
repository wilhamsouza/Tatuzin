import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../domain/entities/customer_credit_transaction.dart';

abstract final class CustomerCreditDatabaseSupport {
  static Future<int> getCustomerBalance(
    DatabaseExecutor db,
    int customerId,
  ) async {
    final customer = await _loadCustomerRow(db, customerId);
    return customer['credit_balance'] as int? ?? 0;
  }

  static Future<List<CustomerCreditTransaction>> listTransactions(
    DatabaseExecutor db,
    int customerId,
  ) async {
    final customer = await _loadCustomerRow(db, customerId);
    final customerName = customer['nome'] as String?;
    final rows = await db.query(
      TableNames.customerCreditTransactions,
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at ASC, id ASC',
    );

    var runningBalance = 0;
    final computed = <CustomerCreditTransaction>[];
    for (final row in rows) {
      final amount = row['amount'] as int? ?? 0;
      final before = runningBalance;
      final after = before + amount;
      runningBalance = after;
      computed.add(
        CustomerCreditTransaction(
          id: row['id'] as int,
          customerId: row['customer_id'] as int,
          type: row['type'] as String,
          amountCents: amount,
          description: row['description'] as String?,
          saleId: row['sale_id'] as int?,
          fiadoId: row['fiado_id'] as int?,
          cashSessionId: row['cash_session_id'] as int?,
          originPaymentId: row['origin_payment_id'] as int?,
          reversedTransactionId: row['reversed_transaction_id'] as int?,
          isReversed: (row['is_reversed'] as int? ?? 0) == 1,
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: row['updated_at'] == null
              ? null
              : DateTime.parse(row['updated_at'] as String),
          balanceBeforeCents: before,
          balanceAfterCents: after,
          customerName: customerName,
        ),
      );
    }

    return computed.reversed.toList(growable: false);
  }

  static Future<CustomerCreditTransaction> getTransactionById(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final row = await _loadTransactionRow(db, transactionId);
    final customerId = row['customer_id'] as int;
    final transactions = await listTransactions(db, customerId);
    return transactions.firstWhere(
      (transaction) => transaction.id == transactionId,
      orElse: () => throw const ValidationException(
        'Lancamento de haver nao foi encontrado.',
      ),
    );
  }

  static Future<CustomerCreditTransaction> addManualCredit(
    DatabaseExecutor db, {
    required int customerId,
    required int amountCents,
    String? description,
  }) {
    return _insertTransaction(
      db,
      customerId: customerId,
      type: CustomerCreditTransactionType.manualCredit,
      amountCents: amountCents.abs(),
      description: description ?? 'Credito manual lançado.',
    );
  }

  static Future<CustomerCreditTransaction> addManualDebit(
    DatabaseExecutor db, {
    required int customerId,
    required int amountCents,
    String? description,
  }) {
    return _insertTransaction(
      db,
      customerId: customerId,
      type: CustomerCreditTransactionType.manualDebit,
      amountCents: -amountCents.abs(),
      description: description ?? 'Debito manual lançado.',
    );
  }

  static Future<CustomerCreditTransaction> applyCreditToSale(
    DatabaseExecutor db, {
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  }) {
    return _insertUniqueOriginTransaction(
      db,
      customerId: customerId,
      type: CustomerCreditTransactionType.creditUsedInSale,
      amountCents: -amountCents.abs(),
      description: description ?? 'Haver usado na venda.',
      saleId: saleId,
    );
  }

  static Future<CustomerCreditTransaction> createCreditFromOverpayment(
    DatabaseExecutor db, {
    required int customerId,
    required int amountCents,
    String? description,
    int? saleId,
    int? fiadoId,
    int? cashSessionId,
    int? originPaymentId,
    String type = CustomerCreditTransactionType.overpaymentCredit,
  }) {
    return _insertUniqueOriginTransaction(
      db,
      customerId: customerId,
      type: type,
      amountCents: amountCents.abs(),
      description: description ?? 'Credito gerado automaticamente.',
      saleId: saleId,
      fiadoId: fiadoId,
      cashSessionId: cashSessionId,
      originPaymentId: originPaymentId,
    );
  }

  static Future<CustomerCreditTransaction> createCreditFromSaleCancel(
    DatabaseExecutor db, {
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  }) {
    return _insertUniqueOriginTransaction(
      db,
      customerId: customerId,
      type: CustomerCreditTransactionType.saleCancelCredit,
      amountCents: amountCents.abs(),
      description:
          description ?? 'Cancelamento convertido em haver para o cliente.',
      saleId: saleId,
    );
  }

  static Future<CustomerCreditTransaction> createCreditFromSaleReturn(
    DatabaseExecutor db, {
    required int customerId,
    required int saleId,
    required int amountCents,
    String? description,
  }) {
    return _insertTransaction(
      db,
      customerId: customerId,
      type: CustomerCreditTransactionType.saleReturnCredit,
      amountCents: amountCents.abs(),
      description:
          description ?? 'Devolucao convertida em haver para o cliente.',
      saleId: saleId,
    );
  }

  static Future<CustomerCreditTransaction> reverseCreditTransaction(
    DatabaseExecutor db, {
    required int transactionId,
    String? description,
  }) async {
    final original = await _loadTransactionRow(db, transactionId);
    if ((original['is_reversed'] as int? ?? 0) == 1) {
      throw const ValidationException(
        'Este lancamento de haver ja foi estornado.',
      );
    }

    final existingReversalRows = await db.query(
      TableNames.customerCreditTransactions,
      where: 'reversed_transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (existingReversalRows.isNotEmpty) {
      return getTransactionById(db, existingReversalRows.first['id'] as int);
    }

    final now = DateTime.now();
    await db.update(
      TableNames.customerCreditTransactions,
      {'is_reversed': 1, 'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [transactionId],
    );

    return _insertTransaction(
      db,
      customerId: original['customer_id'] as int,
      type: CustomerCreditTransactionType.creditReversal,
      amountCents: -(original['amount'] as int? ?? 0),
      description: description ?? 'Estorno do lancamento de haver.',
      saleId: original['sale_id'] as int?,
      fiadoId: original['fiado_id'] as int?,
      cashSessionId: original['cash_session_id'] as int?,
      originPaymentId: original['origin_payment_id'] as int?,
      reversedTransactionId: transactionId,
    );
  }

  static Future<CustomerCreditTransaction> _insertUniqueOriginTransaction(
    DatabaseExecutor db, {
    required int customerId,
    required String type,
    required int amountCents,
    String? description,
    int? saleId,
    int? fiadoId,
    int? cashSessionId,
    int? originPaymentId,
  }) async {
    final existingRows = await db.query(
      TableNames.customerCreditTransactions,
      where:
          'customer_id = ? AND type = ? AND '
          'COALESCE(sale_id, 0) = COALESCE(?, 0) AND '
          'COALESCE(fiado_id, 0) = COALESCE(?, 0) AND '
          'COALESCE(origin_payment_id, 0) = COALESCE(?, 0)',
      whereArgs: [customerId, type, saleId, fiadoId, originPaymentId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      return getTransactionById(db, existingRows.first['id'] as int);
    }

    return _insertTransaction(
      db,
      customerId: customerId,
      type: type,
      amountCents: amountCents,
      description: description,
      saleId: saleId,
      fiadoId: fiadoId,
      cashSessionId: cashSessionId,
      originPaymentId: originPaymentId,
    );
  }

  static Future<CustomerCreditTransaction> _insertTransaction(
    DatabaseExecutor db, {
    required int customerId,
    required String type,
    required int amountCents,
    String? description,
    int? saleId,
    int? fiadoId,
    int? cashSessionId,
    int? originPaymentId,
    int? reversedTransactionId,
  }) async {
    if (amountCents == 0) {
      throw const ValidationException(
        'O valor do lancamento de haver precisa ser maior que zero.',
      );
    }

    final customer = await _loadCustomerRow(db, customerId);
    final previousBalance = customer['credit_balance'] as int? ?? 0;
    final nextBalance = previousBalance + amountCents;
    if (nextBalance < 0) {
      throw const ValidationException(
        'O debito informado excede o saldo de haver disponivel.',
      );
    }

    final now = DateTime.now();
    final id = await db.insert(TableNames.customerCreditTransactions, {
      'customer_id': customerId,
      'type': type,
      'amount': amountCents,
      'description': _cleanNullable(description),
      'sale_id': saleId,
      'fiado_id': fiadoId,
      'cash_session_id': cashSessionId,
      'origin_payment_id': originPaymentId,
      'reversed_transaction_id': reversedTransactionId,
      'is_reversed': 0,
      'created_at': now.toIso8601String(),
      'updated_at': null,
    });

    await db.update(
      TableNames.clientes,
      {'credit_balance': nextBalance, 'atualizado_em': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [customerId],
    );

    return CustomerCreditTransaction(
      id: id,
      customerId: customerId,
      type: type,
      amountCents: amountCents,
      description: _cleanNullable(description),
      saleId: saleId,
      fiadoId: fiadoId,
      cashSessionId: cashSessionId,
      originPaymentId: originPaymentId,
      reversedTransactionId: reversedTransactionId,
      isReversed: false,
      createdAt: now,
      updatedAt: null,
      balanceBeforeCents: previousBalance,
      balanceAfterCents: nextBalance,
      customerName: customer['nome'] as String?,
    );
  }

  static Future<Map<String, Object?>> _loadCustomerRow(
    DatabaseExecutor db,
    int customerId,
  ) async {
    final rows = await db.query(
      TableNames.clientes,
      columns: ['id', 'nome', 'credit_balance', 'deletado_em'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['deletado_em'] != null) {
      throw const ValidationException('Cliente nao esta disponivel.');
    }
    return rows.first;
  }

  static Future<Map<String, Object?>> _loadTransactionRow(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final rows = await db.query(
      TableNames.customerCreditTransactions,
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ValidationException('Lancamento de haver nao encontrado.');
    }
    return rows.first;
  }

  static String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
