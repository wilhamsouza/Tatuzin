import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  return SecureAuthTokenStorage();
});

abstract interface class SecureTokenStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureTokenStore implements SecureTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }
}

class SecureAuthTokenStorage implements AuthTokenStorage {
  SecureAuthTokenStorage({SecureTokenStore? secureTokenStore})
    : _secureTokenStore = secureTokenStore ?? FlutterSecureTokenStore();

  final SecureTokenStore _secureTokenStore;

  static const String _accessTokenKey = 'session.remote_access_token';
  static const String _refreshTokenKey = 'session.remote_refresh_token';
  static const String _clientTypeKey = 'session.remote_client_type';
  static const String _clientInstanceIdKey =
      'session.remote_client_instance_id';
  static const String _deviceLabelKey = 'session.remote_device_label';
  static const String _platformKey = 'session.remote_platform';
  static const String _appVersionKey = 'session.remote_app_version';

  static final Random _random = Random.secure();

  @override
  Future<void> clear() async {
    Object? firstSecureError;
    for (final key in const <String>[_accessTokenKey, _refreshTokenKey]) {
      try {
        await _secureTokenStore.delete(key: key);
      } catch (error) {
        firstSecureError ??= error;
      }
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);

    if (firstSecureError != null) {
      throw firstSecureError;
    }
  }

  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final existingClientInstanceId = preferences
        .getString(_clientInstanceIdKey)
        ?.trim();
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
    return _readTokenMigratingLegacy(_accessTokenKey);
  }

  @override
  Future<AuthClientContext?> readClientContext() async {
    final preferences = await SharedPreferences.getInstance();
    final clientType = _normalizeOptional(
      preferences.getString(_clientTypeKey),
    );
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
    return _readTokenMigratingLegacy(_refreshTokenKey);
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _writeAndConfirmSecureToken(
      key: _accessTokenKey,
      value: accessToken.trim(),
    );
    await _writeAndConfirmSecureToken(
      key: _refreshTokenKey,
      value: refreshToken.trim(),
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);
  }

  Future<String?> _readTokenMigratingLegacy(String key) async {
    final secureToken = _normalizeOptional(
      await _secureTokenStore.read(key: key),
    );
    if (secureToken != null) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
      return secureToken;
    }

    final preferences = await SharedPreferences.getInstance();
    final legacyToken = _normalizeOptional(preferences.getString(key));
    if (legacyToken == null) {
      return null;
    }

    await _writeAndConfirmSecureToken(key: key, value: legacyToken);
    await preferences.remove(key);
    return legacyToken;
  }

  Future<void> _writeAndConfirmSecureToken({
    required String key,
    required String value,
  }) async {
    await _secureTokenStore.write(key: key, value: value);
    final confirmed = _normalizeOptional(
      await _secureTokenStore.read(key: key),
    );
    if (confirmed != value) {
      throw StateError('secure_token_write_confirmation_failed:$key');
    }
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
