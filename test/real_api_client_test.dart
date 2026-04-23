import 'dart:convert';
import 'dart:io';

import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/api_client_contract.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:erp_pdv_app/app/core/network/real/real_api_client.dart';
import 'package:erp_pdv_app/app/core/session/auth_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RealApiClient', () {
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
