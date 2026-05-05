import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
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
}
