class AdminPermissionDefinition {
  const AdminPermissionDefinition({
    required this.permissionKey,
    required this.description,
    required this.category,
    required this.riskLevel,
    required this.actionType,
    required this.scopes,
    required this.requiresDryRun,
    required this.requiresReason,
    required this.requiresExplicitConfirmation,
    required this.requiresPersistentAudit,
  });

  final String permissionKey;
  final String description;
  final String category;
  final String riskLevel;
  final String? actionType;
  final List<String> scopes;
  final bool requiresDryRun;
  final bool requiresReason;
  final bool requiresExplicitConfirmation;
  final bool requiresPersistentAudit;

  factory AdminPermissionDefinition.fromMap(Map<String, dynamic> map) {
    return AdminPermissionDefinition(
      permissionKey: _readString(map, 'permissionKey'),
      description: _readString(map, 'description', fallback: 'Nao informado'),
      category: _readString(map, 'category', fallback: 'Sem categoria'),
      riskLevel: _readString(map, 'riskLevel', fallback: 'unknown'),
      actionType: _readOptionalString(map, 'actionType'),
      scopes: _readStringList(map['scopes']),
      requiresDryRun: map['requiresDryRun'] == true,
      requiresReason: map['requiresReason'] == true,
      requiresExplicitConfirmation: map['requiresExplicitConfirmation'] == true,
      requiresPersistentAudit: map['requiresPersistentAudit'] == true,
    );
  }
}

class AdminPermissionsCatalog {
  const AdminPermissionsCatalog({required this.items});

  final List<AdminPermissionDefinition> items;

  factory AdminPermissionsCatalog.fromMap(Map<String, dynamic> map) {
    final rawItems = map['catalog'] ?? map['knownPermissions'];
    return AdminPermissionsCatalog(
      items: _readMapList(
        rawItems,
      ).map(AdminPermissionDefinition.fromMap).toList(growable: false),
    );
  }
}

class AdminUserPermission {
  const AdminUserPermission({
    required this.id,
    required this.actorUserId,
    required this.permissionKey,
    required this.scope,
    required this.scopeId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.revokedAt,
  });

  final String id;
  final String actorUserId;
  final String permissionKey;
  final String scope;
  final String scopeId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? revokedAt;

  factory AdminUserPermission.fromMap(Map<String, dynamic> map) {
    final isActive = map['isActive'] != false;
    return AdminUserPermission(
      id: _readString(map, 'id', fallback: 'Indisponivel'),
      actorUserId: _readString(map, 'actorUserId', fallback: 'Nao informado'),
      permissionKey: _readString(map, 'permissionKey'),
      scope: _readString(map, 'scope', fallback: 'platform'),
      scopeId: _readString(map, 'scopeId', fallback: '*'),
      isActive: isActive,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      revokedAt: _readOptionalDateTime(map, 'revokedAt'),
    );
  }
}

class AdminUserPermissionsSnapshot {
  const AdminUserPermissionsSnapshot({
    required this.adminUserId,
    required this.activePermissions,
    required this.inactivePermissions,
    required this.auditEventId,
  });

  final String adminUserId;
  final List<AdminUserPermission> activePermissions;
  final List<AdminUserPermission> inactivePermissions;
  final String? auditEventId;

  factory AdminUserPermissionsSnapshot.fromMap(
    Map<String, dynamic> map, {
    required String adminUserId,
  }) {
    final active = _readMapList(
      map['permissions'],
    ).map(AdminUserPermission.fromMap).toList(growable: false);
    final inactive = _readMapList(
      map['inactivePermissions'] ?? map['revokedPermissions'],
    ).map(AdminUserPermission.fromMap).toList(growable: false);

    return AdminUserPermissionsSnapshot(
      adminUserId: adminUserId,
      activePermissions: active,
      inactivePermissions: inactive,
      auditEventId: _readOptionalString(map, 'auditEventId'),
    );
  }
}

class AdminPermissionMutationResult {
  const AdminPermissionMutationResult({
    required this.ok,
    required this.code,
    required this.message,
    required this.auditEventId,
    required this.permission,
    required this.revokedCount,
  });

  final bool ok;
  final String code;
  final String message;
  final String? auditEventId;
  final AdminUserPermission? permission;
  final int? revokedCount;

  factory AdminPermissionMutationResult.fromMap(Map<String, dynamic> map) {
    final rawPermission = map['permission'];
    final details = map['details'];
    return AdminPermissionMutationResult(
      ok: map['ok'] == true,
      code: _readString(map, 'code', fallback: 'ADMIN_PERMISSION_UNKNOWN'),
      message: _readString(
        map,
        'message',
        fallback: 'Resposta administrativa recebida.',
      ),
      auditEventId: _readOptionalString(map, 'auditEventId'),
      permission: rawPermission is Map<String, dynamic>
          ? AdminUserPermission.fromMap(rawPermission)
          : null,
      revokedCount: details is Map<String, dynamic>
          ? _readOptionalInt(details, 'revokedCount')
          : null,
    );
  }
}

String _readString(Map<String, dynamic> map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (fallback != null) {
    return fallback;
  }
  throw FormatException('Campo "$key" ausente no payload de permissoes.');
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

int? _readOptionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is int ? value : null;
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is List<dynamic>) {
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

List<String> _readStringList(Object? value) {
  if (value is! List<dynamic>) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
