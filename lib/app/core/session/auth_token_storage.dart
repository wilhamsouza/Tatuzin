import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthClientContext {
  const AuthClientContext({
    required this.clientType,
    required this.clientInstanceId,
    this.deviceLabel,
    this.platform,
    this.appVersion,
  });

  final String clientType;
  final String clientInstanceId;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;

  Map<String, dynamic> toApiPayload() {
    return <String, dynamic>{
      'clientType': clientType,
      'clientInstanceId': clientInstanceId,
      if (deviceLabel?.trim().isNotEmpty ?? false) 'deviceLabel': deviceLabel,
      if (platform?.trim().isNotEmpty ?? false) 'platform': platform,
      if (appVersion?.trim().isNotEmpty ?? false) 'appVersion': appVersion,
    };
  }
}

abstract interface class AuthTokenStorage {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<AuthClientContext?> readClientContext();

  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  });

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });

  Future<void> clear();
}

final authTokenStorageProvider = Provider<AuthTokenStorage>((ref) {
  return SharedPreferencesAuthTokenStorage();
});

class SharedPreferencesAuthTokenStorage implements AuthTokenStorage {
  SharedPreferencesAuthTokenStorage();

  static const String _accessTokenKey = 'session.remote_access_token';
  static const String _refreshTokenKey = 'session.remote_refresh_token';
  static const String _clientTypeKey = 'session.remote_client_type';
  static const String _clientInstanceIdKey = 'session.remote_client_instance_id';
  static const String _deviceLabelKey = 'session.remote_device_label';
  static const String _platformKey = 'session.remote_platform';
  static const String _appVersionKey = 'session.remote_app_version';

  static final Random _random = Random.secure();

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);
  }

  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final existingClientInstanceId =
        preferences.getString(_clientInstanceIdKey)?.trim();
    final clientInstanceId =
        existingClientInstanceId == null || existingClientInstanceId.isEmpty
        ? _generateClientInstanceId()
        : existingClientInstanceId;

    final normalizedDeviceLabel = _normalizeOptional(deviceLabel);
    final normalizedPlatform = _normalizeOptional(platform);
    final normalizedAppVersion = _normalizeOptional(appVersion);

    await preferences.setString(_clientTypeKey, clientType.trim());
    await preferences.setString(_clientInstanceIdKey, clientInstanceId);

    if (normalizedDeviceLabel != null) {
      await preferences.setString(_deviceLabelKey, normalizedDeviceLabel);
    }
    if (normalizedPlatform != null) {
      await preferences.setString(_platformKey, normalizedPlatform);
    }
    if (normalizedAppVersion != null) {
      await preferences.setString(_appVersionKey, normalizedAppVersion);
    }

    return AuthClientContext(
      clientType: clientType.trim(),
      clientInstanceId: clientInstanceId,
      deviceLabel:
          normalizedDeviceLabel ??
          _normalizeOptional(preferences.getString(_deviceLabelKey)),
      platform:
          normalizedPlatform ??
          _normalizeOptional(preferences.getString(_platformKey)),
      appVersion:
          normalizedAppVersion ??
          _normalizeOptional(preferences.getString(_appVersionKey)),
    );
  }

  @override
  Future<String?> readAccessToken() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalizeOptional(preferences.getString(_accessTokenKey));
  }

  @override
  Future<AuthClientContext?> readClientContext() async {
    final preferences = await SharedPreferences.getInstance();
    final clientType = _normalizeOptional(preferences.getString(_clientTypeKey));
    final clientInstanceId = _normalizeOptional(
      preferences.getString(_clientInstanceIdKey),
    );

    if (clientType == null || clientInstanceId == null) {
      return null;
    }

    return AuthClientContext(
      clientType: clientType,
      clientInstanceId: clientInstanceId,
      deviceLabel: _normalizeOptional(preferences.getString(_deviceLabelKey)),
      platform: _normalizeOptional(preferences.getString(_platformKey)),
      appVersion: _normalizeOptional(preferences.getString(_appVersionKey)),
    );
  }

  @override
  Future<String?> readRefreshToken() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalizeOptional(preferences.getString(_refreshTokenKey));
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessTokenKey, accessToken.trim());
    await preferences.setString(_refreshTokenKey, refreshToken.trim());
  }

  static String? _normalizeOptional(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String _generateClientInstanceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = List<String>.generate(
      4,
      (_) => _random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    ).join();
    return 'mob-$timestamp-$suffix';
  }
}
