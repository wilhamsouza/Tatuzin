import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_session.dart';
import 'app_user.dart';
import 'company_context.dart';

abstract interface class CachedSessionStorage {
  Future<AppSession?> readSession();

  Future<void> saveSession(AppSession session);

  Future<void> clear();
}

final cachedSessionStorageProvider = Provider<CachedSessionStorage>((ref) {
  return SharedPreferencesCachedSessionStorage();
});

class SharedPreferencesCachedSessionStorage implements CachedSessionStorage {
  static const _userIdKey = 'session.cached.user_id';
  static const _userNameKey = 'session.cached.user_name';
  static const _userEmailKey = 'session.cached.user_email';
  static const _userRoleKey = 'session.cached.user_role';
  static const _userPlatformAdminKey = 'session.cached.user_platform_admin';
  static const _companyIdKey = 'session.cached.company_id';
  static const _companyNameKey = 'session.cached.company_name';
  static const _companyLegalNameKey = 'session.cached.company_legal_name';
  static const _companyDocumentKey = 'session.cached.company_document';
  static const _licensePlanKey = 'session.cached.license_plan';
  static const _licenseStatusKey = 'session.cached.license_status';
  static const _licenseStartsAtKey = 'session.cached.license_starts_at';
  static const _licenseExpiresAtKey = 'session.cached.license_expires_at';
  static const _maxDevicesKey = 'session.cached.max_devices';
  static const _syncEnabledKey = 'session.cached.sync_enabled';
  static const _clientInstanceIdKey = 'session.cached.client_instance_id';

  static const _allKeys = <String>[
    _userIdKey,
    _userNameKey,
    _userEmailKey,
    _userRoleKey,
    _userPlatformAdminKey,
    _companyIdKey,
    _companyNameKey,
    _companyLegalNameKey,
    _companyDocumentKey,
    _licensePlanKey,
    _licenseStatusKey,
    _licenseStartsAtKey,
    _licenseExpiresAtKey,
    _maxDevicesKey,
    _syncEnabledKey,
    _clientInstanceIdKey,
  ];

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in _allKeys) {
      await preferences.remove(key);
    }
  }

  @override
  Future<AppSession?> readSession() async {
    final preferences = await SharedPreferences.getInstance();
    final userId = _readString(preferences, _userIdKey);
    final companyId = _readString(preferences, _companyIdKey);
    final clientInstanceId = _readString(preferences, _clientInstanceIdKey);
    if (userId == null || companyId == null || clientInstanceId == null) {
      return null;
    }

    final companyName =
        _readString(preferences, _companyNameKey) ?? 'Empresa Tatuzin';
    return AppSession(
      scope: SessionScope.authenticatedRemote,
      user: AppUser(
        localId: null,
        remoteId: userId,
        displayName:
            _readString(preferences, _userNameKey) ?? 'Operador Tatuzin',
        email: _readString(preferences, _userEmailKey),
        roleLabel: _readString(preferences, _userRoleKey) ?? 'Operador',
        kind: AppUserKind.remoteAuthenticated,
        isPlatformAdmin: preferences.getBool(_userPlatformAdminKey) ?? false,
      ),
      company: CompanyContext(
        localId: null,
        remoteId: companyId,
        displayName: companyName,
        legalName:
            _readString(preferences, _companyLegalNameKey) ?? companyName,
        documentNumber: _readString(preferences, _companyDocumentKey),
        licensePlan: _readString(preferences, _licensePlanKey),
        licenseStatus: _readString(preferences, _licenseStatusKey),
        licenseStartsAt: _readDateTime(preferences, _licenseStartsAtKey),
        licenseExpiresAt: _readDateTime(preferences, _licenseExpiresAtKey),
        maxDevices: preferences.getInt(_maxDevicesKey),
        syncEnabled: preferences.getBool(_syncEnabledKey) ?? false,
      ),
      startedAt: DateTime.now(),
      isOfflineFallback: true,
      clientInstanceId: clientInstanceId,
    );
  }

  @override
  Future<void> saveSession(AppSession session) async {
    if (!session.hasOperationalIdentity) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_userIdKey, session.user.remoteId!.trim());
    await preferences.setString(_userNameKey, session.user.displayName.trim());
    await _setOptionalString(preferences, _userEmailKey, session.user.email);
    await preferences.setString(_userRoleKey, session.user.roleLabel.trim());
    await preferences.setBool(
      _userPlatformAdminKey,
      session.user.isPlatformAdmin,
    );
    await preferences.setString(
      _companyIdKey,
      session.company.remoteId!.trim(),
    );
    await preferences.setString(
      _companyNameKey,
      session.company.displayName.trim(),
    );
    await preferences.setString(
      _companyLegalNameKey,
      session.company.legalName.trim(),
    );
    await _setOptionalString(
      preferences,
      _companyDocumentKey,
      session.company.documentNumber,
    );
    await _setOptionalString(
      preferences,
      _licensePlanKey,
      session.company.licensePlan,
    );
    await _setOptionalString(
      preferences,
      _licenseStatusKey,
      session.company.licenseStatus,
    );
    await _setOptionalDateTime(
      preferences,
      _licenseStartsAtKey,
      session.company.licenseStartsAt,
    );
    await _setOptionalDateTime(
      preferences,
      _licenseExpiresAtKey,
      session.company.licenseExpiresAt,
    );
    final maxDevices = session.company.maxDevices;
    if (maxDevices == null) {
      await preferences.remove(_maxDevicesKey);
    } else {
      await preferences.setInt(_maxDevicesKey, maxDevices);
    }
    await preferences.setBool(_syncEnabledKey, session.company.syncEnabled);
    await preferences.setString(
      _clientInstanceIdKey,
      session.clientInstanceId!.trim(),
    );
  }

  static String? _readString(SharedPreferences preferences, String key) {
    final value = preferences.getString(key)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static DateTime? _readDateTime(SharedPreferences preferences, String key) {
    final value = _readString(preferences, key);
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static Future<void> _setOptionalString(
    SharedPreferences preferences,
    String key,
    String? value,
  ) async {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      await preferences.remove(key);
      return;
    }
    await preferences.setString(key, normalized);
  }

  static Future<void> _setOptionalDateTime(
    SharedPreferences preferences,
    String key,
    DateTime? value,
  ) async {
    if (value == null) {
      await preferences.remove(key);
      return;
    }
    await preferences.setString(key, value.toIso8601String());
  }
}
