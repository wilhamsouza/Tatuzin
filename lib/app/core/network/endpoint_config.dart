class EndpointConfig {
  static const Object _noChange = Object();

  const EndpointConfig({
    this.baseUrl,
    this.apiVersion = 'v1',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });

  const EndpointConfig.localDevelopment({
    this.baseUrl = 'http://10.0.2.2:4000',
    this.apiVersion = 'api',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });

  final String? baseUrl;
  final String apiVersion;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  static String? normalizeBaseUrl(String? value, {required String apiVersion}) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    var normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    final apiSuffix = '/${apiVersion.toLowerCase()}';
    if (normalized.toLowerCase().endsWith(apiSuffix)) {
      normalized = normalized.substring(
        0,
        normalized.length - apiSuffix.length,
      );
    }

    return normalized;
  }

  bool get isConfigured {
    final value = baseUrl?.trim();
    return value != null && value.isNotEmpty;
  }

  String get summaryLabel {
    if (!isConfigured) {
      return 'Nao configurado';
    }

    return '$baseUrl/$apiVersion';
  }

  EndpointConfig copyWith({
    Object? baseUrl = _noChange,
    String? apiVersion,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) {
    final resolvedApiVersion = apiVersion ?? this.apiVersion;
    final resolvedBaseUrl = identical(baseUrl, _noChange)
        ? this.baseUrl
        : normalizeBaseUrl(baseUrl as String?, apiVersion: resolvedApiVersion);

    return EndpointConfig(
      baseUrl: resolvedBaseUrl,
      apiVersion: resolvedApiVersion,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
    );
  }

  Uri? uriFor(String path) {
    if (!isConfigured) {
      return null;
    }

    final normalizedBase = baseUrl!.endsWith('/') ? baseUrl! : '${baseUrl!}/';
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$normalizedBase$apiVersion/$normalizedPath');
  }
}
