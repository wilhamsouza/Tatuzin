import 'dart:async';

import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/api_client_contract.dart';
import 'package:erp_pdv_app/app/core/network/real/remote_auth_gateway.dart';
import 'package:erp_pdv_app/app/core/session/auth_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteAuthGateway', () {
    test(
      'login usa /auth/login, salva tokens e carrega bootstrap com entitlements',
      () async {
        final apiClient = _RecordingApiClient();
        final tokenStorage = _MemoryAuthTokenStorage(
          clientContext: const AuthClientContext(
            clientType: 'mobile_app',
            clientInstanceId: 'device-123',
          ),
        );

        apiClient.onPost('/auth/login', (body, options) {
          expect(body?['email'], 'owner@tatuzin.com.br');
          expect(body?['password'], 'secret-123');
          expect(body?['clientType'], 'mobile_app');
          expect(body?['clientInstanceId'], 'device-123');

          return ApiResponse<Map<String, dynamic>>(
            statusCode: 200,
            data: _authPayload(),
            headers: const <String, String>{},
          );
        });
        apiClient.onGet('/app/bootstrap', (options) {
          expect(options.headers['Authorization'], 'Bearer access-token-1');
          expect(options.headers['X-Client-Instance-Id'], 'device-123');

          return ApiResponse<Map<String, dynamic>>(
            statusCode: 200,
            data: _bootstrapPayload(),
            headers: const <String, String>{},
          );
        });

        final gateway = RemoteAuthGateway(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
        );

        final session = await gateway.signIn(
          identifier: 'owner@tatuzin.com.br',
          password: 'secret-123',
        );

        expect(apiClient.calls, [
          ('POST', '/auth/login'),
          ('GET', '/app/bootstrap'),
        ]);
        expect(await tokenStorage.readAccessToken(), 'access-token-1');
        expect(await tokenStorage.readRefreshToken(), 'refresh-token-1');
        expect(session.user.remoteId, 'user-1');
        expect(session.company.remoteId, 'company-1');
        expect(session.company.displayName, 'Tatuzin Foods');
        expect(session.company.licenseStatus, 'active');
        expect(session.company.syncEnabled, isTrue);
        expect(session.company.plan, PlanKey.pro);
        expect(session.company.hasFeature(FeatureKey.employees), isTrue);
        expect(session.company.limits.maxDevices, 100);
        expect(
          session.membership?.permissions.contains('employees.manage'),
          isTrue,
        );
        expect(session.employee?.role, 'OWNER');
        expect(
          session.employee?.permissions.contains('employees.manage'),
          isTrue,
        );
        expect(session.clientInstanceId, 'device-123');
      },
    );

    test('restoreSession exige contexto de dispositivo salvo', () async {
      final apiClient = _RecordingApiClient();
      final tokenStorage = _MemoryAuthTokenStorage(
        accessToken: 'access-token-1',
        refreshToken: 'refresh-token-1',
      );

      final gateway = RemoteAuthGateway(
        apiClient: apiClient,
        tokenStorage: tokenStorage,
      );

      final session = await gateway.restoreSession();

      expect(session, isNull);
      expect(apiClient.calls, isEmpty);
      expect(await tokenStorage.readAccessToken(), isNull);
      expect(await tokenStorage.readRefreshToken(), isNull);
    });

    test(
      'login falha com timeout especifico quando /app/bootstrap demora',
      () async {
        final apiClient = _RecordingApiClient();
        final tokenStorage = _MemoryAuthTokenStorage(
          clientContext: const AuthClientContext(
            clientType: 'mobile_app',
            clientInstanceId: 'device-123',
          ),
        );

        apiClient.onPost('/auth/login', (body, options) {
          return ApiResponse<Map<String, dynamic>>(
            statusCode: 200,
            data: _authPayload(),
            headers: const <String, String>{},
          );
        });
        apiClient.onGet('/app/bootstrap', (options) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return ApiResponse<Map<String, dynamic>>(
            statusCode: 200,
            data: _bootstrapPayload(),
            headers: const <String, String>{},
          );
        });

        final gateway = RemoteAuthGateway(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
          currentCompanyTimeout: const Duration(milliseconds: 10),
        );

        await expectLater(
          () => gateway.signIn(
            identifier: 'owner@tatuzin.com.br',
            password: 'secret-123',
          ),
          throwsA(
            isA<NetworkRequestException>().having(
              (error) => error.message,
              'message',
              contains('A API demorou demais para responder'),
            ),
          ),
        );
      },
    );

    test('cadastro usa /auth/register com slug normalizado', () async {
      final apiClient = _RecordingApiClient();
      final tokenStorage = _MemoryAuthTokenStorage(
        clientContext: const AuthClientContext(
          clientType: 'mobile_app',
          clientInstanceId: 'device-123',
        ),
      );

      apiClient.onPost('/auth/register', (body, options) {
        expect(body?['companyName'], 'Tatuzin Foods');
        expect(body?['companySlug'], 'tatuzin-foods');
        expect(body?['userName'], 'Owner');

        return ApiResponse<Map<String, dynamic>>(
          statusCode: 200,
          data: _authPayload(),
          headers: const <String, String>{},
        );
      });
      apiClient.onGet(
        '/app/bootstrap',
        (options) => ApiResponse<Map<String, dynamic>>(
          statusCode: 200,
          data: _bootstrapPayload(),
          headers: const <String, String>{},
        ),
      );

      final gateway = RemoteAuthGateway(
        apiClient: apiClient,
        tokenStorage: tokenStorage,
      );

      final session = await gateway.signUp(
        companyName: 'Tatuzin Foods',
        companySlug: 'Tatuzin-Foods',
        userName: 'Owner',
        email: 'owner@tatuzin.com.br',
        password: 'secret-123',
      );

      expect(apiClient.calls.first, ('POST', '/auth/register'));
      expect(session.user.email, 'owner@tatuzin.com.br');
    });

    test('forgot password usa /auth/forgot-password', () async {
      final apiClient = _RecordingApiClient();
      apiClient.onPost('/auth/forgot-password', (body, options) {
        expect(body?['email'], 'owner@tatuzin.com.br');

        return const ApiResponse<Map<String, dynamic>>(
          statusCode: 200,
          data: <String, dynamic>{'message': 'Token enviado.'},
          headers: <String, String>{},
        );
      });

      final gateway = RemoteAuthGateway(
        apiClient: apiClient,
        tokenStorage: _MemoryAuthTokenStorage(),
      );

      final message = await gateway.requestPasswordReset(
        email: 'owner@tatuzin.com.br',
      );

      expect(message, 'Token enviado.');
      expect(apiClient.calls.single, ('POST', '/auth/forgot-password'));
    });

    test(
      'reset password usa /auth/reset-password e limpa a sessao local',
      () async {
        final apiClient = _RecordingApiClient();
        final tokenStorage = _MemoryAuthTokenStorage(
          accessToken: 'access-token-1',
          refreshToken: 'refresh-token-1',
        );

        apiClient.onPost('/auth/reset-password', (body, options) {
          expect(body?['token'], 'reset-token');
          expect(body?['newPassword'], 'new-password');

          return const ApiResponse<Map<String, dynamic>>(
            statusCode: 200,
            data: <String, dynamic>{'message': 'Senha atualizada.'},
            headers: <String, String>{},
          );
        });

        final gateway = RemoteAuthGateway(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
        );

        final message = await gateway.resetPassword(
          token: 'reset-token',
          newPassword: 'new-password',
        );

        expect(message, 'Senha atualizada.');
        expect(await tokenStorage.readAccessToken(), isNull);
        expect(await tokenStorage.readRefreshToken(), isNull);
        expect(apiClient.calls.single, ('POST', '/auth/reset-password'));
      },
    );

    test(
      'logout usa /auth/logout e continua resiliente quando a API falha',
      () async {
        final apiClient = _RecordingApiClient();
        final tokenStorage = _MemoryAuthTokenStorage(
          accessToken: 'access-token-1',
          refreshToken: 'refresh-token-1',
        );

        apiClient.onPost('/auth/logout', (body, options) {
          expect(options.headers['Authorization'], 'Bearer access-token-1');
          throw const NetworkRequestException('backend offline');
        });

        final gateway = RemoteAuthGateway(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
        );

        await gateway.signOut();

        expect(apiClient.calls.single, ('POST', '/auth/logout'));
        expect(await tokenStorage.readAccessToken(), isNull);
        expect(await tokenStorage.readRefreshToken(), isNull);
      },
    );
  });
}

