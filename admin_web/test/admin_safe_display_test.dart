import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/utils/admin_safe_display.dart';

void main() {
  group('admin safe display', () {
    test('mascara email preservando dominio', () {
      expect(maskAdminEmail('owner@tatuzin.test'), 'o***r@tatuzin.test');
      expect(maskAdminEmail(' a@tatuzin.test '), 'a***@tatuzin.test');
      expect(maskAdminEmail(null), 'Nao informado');
    });

    test('mascara identificadores longos sem expor valor completo', () {
      const raw = 'provider-subscription-long-id-123456';
      final masked = maskAdminIdentifier(raw);

      expect(masked, 'prov...3456');
      expect(masked, isNot(raw));
      expect(masked.contains('subscription-long-id'), isFalse);
      expect(maskAdminIdentifier(null), 'Indisponivel');
    });

    test('redige textos sensiveis e tokens longos', () {
      expect(safeAdminSensitiveText('Bearer secret-token'), '[redacted]');
      expect(
        safeAdminSensitiveText('access_token=super-secret-token'),
        '[redacted]',
      );
      expect(safeAdminSensitiveText('passwordHash abc'), '[redacted]');
      expect(
        safeAdminSensitiveText('abcdefghijklmnopqrstuvwxyz123456'),
        '[redacted]',
      );
    });

    test('mantem textos curtos seguros e mascara textos longos comuns', () {
      expect(safeAdminSensitiveText('OK'), 'OK');
      expect(
        safeAdminSensitiveText('client-instance-readable-long-id'),
        'clie...g-id',
      );
      expect(safeAdminSensitiveText(null), 'Indisponivel');
    });
  });
}
