import 'package:flutter/foundation.dart';

class EndpointConfig {
  static const Object _noChange = Object();
  static const String envKey = 'TATUZIN_API_BASE_URL';
  static const String defaultApiVersion = 'api';
  static const String productionBaseUrl = 'https://api.tatuzin.com.br';
  static const String productionApiUrl =
      'https://api.tatuzin.com.br/$defaultApiVersion';
  static const String localDevelopmentBaseUrl = 'http://10.0.2.2:4000';
  static const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');
  static const String _compileTimeBaseUrl = String.fromEnvironment(envKey);

  const EndpointConfig({
    this.baseUrl,
    this.apiVersion = 'v1',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });

  const EndpointConfig.localDevelopment({
    this.baseUrl = localDevelopmentBaseUrl,
    this.apiVersion = defaultApiVersion,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });

  factory EndpointConfig.remoteDefault() {
    return EndpointConfig(
      baseUrl: resolveBuildBaseUrl(),
      apiVersion: defaultApiVersion,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    );
  }

  final String? baseUrl;
  final String apiVersion;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  static bool get isReleaseBuild => _isReleaseBuild;

  static bool get isProductionEndpointLocked => _isReleaseBuild;

  static bool get allowTechnicalEndpointOverride =>
      !isProductionEndpointLocked && kDebugMode;

  static String get productionResolvedBaseUrl =>
      normalizeBaseUrl(productionApiUrl, apiVersion: defaultApiVersion)!;

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

  static String resolveBuildBaseUrl({
    String configuredBaseUrl = _compileTimeBaseUrl,
    bool isReleaseBuild = _isReleaseBuild,
    String apiVersion = defaultApiVersion,
  }) {
    if (isReleaseBuild) {
      return normalizeBaseUrl(productionApiUrl, apiVersion: apiVersion)!;
    }

    final explicitBaseUrl = normalizeBaseUrl(
      configuredBaseUrl,
      apiVersion: apiVersion,
    );
    if (explicitBaseUrl != null) {
      return explicitBaseUrl;
    }

    const fallbackBaseUrl = localDevelopmentBaseUrl;
    return normalizeBaseUrl(fallbackBaseUrl, apiVersion: apiVersion)!;
  }

  static bool isLocalNetworkBaseUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return false;
    }

    final host =
        Uri.tryParse(trimmed)?.host.toLowerCase() ?? trimmed.toLowerCase();
    if (host.isEmpty) {
      return false;
    }

    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' ||
        host == '0.0.0.0') {
      return true;
    }

    if (RegExp(r'^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host) ||
        RegExp(r'^192\.168\.\d{1,3}\.\d{1,3}$').hasMatch(host)) {
      return true;
    }

    final match = RegExp(
      r'^172\.(\d{1,3})\.\d{1,3}\.\d{1,3}$',
    ).firstMatch(host);
    if (match == null) {
      return false;
    }

    final secondOctet = int.tryParse(match.group(1) ?? '');
    return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
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

  bool get isOfficialProductionEndpoint {
    return normalizeBaseUrl(baseUrl, apiVersion: apiVersion) ==
            productionResolvedBaseUrl &&
        apiVersion == defaultApiVersion;
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
