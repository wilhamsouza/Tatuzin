import '../contracts/api_client_contract.dart';
import '../endpoint_config.dart';

class FakeApiClient implements ApiClientContract {
  const FakeApiClient(this._endpointConfig);

  final EndpointConfig _endpointConfig;

  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    return const ApiResponse<void>(
      statusCode: 204,
      data: null,
      headers: <String, String>{'x-mock-client': 'true'},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: _buildPayload(method: 'GET', path: path),
      headers: const <String, String>{'x-mock-client': 'true'},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: _buildPayload(method: 'POST', path: path, body: body),
      headers: const <String, String>{'x-mock-client': 'true'},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: _buildPayload(method: 'PUT', path: path, body: body),
      headers: const <String, String>{'x-mock-client': 'true'},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: _buildPayload(method: 'PATCH', path: path, body: body),
      headers: const <String, String>{'x-mock-client': 'true'},
    );
  }

  Map<String, dynamic> _buildPayload({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) {
    return <String, dynamic>{
      'mock': true,
      'method': method,
      'path': path,
      'endpoint': _endpointConfig.summaryLabel,
      'timestamp': DateTime.now().toIso8601String(),
      'body': body ?? const <String, dynamic>{},
    };
  }
}