Map<String, dynamic> _authPayload() {
  return <String, dynamic>{
    'accessToken': 'access-token-1',
    'refreshToken': 'refresh-token-1',
    'user': <String, dynamic>{
      'id': 'user-1',
      'name': 'Owner',
      'email': 'owner@tatuzin.com.br',
      'isPlatformAdmin': false,
    },
    'membership': <String, dynamic>{'role': 'OWNER'},
  };
}

Map<String, dynamic> _companyPayload() {
  return <String, dynamic>{
    'id': 'company-1',
    'name': 'Tatuzin Foods',
    'legalName': 'Tatuzin Foods LTDA',
    'documentNumber': '12345678000100',
    'license': <String, dynamic>{
      'plan': 'pro',
      'status': 'active',
      'startsAt': '2026-04-20T00:00:00.000Z',
      'expiresAt': '2026-05-20T00:00:00.000Z',
      'maxDevices': 5,
      'syncEnabled': true,
    },
  };
}

Map<String, dynamic> _bootstrapPayload() {
  final company = _companyPayload();
  return <String, dynamic>{
    'user': <String, dynamic>{
      'id': 'user-1',
      'name': 'Owner',
      'email': 'owner@tatuzin.com.br',
    },
    'company': <String, dynamic>{
      'id': company['id'],
      'name': company['name'],
      'legalName': company['legalName'],
      'documentNumber': company['documentNumber'],
      'setupCompleted': true,
    },
    'membership': <String, dynamic>{
      'id': 'membership-1',
      'role': 'OWNER',
      'permissions': <String>['employees.manage', 'subscription.manage'],
    },
    'employee': <String, dynamic>{
      'id': 'employee-1',
      'role': 'OWNER',
      'status': 'ACTIVE',
      'permissions': <String>['employees.manage', 'subscription.manage'],
    },
    'license': company['license'],
    'plan': 'PRO',
    'features': <String, bool>{
      for (final feature in FeatureKey.values) feature.key: true,
    },
    'limits': <String, dynamic>{
      'maxDevices': 100,
      'maxEmployees': 100,
      'reportPeriods': <String>[
        'daily',
        'weekly',
        'monthly',
        'yearly',
        'custom',
      ],
    },
  };
}

