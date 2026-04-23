import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../network/endpoint_config.dart';
import 'app_data_mode.dart';

class AppEnvironment {
  const AppEnvironment({
    required this.name,
    required this.productName,
    required this.dataMode,
    required this.endpointConfig,
    required this.authEnabled,
    required this.remoteSyncEnabled,
    required this.multiUserEnabled,
    required this.multiCompanyEnabled,
  });

  const AppEnvironment.localDefault()
    : name = 'local-default',
      productName = AppConstants.appName,
      dataMode = AppDataMode.localOnly,
      endpointConfig = const EndpointConfig(),
      authEnabled = false,
      remoteSyncEnabled = false,
      multiUserEnabled = false,
      multiCompanyEnabled = false;

  factory AppEnvironment.remoteDefault() {
    return AppEnvironment(
      name: 'remote-default',
      productName: AppConstants.appName,
      dataMode: AppDataMode.futureRemoteReady,
      endpointConfig: EndpointConfig.remoteDefault(),
      authEnabled: true,
      remoteSyncEnabled: false,
      multiUserEnabled: true,
      multiCompanyEnabled: true,
    );
  }

  const AppEnvironment.localDevelopmentRemoteDefault()
    : name = 'remote-default',
      productName = AppConstants.appName,
      dataMode = AppDataMode.futureRemoteReady,
      endpointConfig = const EndpointConfig.localDevelopment(),
      authEnabled = true,
      remoteSyncEnabled = false,
      multiUserEnabled = true,
      multiCompanyEnabled = true;

  final String name;
  final String productName;
  final AppDataMode dataMode;
  final EndpointConfig endpointConfig;
  final bool authEnabled;
  final bool remoteSyncEnabled;
  final bool multiUserEnabled;
  final bool multiCompanyEnabled;

  bool get isLocalOnly => dataMode == AppDataMode.localOnly;

  AppEnvironment copyWith({
    String? name,
    String? productName,
    AppDataMode? dataMode,
    EndpointConfig? endpointConfig,
    bool? authEnabled,
    bool? remoteSyncEnabled,
    bool? multiUserEnabled,
    bool? multiCompanyEnabled,
  }) {
    return AppEnvironment(
      name: name ?? this.name,
      productName: productName ?? this.productName,
      dataMode: dataMode ?? this.dataMode,
      endpointConfig: endpointConfig ?? this.endpointConfig,
      authEnabled: authEnabled ?? this.authEnabled,
      remoteSyncEnabled: remoteSyncEnabled ?? this.remoteSyncEnabled,
      multiUserEnabled: multiUserEnabled ?? this.multiUserEnabled,
      multiCompanyEnabled: multiCompanyEnabled ?? this.multiCompanyEnabled,
    );
  }
}

final initialAppEnvironmentProvider = Provider<AppEnvironment>((ref) {
  return const AppEnvironment.localDefault();
});

final appEnvironmentProvider =
    NotifierProvider<AppEnvironmentController, AppEnvironment>(
      AppEnvironmentController.new,
    );

final appDataModeProvider = Provider<AppDataMode>((ref) {
  return ref.watch(appEnvironmentProvider).dataMode;
});

class AppEnvironmentController extends Notifier<AppEnvironment> {
  static final EndpointConfig _remoteDefaultEndpoint =
      EndpointConfig.remoteDefault();

  @override
  AppEnvironment build() {
    return ref.watch(initialAppEnvironmentProvider);
  }

  Future<void> setDataMode(AppDataMode mode) async {
    final developmentEndpoint = mode == AppDataMode.localOnly
        ? state.endpointConfig
        : _resolveRemoteEndpoint(state.endpointConfig);

    final nextState = _buildEnvironment(
      mode: mode,
      endpointConfig: developmentEndpoint,
    );
    state = nextState;
    await AppEnvironmentStorage.save(nextState);
  }

  Future<void> setEndpointBaseUrl(String baseUrl) async {
    final nextState = state.copyWith(
      endpointConfig: _remoteDefaultEndpoint.copyWith(baseUrl: baseUrl),
    );
    state = nextState;
    await AppEnvironmentStorage.save(nextState);
  }

  Future<void> resetToLocalDefault() async {
    const nextState = AppEnvironment.localDefault();
    state = nextState;
    await AppEnvironmentStorage.save(nextState);
  }

