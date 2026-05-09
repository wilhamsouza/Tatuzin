import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/owner_models.dart';
import 'owner_debug_log.dart';

class OwnerClientContext {
  const OwnerClientContext({
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

class OwnerAuthStorage extends ChangeNotifier {
  OwnerAuthStorage();

  static const _accessTokenKey = 'tatuzin_owner_access_token';
  static const _refreshTokenKey = 'tatuzin_owner_refresh_token';
  static const _clientTypeKey = 'tatuzin_owner_client_type';
  static const _clientInstanceIdKey = 'tatuzin_owner_client_instance_id';
  static const _deviceLabelKey = 'tatuzin_owner_device_label';
  static const _platformKey = 'tatuzin_owner_platform';
  static const _appVersionKey = 'tatuzin_owner_app_version';
  static const _sessionSnapshotKey = 'tatuzin_owner_session_snapshot';

  static final Random _random = Random.secure();

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);
    await preferences.remove(_sessionSnapshotKey);
    ownerDebugLog('auth.storage.cleared');
    notifyListeners();
  }

  Future<OwnerClientContext> ensureClientContext({
    String clientType = 'unknown',
    String? deviceLabel = 'Tatuzin Owner Web',
    String? platform = 'web',
    String? appVersion = 'owner-web',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final existingClientInstanceId = preferences
        .getString(_clientInstanceIdKey)
        ?.trim();
    final clientInstanceId =
        existingClientInstanceId == null || existingClientInstanceId.isEmpty
        ? _generateClientInstanceId()
        : existingClientInstanceId;

    final normalizedClientType = clientType.trim().isEmpty
        ? 'unknown'
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

    ownerDebugLog('auth.storage.client_context.ready', {
      'clientType': normalizedClientType,
      'hasClientInstanceId': clientInstanceId.isNotEmpty,
      'platform': normalizedPlatform,
      'appVersion': normalizedAppVersion,
    });

    return OwnerClientContext(
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

  Future<String?> readRefreshToken() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalizeOptional(preferences.getString(_refreshTokenKey));
  }

  Future<OwnerClientContext?> readClientContext() async {
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
    return OwnerClientContext(
      clientType: clientType,
      clientInstanceId: clientInstanceId,
      deviceLabel: _normalizeOptional(preferences.getString(_deviceLabelKey)),
      platform: _normalizeOptional(preferences.getString(_platformKey)),
      appVersion: _normalizeOptional(preferences.getString(_appVersionKey)),
    );
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessTokenKey, accessToken.trim());
    await preferences.setString(_refreshTokenKey, refreshToken.trim());
    ownerDebugLog('auth.storage.tokens_saved', {
      'hasAccessToken': accessToken.trim().isNotEmpty,
      'hasRefreshToken': refreshToken.trim().isNotEmpty,
    });
    notifyListeners();
  }

  Future<OwnerSession?> readSessionSnapshot() async {
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
      return OwnerSession.fromStorageMap(
        payload,
        accessToken: accessToken,
        refreshToken: await readRefreshToken(),
      );
    } catch (error) {
      ownerDebugLog('auth.storage.snapshot.invalid', {
        'errorType': error.runtimeType.toString(),
      });
      return null;
    }
  }

  Future<void> saveSessionSnapshot(OwnerSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _sessionSnapshotKey,
      jsonEncode(session.toStorageMap()),
    );
    ownerDebugLog('auth.storage.snapshot_saved', {
      'userEmail': session.user.email,
      'companyId': session.company.id,
      'membershipRole': session.membership.role,
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
    return 'own-$timestamp-$suffix';
  }
}
