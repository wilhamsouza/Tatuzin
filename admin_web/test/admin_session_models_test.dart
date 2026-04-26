import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';

void main() {
  test(
    'AdminSession.fromLoginResponse aceita o payload atual de auth do backend',
    () {
      final session = AdminSession.fromLoginResponse(<String, dynamic>{
        'accessToken': 'access-token-value',
        'refreshToken': 'refresh-token-value',
        'tokenType': 'Bearer',
        'user': <String, dynamic>{
          'id': 'user-1',
          'email': 'admin@simples.local',
          'name': 'Administrador',
          'isPlatformAdmin': true,
        },
        'company': <String, dynamic>{
          'id': 'company-1',
          'name': 'Tatuzin Cloud',
          'legalName': 'Tatuzin Cloud LTDA',
          'documentNumber': '123',
          'slug': 'tatuzin-cloud',
          'license': <String, dynamic>{
            'id': 'license-1',
            'plan': 'pro',
            'status': 'active',
            'startsAt': '2026-04-01T12:00:00.000Z',
            'expiresAt': '2026-05-01T12:00:00.000Z',
            'maxDevices': 5,
            'syncEnabled': true,
          },
        },
        'membership': <String, dynamic>{
          'id': 'membership-1',
          'role': 'OWNER',
          'isDefault': true,
        },
        'session': <String, dynamic>{
          'id': 'session-1',
          'userId': 'user-1',
          'userName': 'Administrador',
          'userEmail': 'admin@simples.local',
          'companyId': 'company-1',
          'companyName': 'Tatuzin Cloud',
          'membershipId': 'membership-1',
          'membershipRole': 'OWNER',
          'clientType': 'admin_web',
          'clientInstanceId': 'adm-web-1',
          'deviceLabel': 'Chrome',
          'platform': 'web',
          'appVersion': 'admin-web',
          'status': 'active',
          'createdAt': '2026-04-01T12:00:00.000Z',
          'lastSeenAt': '2026-04-01T12:00:00.000Z',
          'lastRefreshedAt': '2026-04-01T12:05:00.000Z',
          'refreshTokenExpiresAt': '2026-05-01T12:00:00.000Z',
          'revokedAt': null,
          'revokedReason': null,
        },
      });

      expect(session.accessToken, 'access-token-value');
      expect(session.refreshToken, 'refresh-token-value');
      expect(session.tokenType, 'Bearer');
      expect(session.user.isPlatformAdmin, isTrue);
      expect(session.company.license, isNotNull);
      expect(session.company.license!.companyId, 'company-1');
      expect(session.company.license!.companyName, 'Tatuzin Cloud');
      expect(session.activeSession, isNotNull);
      expect(session.activeSession!.id, 'session-1');
    },
  );

  test(
    'AdminSession.fromIdentityResponse aceita o payload atual de /auth/me',
    () {
      final session = AdminSession.fromIdentityResponse(<String, dynamic>{
        'user': <String, dynamic>{
          'id': 'user-1',
          'email': 'admin@simples.local',
          'name': 'Administrador',
          'isPlatformAdmin': true,
        },
        'company': <String, dynamic>{
          'id': 'company-1',
          'name': 'Tatuzin Cloud',
          'legalName': 'Tatuzin Cloud LTDA',
          'documentNumber': '123',
          'slug': 'tatuzin-cloud',
          'license': <String, dynamic>{
            'id': 'license-1',
            'plan': 'pro',
            'status': 'active',
            'startsAt': '2026-04-01T12:00:00.000Z',
            'expiresAt': '2026-05-01T12:00:00.000Z',
            'maxDevices': 5,
            'syncEnabled': true,
          },
        },
        'membership': <String, dynamic>{
          'id': 'membership-1',
          'role': 'OWNER',
          'isDefault': true,
        },
      }, accessToken: 'restored-access-token');

      expect(session.accessToken, 'restored-access-token');
      expect(session.user.isPlatformAdmin, isTrue);
      expect(session.company.license, isNotNull);
      expect(session.company.license!.companySlug, 'tatuzin-cloud');
      expect(session.activeSession, isNull);
    },
  );
}
