import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../domain/entities/sale_enums.dart';
import 'sale_validation_support.dart';

class SaleCancellationSupport {
  const SaleCancellationSupport._();

  static String buildCancellationMessage({
    required String receiptNumber,
    required String reason,
  }) {
    return 'Cancelamento da venda $receiptNumber. Motivo: ${reason.trim()}';
  }

  static String mergeCancellationReason(String? existingNotes, String reason) {
    final trimmedExisting = SaleValidationSupport.cleanNullable(existingNotes);
    final cancellationMessage = 'Cancelamento: ${reason.trim()}';
    if (trimmedExisting == null) {
      return cancellationMessage;
    }

    return '$trimmedExisting\n$cancellationMessage';
  }

  static Future<void> persistSaleCancellation(
    DatabaseExecutor txn, {
    required int saleId,
    required String nowIso,
    required String? existingNotes,
    required String reason,
  }) async {
    await txn.update(
      TableNames.vendas,
      {
        'status': SaleStatus.cancelled.dbValue,
        'cancelada_em': nowIso,
        'observacao': mergeCancellationReason(existingNotes, reason),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }
}
