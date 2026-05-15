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
    final sessionId = await CashDatabaseSupport.requireOpenSessionIdWithMessage(
      txn,
      message: paymentMethod == PaymentMethod.cash
          ? 'Abra o caixa antes de registrar venda em dinheiro.'
          : 'Abra o caixa antes de concluir uma venda com recebimento imediato.',
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      cashEntriesDeltaCents: paymentMethod == PaymentMethod.cash
          ? amountCents
          : 0,
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
    final sessionId = await CashDatabaseSupport.requireOpenSessionIdWithMessage(
      txn,
      message:
          'Abra o caixa antes de cancelar uma venda com estorno financeiro.',
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      cashEntriesDeltaCents: paymentMethod == PaymentMethod.cash
          ? -amountCents
          : 0,
    );
    return CashDatabaseSupport.insertMovement(
      txn,
      sessionId: sessionId,
      type: CashMovementType.cancellation,
      amountCents: -amountCents,
      timestamp: timestamp,
      referenceType: 'venda',
      referenceId: saleId,
      description:
          'Cancelamento da venda $receiptNumber. Motivo: ${reason.trim()}',
      paymentMethod: paymentMethod,
    );
  }

  static Future<InsertedCashMovement> registerSaleReturnRefund(
    DatabaseExecutor txn, {
    required DateTime timestamp,
    required int? userId,
    required int saleId,
    required int amountCents,
    required String receiptNumber,
    required String reason,
    required PaymentMethod paymentMethod,
  }) async {
    final sessionId = await CashDatabaseSupport.requireOpenSessionIdWithMessage(
      txn,
      message:
          'Abra o caixa antes de registrar uma devolucao com estorno financeiro.',
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      cashEntriesDeltaCents: paymentMethod == PaymentMethod.cash
          ? -amountCents
          : 0,
    );
    return CashDatabaseSupport.insertMovement(
      txn,
      sessionId: sessionId,
      type: CashMovementType.cancellation,
      amountCents: -amountCents,
      timestamp: timestamp,
      referenceType: 'venda',
      referenceId: saleId,
      description:
          'Devolucao da venda $receiptNumber. Motivo: ${reason.trim()}',
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
    final sessionId = await CashDatabaseSupport.requireOpenSessionIdWithMessage(
      txn,
      message: 'Abra o caixa antes de estornar recebimentos de fiado no PDV.',
    );
    await CashSessionMathSupport.applySessionDeltas(
      txn,
      sessionId: sessionId,
      fiadoReceiptsCashDeltaCents: -amountCents,
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
