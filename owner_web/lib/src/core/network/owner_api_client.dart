import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/owner_auth_storage.dart';
import '../auth/owner_debug_log.dart';
import '../models/owner_models.dart';

class OwnerApiClient {
  OwnerApiClient({
    required String baseUrl,
    required OwnerAuthStorage authStorage,
    http.Client? httpClient,
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _authStorage = authStorage,
       _httpClient = httpClient ?? http.Client();

  final String _baseUrl;
  final OwnerAuthStorage _authStorage;
  final http.Client _httpClient;

  Future<dynamic> getJson(
    String path, {
    String? accessToken,
    Map<String, dynamic>? queryParameters,
  }) {
    return _send(
      'GET',
      path,
      accessToken: accessToken,
      queryParameters: queryParameters,
    );
  }

  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) {
    return _send('POST', path, body: body, accessToken: accessToken);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    Map<String, dynamic>? queryParameters,
    bool allowRefreshRetry = true,
  }) async {
    final baseUri = Uri.parse(
      '$_baseUrl${path.startsWith('/') ? path : '/$path'}',
    );
    final uri = (queryParameters == null || queryParameters.isEmpty)
        ? baseUri
        : baseUri.replace(
            queryParameters: <String, String>{
              ...baseUri.queryParameters,
              ...queryParameters.map(
                (key, value) => MapEntry(key, value.toString()),
              ),
            },
          );

    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (accessToken != null && accessToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${accessToken.trim()}';
    }

    ownerDebugLog('http.request.started', {
      'method': method,
      'path': path,
      'hasAuthorization': headers.containsKey('Authorization'),
      'hasQueryParameters': queryParameters?.isNotEmpty == true,
    });

    final response = await _sendHttp(
      method,
      uri,
      headers,
      body,
    ).timeout(const Duration(seconds: 20));
    final payload = _decodeBody(response.bodyBytes);

    ownerDebugLog('http.request.completed', {
      'method': method,
      'path': path,
      'statusCode': response.statusCode,
      'hasPayload': payload != null,
    });

    if (response.statusCode == 401 &&
        allowRefreshRetry &&
        headers.containsKey('Authorization') &&
        path != '/auth/login' &&
        path != '/auth/refresh') {
      final refreshedAccessToken = await _tryRefreshAccessToken();
      if (refreshedAccessToken != null) {
        return _send(
          method,
          path,
          body: body,
          accessToken: refreshedAccessToken,
          queryParameters: queryParameters,
          allowRefreshRetry: false,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    if (response.statusCode == 401) {
      await _authStorage.clear();
    }

    final message =
        payload is Map<String, dynamic> &&
            payload['message'] is String &&
            (payload['message'] as String).trim().isNotEmpty
        ? (payload['message'] as String).trim()
        : 'A API do painel retornou um erro inesperado.';
    final code = payload is Map<String, dynamic> && payload['code'] is String
        ? payload['code'] as String
        : null;

    throw OwnerApiException(
      message: message,
      statusCode: response.statusCode,
      code: code,
    );
  }

  Future<http.Response> _sendHttp(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) {
    switch (method) {
      case 'GET':
        return _httpClient.get(uri, headers: headers);
      case 'POST':
        return _httpClient.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      default:
        throw ArgumentError.value(
          method,
          'method',
          'Metodo HTTP nao suportado.',
        );
    }
  }

  Future<String?> _tryRefreshAccessToken() async {
    final refreshToken = await _authStorage.readRefreshToken();
    final clientContext = await _authStorage.readClientContext();
    if (refreshToken == null ||
        refreshToken.trim().isEmpty ||
        clientContext == null) {
      ownerDebugLog('http.refresh.skipped', {
        'hasRefreshToken':
            refreshToken != null && refreshToken.trim().isNotEmpty,
        'hasClientContext': clientContext != null,
      });
      return null;
    }

    try {
      ownerDebugLog('http.refresh.started', {
        'clientType': clientContext.clientType,
        'hasClientInstanceId': clientContext.clientInstanceId.isNotEmpty,
      });
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/refresh'),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'refreshToken': refreshToken,
              ...clientContext.toApiPayload(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      final payload = _decodeBody(response.bodyBytes);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (payload is! Map<String, dynamic>) {
          throw const OwnerApiException(
            message: 'A API nao retornou uma sessao valida.',
            statusCode: 401,
            code: 'OWNER_REFRESH_INVALID_PAYLOAD',
          );
        }
        final nextAccessToken = _readRequiredString(payload, 'accessToken');
        final nextRefreshToken = _readRequiredString(payload, 'refreshToken');
        await _authStorage.saveTokens(
          accessToken: nextAccessToken,
          refreshToken: nextRefreshToken,
        );
        ownerDebugLog('http.refresh.succeeded', {
          'hasAccessToken': nextAccessToken.trim().isNotEmpty,
          'hasRefreshToken': nextRefreshToken.trim().isNotEmpty,
        });
        return nextAccessToken;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await _authStorage.clear();
      }
      return null;
    } catch (error) {
      ownerDebugLog('http.refresh.failed', {
        'errorType': error.runtimeType.toString(),
      });
      return null;
    }
  }

  dynamic _decodeBody(List<int> bodyBytes) {
    final rawBody = utf8.decode(bodyBytes);
    if (rawBody.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return null;
    }
  }

  String _readRequiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw OwnerApiException(
      message: 'A API nao retornou o campo "$key" no formato esperado.',
      statusCode: 401,
      code: 'OWNER_INVALID_AUTH_PAYLOAD',
    );
  }

  static String _normalizeBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
