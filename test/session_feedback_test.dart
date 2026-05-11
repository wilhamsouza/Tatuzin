import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/session/session_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlySessionFeedbackMessage', () {
    test('LICENSE_EXPIRED nao vira erro de internet', () {
      final message = friendlySessionFeedbackMessage(
        const NetworkRequestException(
          'Falha ao chamar /api/auth/login: LICENSE_EXPIRED',
          cause: 403,
        ),
      );

      expect(
        message,
        'A licença da empresa está expirada. Regularize a assinatura para continuar.',
      );
      expect(message.toLowerCase(), isNot(contains('internet')));
    });

    test('INVALID_CREDENTIALS mostra e-mail ou senha invalidos', () {
      final message = friendlySessionFeedbackMessage(
        const AuthenticationException('INVALID_CREDENTIALS'),
      );

      expect(message, 'E-mail ou senha inválidos.');
    });

    test('AUTH_REQUIRED e INVALID_ACCESS_TOKEN pedem novo login', () {
      expect(
        friendlySessionFeedbackMessage(
          const AuthenticationException('AUTH_REQUIRED'),
        ),
        'Sua sessão expirou. Entre novamente.',
      );
      expect(
        friendlySessionFeedbackMessage(
          const AuthenticationException('INVALID_ACCESS_TOKEN'),
        ),
        'Sua sessão expirou. Entre novamente.',
      );
    });

    test('erro real de rede fica claro', () {
      expect(
        friendlySessionFeedbackMessage(
          const NetworkRequestException('SocketException: failed host lookup'),
        ),
        'Não foi possível falar com a nuvem agora. Verifique sua conexão.',
      );
    });
  });
}
