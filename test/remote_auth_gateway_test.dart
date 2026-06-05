import 'dart:async';

import 'package:tatuzin/app/core/entitlements/plan_entitlements.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/network/contracts/api_client_contract.dart';
import 'package:tatuzin/app/core/network/real/remote_auth_gateway.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RemoteAuthGateway', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });

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

    test('restoreSession funciona com token seguro', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'session.remote_client_type': 'mobile_app',
        'session.remote_client_instance_id': 'device-123',
      });
      final apiClient = _RecordingApiClient();
      final secureStore = _MemorySecureTokenStore(
        values: <String, String>{
          'session.remote_access_token': 'secure-access',
          'session.remote_refresh_token': 'secure-refresh',
        },
      );
      final tokenStorage = SecureAuthTokenStorage(
        secureTokenStore: secureStore,
      );

      apiClient.onGet('/auth/me', (options) {
        expect(options.headers['Authorization'], 'Bearer secure-access');
        return ApiResponse<Map<String, dynamic>>(
          statusCode: 200,
          data: _authPayload(),
          headers: const <String, String>{},
        );
      });
      apiClient.onGet('/app/bootstrap', (options) {
        expect(options.headers['Authorization'], 'Bearer secure-access');
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

      final session = await gateway.restoreSession();

      expect(session?.company.remoteId, 'company-1');
      expect(apiClient.calls, [('GET', '/auth/me'), ('GET', '/app/bootstrap')]);
      expect(await tokenStorage.readAccessToken(), 'secure-access');
      expect(await tokenStorage.readRefreshToken(), 'secure-refresh');
    });

    test('restoreSession funciona apos migrar access token legado', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'session.remote_access_token': 'legacy-access',
        'session.remote_refresh_token': 'legacy-refresh',
        'session.remote_client_type': 'mobile_app',
        'session.remote_client_instance_id': 'device-123',
      });
      final apiClient = _RecordingApiClient();
      final secureStore = _MemorySecureTokenStore();
      final tokenStorage = SecureAuthTokenStorage(
        secureTokenStore: secureStore,
      );

      apiClient.onGet('/auth/me', (options) {
        expect(options.headers['Authorization'], 'Bearer legacy-access');
        return ApiResponse<Map<String, dynamic>>(
          statusCode: 200,
          data: _authPayload(),
          headers: const <String, String>{},
        );
      });
      apiClient.onGet('/app/bootstrap', (options) {
        expect(options.headers['Authorization'], 'Bearer legacy-access');
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

      final session = await gateway.restoreSession();

      expect(session?.user.remoteId, 'user-1');
      expect(
        await secureStore.read(key: 'session.remote_access_token'),
        'legacy-access',
      );
      expect(
        await secureStore.read(key: 'session.remote_refresh_token'),
        isNull,
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('session.remote_access_token'), isNull);
      expect(
        preferences.getString('session.remote_refresh_token'),
        'legacy-refresh',
      );

      expect(await tokenStorage.readRefreshToken(), 'legacy-refresh');
      expect(
        await secureStore.read(key: 'session.remote_refresh_token'),
        'legacy-refresh',
      );
      expect(preferences.getString('session.remote_refresh_token'), isNull);
    });

    test(
      'login com mustChangePassword preserva tokens para troca obrigatoria',
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
            data: _authPayload(mustChangePassword: true),
            headers: const <String, String>{},
          );
        });

        final gateway = RemoteAuthGateway(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
        );

        await expectLater(
          () => gateway.signIn(
            identifier: 'employee@tatuzin.com.br',
            password: 'Temp123456',
          ),
          throwsA(isA<InitialPasswordChangeRequiredException>()),
        );

        expect(apiClient.calls, [('POST', '/auth/login')]);
        expect(await tokenStorage.readAccessToken(), 'access-token-1');
        expect(await tokenStorage.readRefreshToken(), 'refresh-token-1');
      },
    );

    test(
      'restoreSession com mustChangePassword redireciona sem limpar tokens',
      () async {
        final apiClient = _RecordingApiClient();
        final tokenStorage = _MemoryAuthTokenStorage(
          accessToken: 'access-token-1',
          refreshToken: 'refresh-token-1',
          clientContext: const AuthClientContext(
            clientType: 'mobile_app',
            clientInstanceId: 'device-123',
          ),
        );

        apiClient.onGet(
          '/auth/me',
          (options) => ApiResponse<Map<String, dynamic>>(
            statusCode: 200,
            data: _authPayload(mustChangePassword: true),
            headers: const <String, String>{},
          ),
        );
        apiClient.onGet('/app/bootstrap', (options) {
          throw const NetworkRequestException(
            'Falha ao chamar /api/app/bootstrap: Voce precisa criar uma nova senha para continuar.',
            cause: 403,
          );
        });

        final gateway = RemoteAuthGateway(
          apiClient: apiClient,
          tokenStorage: tokenStorage,
        );

        await expectLater(
          gateway.restoreSession,
          throwsA(isA<InitialPasswordChangeRequiredException>()),
        );

        expect(apiClient.calls, [
          ('GET', '/auth/me'),
          ('GET', '/app/bootstrap'),
        ]);
        expect(await tokenStorage.readAccessToken(), 'access-token-1');
        expect(await tokenStorage.readRefreshToken(), 'refresh-token-1');
      },
    );

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

    test('logout limpa tokens seguros e legados', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'session.remote_access_token': 'legacy-access',
        'session.remote_refresh_token': 'legacy-refresh',
      });
      final apiClient = _RecordingApiClient();
      final secureStore = _MemorySecureTokenStore(
        values: <String, String>{
          'session.remote_access_token': 'secure-access',
          'session.remote_refresh_token': 'secure-refresh',
        },
      );
      final tokenStorage = SecureAuthTokenStorage(
        secureTokenStore: secureStore,
      );

      apiClient.onPost('/auth/logout', (body, options) {
        expect(options.headers['Authorization'], 'Bearer secure-access');
        return const ApiResponse<Map<String, dynamic>>(
          statusCode: 200,
          data: <String, dynamic>{},
          headers: <String, String>{},
        );
      });

      final gateway = RemoteAuthGateway(
        apiClient: apiClient,
        tokenStorage: tokenStorage,
      );

      await gateway.signOut();

      expect(
        await secureStore.read(key: 'session.remote_access_token'),
        isNull,
      );
      expect(
        await secureStore.read(key: 'session.remote_refresh_token'),
        isNull,
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('session.remote_access_token'), isNull);
      expect(preferences.getString('session.remote_refresh_token'), isNull);
    });
  });
}

Map<String, dynamic> _authPayload({bool mustChangePassword = false}) {
  return <String, dynamic>{
    'accessToken': 'access-token-1',
    'refreshToken': 'refresh-token-1',
    'user': <String, dynamic>{
      'id': 'user-1',
      'name': 'Owner',
      'email': 'owner@tatuzin.com.br',
      'isPlatformAdmin': false,
      'mustChangePassword': mustChangePassword,
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

class _MemorySecureTokenStore implements SecureTokenStore {
  _MemorySecureTokenStore({
    Map<String, String> values = const <String, String>{},
  }) : _values = Map<String, String>.from(values);

  final Map<String, String> _values;

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
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
