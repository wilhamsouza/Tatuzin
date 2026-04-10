import 'package:sqflite/sqflite.dart';

import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../../app/core/utils/payment_method_note_codec.dart';
import '../domain/entities/cash_enums.dart';
import '../../vendas/domain/entities/sale_enums.dart';

abstract final class CashDatabaseSupport {
  static const String cashEventFeatureKey = 'cash_events';

  static Future<Map<String, Object?>?> getOpenSessionRow(
    DatabaseExecutor db,
  ) async {
    final rows = await db.query(
      TableNames.caixaSessoes,
      where: 'status = ?',
      whereArgs: [CashSessionStatus.open.dbValue],
      orderBy: 'aberta_em DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  static Future<int> requireOpenSessionId(DatabaseExecutor db) async {
    final row = await getOpenSessionRow(db);
    if (row == null) {
      throw const ValidationException(
        'Abra o caixa antes de registrar movimentacoes manuais.',
      );
    }

    return row['id'] as int;
  }

  static Future<int> ensureOpenSession(
    DatabaseExecutor db, {
    required DateTime timestamp,
    int? userId,
    String? notes,
  }) async {
    final existingRow = await getOpenSessionRow(db);
    if (existingRow != null) {
      return existingRow['id'] as int;
    }

    final openedAtIso = timestamp.toIso8601String();
    return db.insert(TableNames.caixaSessoes, {
      'uuid': IdGenerator.next(),
      'usuario_id': userId,
      'aberta_em': openedAtIso,
      'fechada_em': null,
      'troco_inicial_centavos': 0,
      'aguardando_confirmacao_troco_inicial': 1,
      'total_entradas_dinheiro_centavos': 0,
      'total_suprimentos_centavos': 0,
      'total_sangrias_centavos': 0,
      'total_vendas_centavos': 0,
      'total_recebimentos_fiado_centavos': 0,
      'total_recebimentos_fiado_dinheiro_centavos': 0,
      'total_recebimentos_fiado_pix_centavos': 0,
      'total_recebimentos_fiado_cartao_centavos': 0,
      'saldo_esperado_centavos': 0,
      'saldo_contado_centavos': null,
      'diferenca_centavos': null,
      'saldo_final_centavos': 0,
      'status': CashSessionStatus.open.dbValue,
      'observacao':
          notes ??
          'Sessão aberta automaticamente para registrar movimento financeiro.',
    });
  }

  static Future<InsertedCashMovement> insertMovement(
    DatabaseExecutor db, {
    required int sessionId,
    required CashMovementType type,
    required int amountCents,
    required DateTime timestamp,
    String? referenceType,
    int? referenceId,
    String? description,
    PaymentMethod? paymentMethod,
  }) async {
    final uuid = IdGenerator.next();
    final id = await db.insert(TableNames.caixaMovimentos, {
      'uuid': uuid,
      'sessao_id': sessionId,
      'tipo_movimento': type.dbValue,
      'referencia_tipo': referenceType,
      'referencia_id': referenceId,
      'valor_centavos': amountCents,
      'descricao': PaymentMethodNoteCodec.withPaymentMethod(
        description ?? type.label,
        paymentMethod: paymentMethod,
      ),
      'criado_em': timestamp.toIso8601String(),
    });

    return InsertedCashMovement(id: id, uuid: uuid);
  }
}

class InsertedCashMovement {
  const InsertedCashMovement({required this.id, required this.uuid});

  final int id;
  final String uuid;
}

abstract final class CashSessionMathSupport {
  static Future<void> applySessionDeltas(
    DatabaseExecutor db, {
    required int sessionId,
    int cashEntriesDeltaCents = 0,
    int fiadoReceiptsCashDeltaCents = 0,
    int fiadoReceiptsPixDeltaCents = 0,
    int fiadoReceiptsCardDeltaCents = 0,
    int suppliesDeltaCents = 0,
    int withdrawalsDeltaCents = 0,
  }) async {
    final sessionRows = await db.query(
      TableNames.caixaSessoes,
      columns: [
        'troco_inicial_centavos',
        'total_entradas_dinheiro_centavos',
        'total_suprimentos_centavos',
        'total_sangrias_centavos',
        'total_vendas_centavos',
        'total_recebimentos_fiado_centavos',
        'total_recebimentos_fiado_dinheiro_centavos',
        'total_recebimentos_fiado_pix_centavos',
        'total_recebimentos_fiado_cartao_centavos',
      ],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (sessionRows.isEmpty) {
      throw const ValidationException('Sessao de caixa nao encontrada.');
    }

    final row = sessionRows.first;
    final initialFloat = row['troco_inicial_centavos'] as int? ?? 0;
    final cashEntries =
        (row['total_entradas_dinheiro_centavos'] as int? ?? 0) +
        cashEntriesDeltaCents;
    final supplies =
        (row['total_suprimentos_centavos'] as int? ?? 0) + suppliesDeltaCents;
    final withdrawals =
        (row['total_sangrias_centavos'] as int? ?? 0) + withdrawalsDeltaCents;
    final legacySales =
        (row['total_vendas_centavos'] as int? ?? 0) + cashEntriesDeltaCents;
    final legacyFiadoReceipts =
        (row['total_recebimentos_fiado_centavos'] as int? ?? 0) +
        fiadoReceiptsCashDeltaCents +
        fiadoReceiptsPixDeltaCents +
        fiadoReceiptsCardDeltaCents;
    final fiadoCash =
        (row['total_recebimentos_fiado_dinheiro_centavos'] as int? ?? 0) +
        fiadoReceiptsCashDeltaCents;
    final fiadoPix =
        (row['total_recebimentos_fiado_pix_centavos'] as int? ?? 0) +
        fiadoReceiptsPixDeltaCents;
    final fiadoCard =
        (row['total_recebimentos_fiado_cartao_centavos'] as int? ?? 0) +
        fiadoReceiptsCardDeltaCents;
    final expectedBalance =
        initialFloat + cashEntries + fiadoCash + supplies - withdrawals;

    await db.update(
      TableNames.caixaSessoes,
      {
        'total_entradas_dinheiro_centavos': cashEntries,
        'total_suprimentos_centavos': supplies,
        'total_sangrias_centavos': withdrawals,
        'total_vendas_centavos': legacySales,
        'total_recebimentos_fiado_centavos': legacyFiadoReceipts,
        'total_recebimentos_fiado_dinheiro_centavos': fiadoCash,
        'total_recebimentos_fiado_pix_centavos': fiadoPix,
        'total_recebimentos_fiado_cartao_centavos': fiadoCard,
        'saldo_esperado_centavos': expectedBalance,
        'saldo_final_centavos': expectedBalance,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  static int calculateExpectedBalance({
    required int initialFloatCents,
    required int cashEntriesCents,
    required int fiadoReceiptsCashCents,
    required int suppliesCents,
    required int withdrawalsCents,
  }) {
    return initialFloatCents +
        cashEntriesCents +
        fiadoReceiptsCashCents +
        suppliesCents -
        withdrawalsCents;
  }
}
