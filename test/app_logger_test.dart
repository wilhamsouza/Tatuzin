import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin/app/core/utils/app_logger.dart';

void main() {
  group('AppLogger', () {
    test('redige tokens e credenciais em mensagens de log', () {
      final sanitized = AppLogger.sanitizeForTesting(
        'Authorization: Bearer access.jwt | refresh_token=refresh.jwt | '
        'password=super-secret | senha=123456 | secret=abc',
      );

      expect(sanitized, isNot(contains('access.jwt')));
      expect(sanitized, isNot(contains('refresh.jwt')));
      expect(sanitized, isNot(contains('super-secret')));
      expect(sanitized, isNot(contains('123456')));
      expect(sanitized, isNot(contains('abc')));
      expect(sanitized, contains('Authorization: Bearer <redacted>'));
      expect(sanitized, contains('refresh_token=<redacted>'));
      expect(sanitized, contains('password=<redacted>'));
      expect(sanitized, contains('senha=<redacted>'));
      expect(sanitized, contains('secret=<redacted>'));
    });
  });
}
