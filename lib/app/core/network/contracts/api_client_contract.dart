class ApiRequestOptions {
  const ApiRequestOptions({
    this.headers = const <String, String>{},
    this.queryParameters = const <String, Object?>{},
    this.timeout = const Duration(seconds: 15),
  });

  final Map<String, String> headers;
  final Map<String, Object?> queryParameters;
  final Duration timeout;
}

class ApiResponse<T> {
  const ApiResponse({
    required this.statusCode,
    required this.data,
    required this.headers,
  });

  final int statusCode;
  final T data;
  final Map<String, String> headers;
}

abstract interface class ApiClientContract {
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  });

  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  });

  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  });

  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  });

  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  });
}
