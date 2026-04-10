import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/admin_auth_storage.dart';
import '../auth/admin_debug_log.dart';

class AdminApiException implements Exception {
  const AdminApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

class AdminApiClient {
  AdminApiClient({
    required String baseUrl,
    required AdminAuthStorage authStorage,
    http.Client? httpClient,
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _authStorage = authStorage,
       _httpClient = httpClient ?? http.Client();

  final String _baseUrl;
  final AdminAuthStorage _authStorage;
  final http.Client _httpClient;

  Future<dynamic> getJson(
    String path, {
    String? accessToken,
    Map<String, dynamic>? queryParameters,
  }) async {
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
  }) async {
    return _send(
      'POST',
      path,
      body: body,
      accessToken: accessToken,
    );
  }

  Future<dynamic> patchJson(
    String path, {
    required Map<String, dynamic> body,
    String? accessToken,
  }) async {
    return _send(
      'PATCH',
      path,
      body: body,
      accessToken: accessToken,
    );
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    Map<String, dynamic>? queryParameters,
    bool allowRefreshRetry = true,
  }) async {
    final baseUri = Uri.parse('$_baseUrl${path.startsWith('/') ? path : '/$path'}');
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
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (accessToken != null && accessToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${accessToken.trim()}';
    }

    adminDebugLog('http.request.started', {
      'method': method,
      'path': path,
      'queryParameters': queryParameters,
      'hasAuthorization': headers.containsKey('Authorization'),
      'authorization': headers['Authorization'],
    });

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        break;
      default:
        throw ArgumentError.value(method, 'method', 'Metodo HTTP nao suportado.');
    }

    final rawBody = utf8.decode(response.bodyBytes);
    final payload = rawBody.trim().isEmpty ? null : jsonDecode(rawBody);
    adminDebugLog('http.request.completed', {
      'method': method,
      'path': path,
      'statusCode': response.statusCode,
      'hasPayload': payload != null,
    });

    if (
      response.statusCode == 401 &&
      allowRefreshRetry &&
      headers.containsKey('Authorization') &&
      path != '/auth/login' &&
      path != '/auth/refresh'
    ) {
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

    final message = payload is Map<String, dynamic> &&
            payload['message'] is String &&
            (payload['message'] as String).trim().isNotEmpty
        ? (payload['message'] as String).trim()
        : 'A API administrativa retornou um erro inesperado.';

    final code = payload is Map<String, dynamic> && payload['code'] is String
        ? (payload['code'] as String)
        : null;

    throw AdminApiException(
      message: message,
      statusCode: response.statusCode,
      code: code,
    );
  }

  Future<String?> _tryRefreshAccessToken() async {
    final refreshToken = await _authStorage.readRefreshToken();
    final clientContext = await _authStorage.readClientContext();
    if (
      refreshToken == null ||
      refreshToken.trim().isEmpty ||
      clientContext == null
    ) {
      adminDebugLog('http.refresh.skipped', {
        'hasRefreshToken': refreshToken != null && refreshToken.trim().isNotEmpty,
        'hasClientContext': clientContext != null,
      });
      return null;
    }

    try {
      adminDebugLog('http.refresh.started', {
        'clientType': clientContext.clientType,
        'clientInstanceId': clientContext.clientInstanceId,
      });
      final uri = Uri.parse('$_baseUrl/auth/refresh');
      final response = await _httpClient.post(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'refreshToken': refreshToken,
          ...clientContext.toApiPayload(),
        }),
      ).timeout(const Duration(seconds: 15));

      final rawBody = utf8.decode(response.bodyBytes);
      final payload = rawBody.trim().isEmpty ? null : jsonDecode(rawBody);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (payload is! Map<String, dynamic>) {
          throw const AdminApiException(
            message: 'A API administrativa nao retornou a nova sessao no formato esperado.',
            statusCode: 401,
            code: 'ADMIN_REFRESH_INVALID_PAYLOAD',
          );
        }

        final nextAccessToken = _readRequiredString(
          payload,
          'accessToken',
          fallbackMessage: 'A API administrativa nao retornou um novo access token.',
        );
        final nextRefreshToken = _readRequiredString(
          payload,
          'refreshToken',
          fallbackMessage: 'A API administrativa nao retornou um novo refresh token.',
        );
        await _authStorage.saveTokens(
          accessToken: nextAccessToken,
          refreshToken: nextRefreshToken,
        );
        adminDebugLog('http.refresh.succeeded', {
          'accessToken': nextAccessToken,
          'refreshToken': nextRefreshToken,
        });
        return nextAccessToken;
      }

      final message = payload is Map<String, dynamic> &&
              payload['message'] is String &&
              (payload['message'] as String).trim().isNotEmpty
          ? (payload['message'] as String).trim()
          : 'Sua sessao administrativa expirou.';

      if (response.statusCode == 401 || response.statusCode == 403) {
        await _authStorage.clear();
        adminDebugLog('http.refresh.rejected', {
          'statusCode': response.statusCode,
          'message': message,
        });
        throw AdminApiException(
          message: message,
          statusCode: response.statusCode,
          code: payload is Map<String, dynamic> && payload['code'] is String
              ? payload['code'] as String
              : 'ADMIN_SESSION_EXPIRED',
        );
      }

      throw AdminApiException(
        message: 'Nao foi possivel renovar a sessao administrativa agora.',
        statusCode: response.statusCode,
        code: 'ADMIN_REFRESH_FAILED',
      );
    } on TimeoutException catch (_) {
      adminDebugLog('http.refresh.timeout');
      throw const AdminApiException(
        message: 'Nao foi possivel renovar a sessao administrativa agora.',
        code: 'ADMIN_REFRESH_TIMEOUT',
      );
    }
  }

  static String _readRequiredString(
    Map<String, dynamic> payload,
    String key, {
    required String fallbackMessage,
  }) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw AdminApiException(
      message: fallbackMessage,
      statusCode: 401,
      code: 'ADMIN_REFRESH_INVALID_PAYLOAD',
    );
  }

  static String _normalizeBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      throw const AdminApiException(
        message: 'A URL base da API administrativa nao foi configurada.',
      );
    }
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }
}