class _MemoryAuthTokenStorage implements AuthTokenStorage {
  _MemoryAuthTokenStorage({
    this.accessToken,
    this.refreshToken,
    this.clientContext,
  });

  String? accessToken;
  String? refreshToken;
  AuthClientContext? clientContext;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    final resolvedContext =
        clientContext ??
        AuthClientContext(
          clientType: clientType,
          clientInstanceId: 'generated-client',
          deviceLabel: deviceLabel,
          platform: platform,
          appVersion: appVersion,
        );
    clientContext = resolvedContext;
    return resolvedContext;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<AuthClientContext?> readClientContext() async => clientContext;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

typedef _JsonResponseBuilder =
    FutureOr<ApiResponse<Map<String, dynamic>>> Function(
      Map<String, dynamic>? body,
      ApiRequestOptions options,
    );

typedef _JsonGetResponseBuilder =
    FutureOr<ApiResponse<Map<String, dynamic>>> Function(
      ApiRequestOptions options,
    );

class _RecordingApiClient implements ApiClientContract {
  final List<(String, String)> calls = <(String, String)>[];
  final Map<String, _JsonResponseBuilder> _postHandlers =
      <String, _JsonResponseBuilder>{};
  final Map<String, _JsonGetResponseBuilder> _getHandlers =
      <String, _JsonGetResponseBuilder>{};

  void onGet(String path, _JsonGetResponseBuilder handler) {
    _getHandlers[path] = handler;
  }

  void onPost(String path, _JsonResponseBuilder handler) {
    _postHandlers[path] = handler;
  }

  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(('DELETE', path));
    return const ApiResponse<void>(
      statusCode: 204,
      data: null,
      headers: <String, String>{},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(('GET', path));
    final handler = _getHandlers[path];
    if (handler == null) {
      throw StateError('GET inesperado: $path');
    }
    try {
      return await Future<ApiResponse<Map<String, dynamic>>>.value(
        handler(options),
      ).timeout(options.timeout);
    } on TimeoutException catch (error) {
      throw NetworkRequestException(
        'A API demorou demais para responder.',
        cause: error,
      );
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(('PATCH', path));
    throw StateError('PATCH inesperado: $path');
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(('POST', path));
    final handler = _postHandlers[path];
    if (handler == null) {
      throw StateError('POST inesperado: $path');
    }
    try {
      return await Future<ApiResponse<Map<String, dynamic>>>.value(
        handler(body, options),
      ).timeout(options.timeout);
    } on TimeoutException catch (error) {
      throw NetworkRequestException(
        'A API demorou demais para responder.',
        cause: error,
      );
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(('PUT', path));
    throw StateError('PUT inesperado: $path');
  }
}
