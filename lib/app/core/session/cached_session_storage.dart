import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entitlements/plan_entitlements.dart';
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
  static const _membershipPermissionsKey =
      'session.cached.membership.permissions';
  static const _employeeIdKey = 'session.cached.employee.id';
  static const _employeeRoleKey = 'session.cached.employee.role';
  static const _employeeStatusKey = 'session.cached.employee.status';
  static const _employeePermissionsKey = 'session.cached.employee.permissions';
  static const _entitlementsPlanKey = 'session.cached.entitlements.plan';
  static const _entitlementsFeaturesKey =
      'session.cached.entitlements.features';
  static const _entitlementsMaxDevicesKey =
      'session.cached.entitlements.max_devices';
  static const _entitlementsMaxEmployeesKey =
      'session.cached.entitlements.max_employees';
  static const _entitlementsReportPeriodsKey =
      'session.cached.entitlements.report_periods';

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
    _membershipPermissionsKey,
    _employeeIdKey,
    _employeeRoleKey,
    _employeeStatusKey,
    _employeePermissionsKey,
    _entitlementsPlanKey,
    _entitlementsFeaturesKey,
    _entitlementsMaxDevicesKey,
    _entitlementsMaxEmployeesKey,
    _entitlementsReportPeriodsKey,
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
        entitlements: _readEntitlements(preferences),
      ),
      startedAt: DateTime.now(),
      isOfflineFallback: true,
      clientInstanceId: clientInstanceId,
      membership: AppMembershipContext(
        role: _readString(preferences, _userRoleKey) ?? 'Operador',
        permissions: _readStringSet(preferences, _membershipPermissionsKey),
      ),
      employee: _readEmployeeContext(preferences),
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
    await preferences.setStringList(
      _membershipPermissionsKey,
      session.membership?.permissions.toList() ?? const <String>[],
    );
    await _saveEmployeeContext(preferences, session.employee);
    await _saveEntitlements(preferences, session.company.entitlements);
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

  static Set<String> _readStringSet(SharedPreferences preferences, String key) {
    return (preferences.getStringList(key) ?? const <String>[])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static AppEmployeeContext? _readEmployeeContext(
    SharedPreferences preferences,
  ) {
    final id = _readString(preferences, _employeeIdKey);
    final role = _readString(preferences, _employeeRoleKey);
    final status = _readString(preferences, _employeeStatusKey);
    if (id == null || role == null || status == null) {
      return null;
    }
    return AppEmployeeContext(
      id: id,
      role: role,
      status: status,
      permissions: _readStringSet(preferences, _employeePermissionsKey),
    );
  }

  static Future<void> _saveEmployeeContext(
    SharedPreferences preferences,
    AppEmployeeContext? employee,
  ) async {
    if (employee == null) {
      await preferences.remove(_employeeIdKey);
      await preferences.remove(_employeeRoleKey);
      await preferences.remove(_employeeStatusKey);
      await preferences.remove(_employeePermissionsKey);
      return;
    }
    await preferences.setString(_employeeIdKey, employee.id.trim());
    await preferences.setString(_employeeRoleKey, employee.role.trim());
    await preferences.setString(_employeeStatusKey, employee.status.trim());
    await preferences.setStringList(
      _employeePermissionsKey,
      employee.permissions.toList(),
    );
  }

  static PlanEntitlements _readEntitlements(SharedPreferences preferences) {
    final plan = _readString(preferences, _entitlementsPlanKey);
    final enabledFeatureKeys =
        preferences.getStringList(_entitlementsFeaturesKey) ?? const <String>[];
    final reportPeriodKeys =
        preferences.getStringList(_entitlementsReportPeriodsKey) ??
        const <String>[];
    if (plan == null &&
        enabledFeatureKeys.isEmpty &&
        reportPeriodKeys.isEmpty) {
      return PlanEntitlements.freeFallback();
    }

    final features = <String, bool>{
      for (final featureKey in enabledFeatureKeys) featureKey: true,
    };
    return PlanEntitlements.fromJson(<String, dynamic>{
      'plan': plan,
      'features': features,
      'limits': <String, dynamic>{
        'maxDevices': preferences.getInt(_entitlementsMaxDevicesKey),
        'maxEmployees': preferences.getInt(_entitlementsMaxEmployeesKey),
        'reportPeriods': reportPeriodKeys,
      },
    });
  }

  static Future<void> _saveEntitlements(
    SharedPreferences preferences,
    PlanEntitlements entitlements,
  ) async {
    await preferences.setString(_entitlementsPlanKey, entitlements.plan.key);
    await preferences.setStringList(
      _entitlementsFeaturesKey,
      entitlements.features.map((feature) => feature.key).toList(),
    );
    await preferences.setInt(
      _entitlementsMaxDevicesKey,
      entitlements.limits.maxDevices,
    );
    await preferences.setInt(
      _entitlementsMaxEmployeesKey,
      entitlements.limits.maxEmployees,
    );
    await preferences.setStringList(
      _entitlementsReportPeriodsKey,
      entitlements.limits.reportPeriods.map((period) => period.key).toList(),
    );
  }
}
