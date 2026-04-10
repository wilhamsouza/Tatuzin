import 'package:sqflite/sqflite.dart';

import '../../../caixa/data/cash_database_support.dart';
import '../../../caixa/domain/entities/cash_enums.dart';
import '../../domain/entities/sale_enums.dart';

class SaleCashEffectsSupport {
  const SaleCashEffectsSupport._();

  static Future<InsertedCashMovement> registerCashSaleReceipt(
    DatabaseExecutor txn, {
    required DateTime timestamp,
    required int? userId,
    required int saleId,
    required int amountCents,
    required String receiptNumber,
    required PaymentMethod paymentMethod,
  }) async {
    final sessionId = await CashDatabaseSupport.ensureOpenSession(
      txn,
      timestamp: timestamp,
      userId: userId,
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      salesDeltaCents: amountCents,
    );
    return CashDatabaseSupport.insertMovement(
      txn,
      sessionId: sessionId,
      type: CashMovementType.sale,
      amountCents: amountCents,
      timestamp: timestamp,
      referenceType: 'venda',
      referenceId: saleId,
      description: 'Venda $receiptNumber recebida via ${paymentMethod.label}.',
      paymentMethod: paymentMethod,
    );
  }

  static Future<InsertedCashMovement> registerSaleCancellation(
    DatabaseExecutor txn, {
    required DateTime timestamp,
    required int? userId,
    required int saleId,
    required int amountCents,
    required String receiptNumber,
    required String reason,
    required PaymentMethod paymentMethod,
  }) async {
    final sessionId = await CashDatabaseSupport.ensureOpenSession(
      txn,
      timestamp: timestamp,
      userId: userId,
      notes:
          'Sessao aberta automaticamente para registrar cancelamento de venda.',
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      salesDeltaCents: -amountCents,
    );
    return CashDatabaseSupport.insertMovement(
      txn,
      sessionId: sessionId,
      type: CashMovementType.cancellation,
      amountCents: -amountCents,
      timestamp: timestamp,
      referenceType: 'venda',
      referenceId: saleId,
      description: 'Cancelamento da venda $receiptNumber. Motivo: ${reason.trim()}',
      paymentMethod: paymentMethod,
    );
  }

  static Future<InsertedCashMovement> registerFiadoReceiptRefund(
    DatabaseExecutor txn, {
    required DateTime timestamp,
    required int? userId,
    required int? fiadoId,
    required int amountCents,
    required String receiptNumber,
    required String reason,
  }) async {
    final sessionId = await CashDatabaseSupport.ensureOpenSession(
      txn,
      timestamp: timestamp,
      userId: userId,
      notes: 'Sessao aberta automaticamente para registrar estorno de fiado.',
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      fiadoReceiptsDeltaCents: -amountCents,
    );
    return CashDatabaseSupport.insertMovement(
      txn,
      sessionId: sessionId,
      type: CashMovementType.cancellation,
      amountCents: -amountCents,
      timestamp: timestamp,
      referenceType: 'fiado',
      referenceId: fiadoId,
      description:
          'Estorno dos recebimentos do fiado da venda $receiptNumber. Motivo: ${reason.trim()}',
    );
  }
}