  EndpointConfig _resolveRemoteEndpoint(EndpointConfig current) {
    if (!current.isConfigured) {
      return _remoteDefaultEndpoint;
    }

    return current.copyWith(
      apiVersion: _remoteDefaultEndpoint.apiVersion,
      connectTimeout: _remoteDefaultEndpoint.connectTimeout,
      receiveTimeout: _remoteDefaultEndpoint.receiveTimeout,
    );
  }

  AppEnvironment _buildEnvironment({
    required AppDataMode mode,
    required EndpointConfig endpointConfig,
  }) {
    return AppEnvironment(
      name: mode == AppDataMode.localOnly ? 'local-default' : 'remote-default',
      productName: AppConstants.appName,
      dataMode: mode,
      endpointConfig: endpointConfig,
      authEnabled: mode != AppDataMode.localOnly,
      remoteSyncEnabled: mode == AppDataMode.futureHybridReady,
      multiUserEnabled: mode != AppDataMode.localOnly,
      multiCompanyEnabled: mode != AppDataMode.localOnly,
    );
  }
}

class AppEnvironmentStorage {
  const AppEnvironmentStorage._();

  static const String _dataModeKey = 'app.environment.data_mode';
  static const String _endpointBaseUrlKey = 'app.environment.endpoint_base_url';
  static const String _endpointApiVersionKey =
      'app.environment.endpoint_api_version';

  static Future<AppEnvironment> load() async {
    final preferences = await SharedPreferences.getInstance();
    final persistedMode = preferences.getString(_dataModeKey);
    final mode = persistedMode == null || persistedMode.trim().isEmpty
        ? _defaultDataMode()
        : _parseMode(persistedMode);
    final defaultEndpoint = mode == AppDataMode.localOnly
        ? const EndpointConfig()
        : EndpointConfig.remoteDefault();
    final apiVersion =
        preferences.getString(_endpointApiVersionKey)?.trim().isNotEmpty == true
        ? preferences.getString(_endpointApiVersionKey)!.trim()
        : defaultEndpoint.apiVersion;
    final persistedBaseUrl = _resolvePersistedBaseUrl(
      preferences.getString(_endpointBaseUrlKey),
    );
    var endpointConfig = defaultEndpoint.copyWith(apiVersion: apiVersion);
    if (persistedBaseUrl != null) {
      endpointConfig = endpointConfig.copyWith(baseUrl: persistedBaseUrl);
    }

    return AppEnvironment(
      name: mode == AppDataMode.localOnly ? 'local-default' : 'remote-default',
      productName: AppConstants.appName,
      dataMode: mode,
      endpointConfig: endpointConfig,
      authEnabled: mode != AppDataMode.localOnly,
      remoteSyncEnabled: mode == AppDataMode.futureHybridReady,
      multiUserEnabled: mode != AppDataMode.localOnly,
      multiCompanyEnabled: mode != AppDataMode.localOnly,
    );
  }

  static Future<void> save(AppEnvironment environment) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_dataModeKey, environment.dataMode.name);
    final baseUrl = environment.endpointConfig.baseUrl?.trim();
    if (baseUrl == null || baseUrl.isEmpty) {
      await preferences.remove(_endpointBaseUrlKey);
    } else {
      await preferences.setString(_endpointBaseUrlKey, baseUrl);
    }
    await preferences.setString(
      _endpointApiVersionKey,
      environment.endpointConfig.apiVersion,
    );
  }

  static AppDataMode _parseMode(String? rawValue) {
    for (final mode in AppDataMode.values) {
      if (mode.name == rawValue) {
        return mode;
      }
    }

    if (rawValue != null && rawValue.isNotEmpty) {
      debugPrint(
        'AppEnvironmentStorage: modo persistido desconhecido "$rawValue".',
      );
    }

    return AppDataMode.localOnly;
  }

  static AppDataMode _defaultDataMode() {
    return AppDataMode.futureRemoteReady;
  }

  static String? _resolvePersistedBaseUrl(String? rawValue) {
    final normalized = EndpointConfig.normalizeBaseUrl(
      rawValue,
      apiVersion: EndpointConfig.defaultApiVersion,
    );
    if (normalized == null) {
      return null;
    }

    if (EndpointConfig.isReleaseBuild &&
        EndpointConfig.isLocalNetworkBaseUrl(normalized)) {
      return null;
    }

    return normalized;
  }
}
