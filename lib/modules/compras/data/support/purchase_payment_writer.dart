import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/utils/id_generator.dart';
import '../../../caixa/data/cash_database_support.dart';
import '../../../caixa/domain/entities/cash_enums.dart';
import '../../../vendas/domain/entities/sale_enums.dart';

class PurchasePaymentWriter {
  const PurchasePaymentWriter._();

  static Future<void> insertPayment(
    DatabaseExecutor db, {
    required int purchaseId,
    required int? currentLocalUserId,
    required String supplierName,
    required int amountCents,
    required PaymentMethod? paymentMethod,
    required DateTime registeredAt,
    required String? notes,
    String? paymentUuid,
  }) async {
    if (paymentMethod == null || paymentMethod == PaymentMethod.fiado) {
      throw const ValidationException(
        'Forma de pagamento invalida para a compra.',
      );
    }

    final sessionId = await CashDatabaseSupport.ensureOpenSession(
      db,
      timestamp: registeredAt,
      userId: currentLocalUserId,
    );
    await CashSessionMathSupport.applySessionDeltas(
      db,
      sessionId: sessionId,
      withdrawalsDeltaCents: amountCents,
    );
    final movement = await CashDatabaseSupport.insertMovement(
      db,
      sessionId: sessionId,
      type: CashMovementType.sangria,
      amountCents: -amountCents,
      timestamp: registeredAt,
      referenceType: 'compra',
      referenceId: purchaseId,
      description: 'Pagamento de compra para $supplierName',
      paymentMethod: paymentMethod,
    );

    await db.insert(TableNames.compraPagamentos, {
      'uuid': paymentUuid ?? IdGenerator.next(),
      'compra_id': purchaseId,
      'valor_centavos': amountCents,
      'forma_pagamento': paymentMethod.dbValue,
      'data_hora': registeredAt.toIso8601String(),
      'observacao': _cleanNullable(notes),
      'caixa_movimento_id': movement.id,
    });
  }

  static String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
