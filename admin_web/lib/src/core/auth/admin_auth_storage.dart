import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_models.dart';
import 'admin_debug_log.dart';

class AdminClientContext {
  const AdminClientContext({
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

class AdminAuthStorage extends ChangeNotifier {
  AdminAuthStorage();

  static const _accessTokenKey = 'tatuzin_admin_access_token';
  static const _refreshTokenKey = 'tatuzin_admin_refresh_token';
  static const _clientTypeKey = 'tatuzin_admin_client_type';
  static const _clientInstanceIdKey = 'tatuzin_admin_client_instance_id';
  static const _deviceLabelKey = 'tatuzin_admin_device_label';
  static const _platformKey = 'tatuzin_admin_platform';
  static const _appVersionKey = 'tatuzin_admin_app_version';
  static const _sessionSnapshotKey = 'tatuzin_admin_session_snapshot';

  static final Random _random = Random.secure();

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);
    await preferences.remove(_sessionSnapshotKey);
    adminDebugLog('auth.storage.cleared');
    notifyListeners();
  }

  Future<AdminClientContext> ensureClientContext({
    String clientType = 'admin_web',
    String? deviceLabel = 'Tatuzin Admin Web',
    String? platform = 'web',
    String? appVersion = 'admin-web',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final existingClientInstanceId =
        preferences.getString(_clientInstanceIdKey)?.trim();
    final clientInstanceId =
        existingClientInstanceId == null || existingClientInstanceId.isEmpty
        ? _generateClientInstanceId()
        : existingClientInstanceId;

    final normalizedClientType = clientType.trim().isEmpty
        ? 'admin_web'
        : clientType.trim();
    final normalizedDeviceLabel = _normalizeOptional(deviceLabel);
    final normalizedPlatform = _normalizeOptional(platform);
    final normalizedAppVersion = _normalizeOptional(appVersion);

    await preferences.setString(_clientTypeKey, normalizedClientType);
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

    adminDebugLog('auth.storage.client_context.ready', {
      'clientType': normalizedClientType,
      'clientInstanceId': clientInstanceId,
      'platform': normalizedPlatform,
      'appVersion': normalizedAppVersion,
    });

    return AdminClientContext(
      clientType: normalizedClientType,
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

  Future<String?> readAccessToken() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalizeOptional(preferences.getString(_accessTokenKey));
  }

  Future<AdminClientContext?> readClientContext() async {
    final preferences = await SharedPreferences.getInstance();
    final clientType = _normalizeOptional(preferences.getString(_clientTypeKey));
    final clientInstanceId = _normalizeOptional(
      preferences.getString(_clientInstanceIdKey),
    );
    if (clientType == null || clientInstanceId == null) {
      return null;
    }

    return AdminClientContext(
      clientType: clientType,
      clientInstanceId: clientInstanceId,
      deviceLabel: _normalizeOptional(preferences.getString(_deviceLabelKey)),
      platform: _normalizeOptional(preferences.getString(_platformKey)),
      appVersion: _normalizeOptional(preferences.getString(_appVersionKey)),
    );
  }

  Future<String?> readRefreshToken() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalizeOptional(preferences.getString(_refreshTokenKey));
  }

  Future<AdminSession?> readSessionSnapshot() async {
    final preferences = await SharedPreferences.getInstance();
    final rawSnapshot = _normalizeOptional(
      preferences.getString(_sessionSnapshotKey),
    );
    final accessToken = await readAccessToken();
    if (rawSnapshot == null || accessToken == null) {
      return null;
    }

    try {
      final payload = jsonDecode(rawSnapshot);
      if (payload is! Map<String, dynamic>) {
        return null;
      }

      final session = AdminSession.fromStorageMap(
        payload,
        accessToken: accessToken,
        refreshToken: await readRefreshToken(),
      );
      adminDebugLog('auth.storage.snapshot.loaded', {
        'userEmail': session.user.email,
        'isPlatformAdmin': session.user.isPlatformAdmin,
        'sessionId': session.activeSession?.id,
      });
      return session;
    } catch (error) {
      adminDebugLog('auth.storage.snapshot.invalid', {
        'error': error.toString(),
      });
      return null;
    }
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessTokenKey, accessToken.trim());
    await preferences.setString(_refreshTokenKey, refreshToken.trim());
    adminDebugLog('auth.storage.tokens_saved', {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });
    notifyListeners();
  }

  Future<void> saveSessionSnapshot(AdminSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _sessionSnapshotKey,
      jsonEncode(session.toStorageMap()),
    );
    adminDebugLog('auth.storage.snapshot_saved', {
      'userEmail': session.user.email,
      'isPlatformAdmin': session.user.isPlatformAdmin,
      'sessionId': session.activeSession?.id,
    });
    notifyListeners();
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
    return 'adm-$timestamp-$suffix';
  }
}
