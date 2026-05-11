import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/sync/sync_batch_result.dart';
import 'package:erp_pdv_app/app/core/sync/sync_error_info.dart';
import 'package:erp_pdv_app/app/core/sync/sync_error_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API 422 com createdAt invalid datetime vira erro de validacao claro', () {
    final result = resolveSyncError(
      const NetworkRequestException(
        'Falha ao chamar /api/financial-events: Dados invalidos enviados para a API. createdAt: Invalid datetime',
        cause: 422,
      ),
    );

    expect(result.type, SyncErrorType.validation);
    expect(
      result.message,
      'Falha ao sincronizar evento financeiro. Data invalida no evento local (createdAt).',
    );
  });

  test('sync com conflitos e erro nao mostra sucesso puro', () {
    final now = DateTime(2026, 5, 6, 20, 45);
    final result = SyncBatchResult(
      processedCount: 9,
      syncedCount: 0,
      failedCount: 1,
      blockedCount: 0,
      conflictCount: 8,
      reprocessedOnly: false,
      startedAt: now,
      finishedAt: now.add(const Duration(seconds: 1)),
    );

    expect(
      result.message,
      'Sincronização concluída, mas ainda há itens que precisam de revisão. Conflitos: 8 · Erros: 1.',
    );
    expect(result.message.toLowerCase(), isNot(contains('sucesso')));
  });
}
