import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../errors/app_exceptions.dart';
import '../../session/auth_token_storage.dart';
import '../contracts/api_client_contract.dart';
import '../endpoint_config.dart';

typedef SessionInvalidationHandler = Future<void> Function();

class RealApiClient implements ApiClientContract {
  RealApiClient(
    this._endpointConfig, {
    http.Client? httpClient,
    AuthTokenStorage? tokenStorage,
    SessionInvalidationHandler? onSessionInvalidated,
  }) : _httpClient = httpClient ?? http.Client(),
       _tokenStorage = tokenStorage,
       _onSessionInvalidated = onSessionInvalidated;

  final EndpointConfig _endpointConfig;
  final http.Client _httpClient;
  final AuthTokenStorage? _tokenStorage;
  final SessionInvalidationHandler? _onSessionInvalidated;

  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    final response = await _send(
      method: 'DELETE',
      path: path,
      options: options,
    );

    return ApiResponse<void>(
      statusCode: response.statusCode,
      data: null,
      headers: response.headers,
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    return _send(method: 'GET', path: path, options: options);
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    return _send(method: 'POST', path: path, options: options, body: body);
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    return _send(method: 'PUT', path: path, options: options, body: body);
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    return _send(method: 'PATCH', path: path, options: options, body: body);
  }

  Future<ApiResponse<Map<String, dynamic>>> _send({
    required String method,
    required String path,
    required ApiRequestOptions options,
    Map<String, dynamic>? body,
    bool allowRefreshRetry = true,
  }) async {
    final uri = _buildUri(path, options);
    final headers = _buildHeaders(options.headers);

    try {
      final response = await _executeRequest(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        timeout: options.timeout,
      );
      final payload = _decodeBody(response);

      if (response.statusCode >= 400) {
        if (
          response.statusCode == 401 &&
          allowRefreshRetry &&
          _shouldAttemptRefresh(path, headers)
        ) {
          final refreshedAccessToken = await _tryRefreshAccessToken(
            timeout: options.timeout,
          );
          if (refreshedAccessToken != null) {
            final retryHeaders = _replaceAuthorizationHeader(
              headers,
              refreshedAccessToken,
            );
            return _send(
              method: method,
              path: path,
              options: ApiRequestOptions(
                headers: retryHeaders,
                queryParameters: options.queryParameters,
                timeout: options.timeout,
              ),
              body: body,
              allowRefreshRetry: false,
            );
          }
        }

        final message = _extractErrorMessage(payload, response.statusCode);
        if (response.statusCode == 401) {
          throw AuthenticationException(message);
        }
        throw NetworkRequestException(
          'Falha ao chamar ${uri.path}: $message',
          cause: response.statusCode,
        );
      }

      if (payload is! Map<String, dynamic>) {
        return ApiResponse<Map<String, dynamic>>(
          statusCode: response.statusCode,
          data: const <String, dynamic>{},
          headers: response.headers,
        );
      }

      return ApiResponse<Map<String, dynamic>>(
        statusCode: response.statusCode,
        data: payload,
        headers: response.headers,
      );
    } on TimeoutException catch (error) {
      throw NetworkRequestException(
        'A API demorou demais para responder.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw NetworkRequestException(
        'Nao foi possivel alcancar o backend configurado.',
        cause: error,
      );
    } on FormatException catch (error) {
      throw NetworkRequestException(
        'A API respondeu em um formato invalido.',
        cause: error,
      );
    } on AppException {
      rethrow;
    } catch (error) {
      throw NetworkRequestException(
        'Falha inesperada ao chamar a API remota.',
        cause: error,
      );
    }
  }

  Future<http.Response> _executeRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
    required Duration timeout,
  }) async {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamedResponse = await _httpClient.send(request).timeout(timeout);
    return http.Response.fromStream(streamedResponse);
  }

  Future<String?> _tryRefreshAccessToken({
    required Duration timeout,
  }) async {
    final tokenStorage = _tokenStorage;
    if (tokenStorage == null) {
      return null;
    }

    final refreshToken = await tokenStorage.readRefreshToken();
    final clientContext = await tokenStorage.readClientContext();
    if (
      refreshToken == null ||
      refreshToken.trim().isEmpty ||
      clientContext == null
    ) {
      return null;
    }

    final uri = _buildUri('/auth/refresh', const ApiRequestOptions());
    final response = await _executeRequest(
      method: 'POST',
      uri: uri,
      headers: _buildHeaders(const <String, String>{}),
      body: <String, dynamic>{
        'refreshToken': refreshToken,
        ...clientContext.toApiPayload(),
      },
      timeout: timeout,
    );
    final payload = _decodeBody(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (payload is! Map<String, dynamic>) {
        throw const AuthenticationException(
          'A API nao retornou uma nova sessao valida.',
        );
      }

      final nextAccessToken = _readRequiredString(
        payload,
        'accessToken',
        fallbackMessage: 'A API nao retornou o novo access token.',
      );
      final nextRefreshToken = _readRequiredString(
        payload,
        'refreshToken',
        fallbackMessage: 'A API nao retornou o novo refresh token.',
      );

      await tokenStorage.saveTokens(
        accessToken: nextAccessToken,
        refreshToken: nextRefreshToken,
      );
      return nextAccessToken;
    }

    final message = _extractErrorMessage(payload, response.statusCode);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await tokenStorage.clear();
      if (_onSessionInvalidated != null) {
        await _onSessionInvalidated();
      }
      throw AuthenticationException(message);
    }

    throw NetworkRequestException(
      'Nao foi possivel renovar a sessao remota agora.',
      cause: response.statusCode,
    );
  }

  bool _shouldAttemptRefresh(String path, Map<String, String> headers) {
    final hasAuthorization = headers.entries.any(
      (entry) =>
          entry.key.toLowerCase() == 'authorization' &&
          entry.value.trim().toLowerCase().startsWith('bearer '),
    );
    if (!hasAuthorization) {
      return false;
    }

    final normalizedPath = path.trim().toLowerCase();
    return normalizedPath != '/auth/login' &&
        normalizedPath != '/auth/refresh' &&
        normalizedPath != '/auth/register-initial';
  }

  Map<String, String> _replaceAuthorizationHeader(
    Map<String, String> headers,
    String accessToken,
  ) {
    final nextHeaders = <String, String>{};
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        continue;
      }
      nextHeaders[entry.key] = entry.value;
    }
    nextHeaders['Authorization'] = 'Bearer $accessToken';
    return nextHeaders;
  }

  Uri _buildUri(String path, ApiRequestOptions options) {
    final uri = _endpointConfig.uriFor(path);
    if (uri == null) {
      throw const NetworkRequestException(
        'Endpoint remoto nao configurado para este ambiente.',
      );
    }

    if (options.queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...options.queryParameters.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
      },
    );
  }

  Map<String, String> _buildHeaders(Map<String, String> headers) {
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...headers,
    };
  }

  dynamic _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return null;
    }

    return jsonDecode(text);
  }

  String _extractErrorMessage(dynamic payload, int statusCode) {
    if (payload is Map<String, dynamic>) {
      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }

    return 'Resposta HTTP $statusCode';
  }

  String _readRequiredString(
    Map<String, dynamic> source,
    String key, {
    required String fallbackMessage,
  }) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw AuthenticationException(fallbackMessage);
  }
}
