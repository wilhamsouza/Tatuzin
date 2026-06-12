import 'dart:convert';
import 'dart:io';

import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/network/contracts/api_client_contract.dart';
import 'package:tatuzin/app/core/network/endpoint_config.dart';
import 'package:tatuzin/app/core/network/real/real_api_client.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RealApiClient', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });

    test(
      'renova a sessao em /auth/refresh e repete a chamada original',
      () async {
        final recordedRequests = <http.Request>[];
        final tokenStorage = _MemoryAuthTokenStorage(
          accessToken: 'expired-access',
          refreshToken: 'refresh-token-1',
          clientContext: const AuthClientContext(
            clientType: 'mobile_app',
            clientInstanceId: 'device-123',
            deviceLabel: 'Tatuzin Windows',
            platform: 'windows',
            appVersion: '1.0.0',
          ),
        );
        final client = MockClient((request) async {
          recordedRequests.add(request);

          if (request.url.path == '/api/categories') {
            if (request.headers['Authorization'] == 'Bearer expired-access') {
              return http.Response('{"message":"expired"}', 401);
            }

            expect(request.headers['Authorization'], 'Bearer renewed-access');
            return http.Response('{"items":[]}', 200);
          }

          if (request.url.path == '/api/auth/refresh') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['refreshToken'], 'refresh-token-1');
            expect(body['clientType'], 'mobile_app');
            expect(body['clientInstanceId'], 'device-123');

            return http.Response(
              '{"accessToken":"renewed-access","refreshToken":"renewed-refresh"}',
              200,
            );
          }

          throw StateError('Rota inesperada: ${request.url}');
        });

        final apiClient = RealApiClient(
          const EndpointConfig(
            baseUrl: EndpointConfig.productionBaseUrl,
            apiVersion: EndpointConfig.defaultApiVersion,
          ),
          httpClient: client,
          tokenStorage: tokenStorage,
        );

        final response = await apiClient.getJson(
          '/categories',
          options: const ApiRequestOptions(
            headers: <String, String>{'Authorization': 'Bearer expired-access'},
          ),
        );

        expect(response.statusCode, 200);
        expect(response.data['items'], isEmpty);
        expect(recordedRequests, hasLength(3));
        expect(
          recordedRequests.first.url.toString(),
          'https://api.tatuzin.com.br/api/categories',
        );
        expect(
          recordedRequests[1].url.toString(),
          'https://api.tatuzin.com.br/api/auth/refresh',
        );
        expect(await tokenStorage.readAccessToken(), 'renewed-access');
        expect(await tokenStorage.readRefreshToken(), 'renewed-refresh');
      },
    );

    test('retorna erro amigavel quando a API fica indisponivel', () async {
      final apiClient = RealApiClient(
        const EndpointConfig(
          baseUrl: EndpointConfig.productionBaseUrl,
          apiVersion: EndpointConfig.defaultApiVersion,
        ),
        httpClient: MockClient((request) async {
          throw const SocketException('unreachable');
        }),
      );

      await expectLater(
        () => apiClient.getJson('/health'),
        throwsA(
          isA<NetworkRequestException>().having(
            (error) => error.message,
            'message',
            'Nao foi possivel alcancar o backend configurado.',
          ),
        ),
      );
    });

    test('refresh automatico atualiza tokens no storage seguro', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'session.remote_client_type': 'mobile_app',
        'session.remote_client_instance_id': 'device-123',
      });
      final secureStore = _MemorySecureTokenStore(
        values: <String, String>{
          'session.remote_access_token': 'expired-access',
          'session.remote_refresh_token': 'refresh-token-1',
        },
      );
      final tokenStorage = SecureAuthTokenStorage(
        secureTokenStore: secureStore,
      );
      final client = MockClient((request) async {
        if (request.url.path == '/api/categories') {
          if (request.headers['Authorization'] == 'Bearer expired-access') {
            return http.Response('{"message":"expired"}', 401);
          }
          expect(request.headers['Authorization'], 'Bearer renewed-access');
          return http.Response('{"items":[]}', 200);
        }

        if (request.url.path == '/api/auth/refresh') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refreshToken'], 'refresh-token-1');
          expect(body['clientInstanceId'], 'device-123');
          return http.Response(
            '{"accessToken":"renewed-access","refreshToken":"renewed-refresh"}',
            200,
          );
        }

        throw StateError('Rota inesperada: ${request.url}');
      });

      final apiClient = RealApiClient(
        const EndpointConfig(
          baseUrl: EndpointConfig.productionBaseUrl,
          apiVersion: EndpointConfig.defaultApiVersion,
        ),
        httpClient: client,
        tokenStorage: tokenStorage,
      );

      await apiClient.getJson(
        '/categories',
        options: const ApiRequestOptions(
          headers: <String, String>{'Authorization': 'Bearer expired-access'},
        ),
      );

      expect(
        await secureStore.read(key: 'session.remote_access_token'),
        'renewed-access',
      );
      expect(
        await secureStore.read(key: 'session.remote_refresh_token'),
        'renewed-refresh',
      );
    });

    test('monta login na API oficial sem duplicar /api', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.tatuzin.com.br/api/auth/login',
        );
        return http.Response('{"accessToken":"a","refreshToken":"r"}', 200);
      });
      final apiClient = RealApiClient(
        const EndpointConfig(
          baseUrl: EndpointConfig.productionBaseUrl,
          apiVersion: EndpointConfig.defaultApiVersion,
        ),
        httpClient: client,
      );

      final response = await apiClient.postJson('/auth/login');

      expect(response.statusCode, 200);
    });

    test('inclui detalhes de validacao 422 na mensagem de erro', () async {
      final apiClient = RealApiClient(
        const EndpointConfig(
          baseUrl: EndpointConfig.productionBaseUrl,
          apiVersion: EndpointConfig.defaultApiVersion,
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'message': 'Dados invalidos enviados para a API.',
              'code': 'VALIDATION_ERROR',
              'details': {
                'fieldErrors': {
                  'lastCostUpdatedAt': ['Invalid datetime'],
                },
                'formErrors': [],
              },
            }),
            422,
          );
        }),
      );

      await expectLater(
        () => apiClient.postJson('/products', body: const <String, dynamic>{}),
        throwsA(
          isA<NetworkRequestException>()
              .having((error) => error.cause, 'cause', 422)
              .having(
                (error) => error.message,
                'message',
                contains('lastCostUpdatedAt: Invalid datetime'),
              ),
        ),
      );
    });

    test(
      'mapeia TENANT_PENDING_DELETION sem refresh ou erro generico',
      () async {
        var requestCount = 0;
        TenantPendingDeletionException? reportedException;
        final tokenStorage = _MemoryAuthTokenStorage(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          clientContext: const AuthClientContext(
            clientType: 'mobile_app',
            clientInstanceId: 'device-123',
          ),
        );
        final apiClient = RealApiClient(
          const EndpointConfig(
            baseUrl: EndpointConfig.productionBaseUrl,
            apiVersion: EndpointConfig.defaultApiVersion,
          ),
          httpClient: MockClient((request) async {
            requestCount++;
            return http.Response(
              jsonEncode({
                'ok': false,
                'message': 'Empresa em quarentena.',
                'code': TenantPendingDeletionException.code,
                'details': {
                  'acknowledgementAvailable': true,
                  'acknowledgement': {
                    'token': 'signed-ack-token',
                    'requestId': 'request-1',
                    'companyId': 'company-1',
                    'clientInstanceId': 'device-123',
                  },
                },
              }),
              423,
            );
          }),
          tokenStorage: tokenStorage,
          onTenantPendingDeletion: (exception) async {
            reportedException = exception;
          },
        );

        await expectLater(
          () => apiClient.getJson(
            '/sync/push',
            options: const ApiRequestOptions(
              headers: <String, String>{'Authorization': 'Bearer access-token'},
            ),
          ),
          throwsA(
            isA<TenantPendingDeletionException>()
                .having((error) => error.statusCode, 'statusCode', 423)
                .having(
                  (error) => error.requestPath,
                  'requestPath',
                  '/sync/push',
                )
                .having(
                  (error) => error.acknowledgementToken,
                  'acknowledgementToken',
                  'signed-ack-token',
                )
                .having((error) => error.companyId, 'companyId', 'company-1'),
          ),
        );

        expect(requestCount, 1);
        expect(reportedException, isNotNull);
        expect(reportedException?.clientInstanceId, 'device-123');
        expect(await tokenStorage.readAccessToken(), isNull);
        expect(await tokenStorage.readRefreshToken(), isNull);
      },
    );
  });
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
