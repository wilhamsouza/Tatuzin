class AdminSession {
  const AdminSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.user,
    required this.company,
    required this.membership,
    required this.activeSession,
  });

  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final AdminUser user;
  final AdminCompanyContext company;
  final AdminMembershipContext membership;
  final AdminDeviceSession? activeSession;

  factory AdminSession.fromLoginResponse(Map<String, dynamic> map) {
    final token = _readString(map, 'accessToken');
    return AdminSession(
      accessToken: token,
      refreshToken: _readOptionalString(map, 'refreshToken'),
      tokenType: _readString(map, 'tokenType', fallback: 'Bearer'),
      user: AdminUser.fromMap(_readMap(map, 'user')),
      company: AdminCompanyContext.fromMap(_readMap(map, 'company')),
      membership: AdminMembershipContext.fromMap(_readMap(map, 'membership')),
      activeSession: map['session'] is Map<String, dynamic>
          ? AdminDeviceSession.fromMap(map['session'] as Map<String, dynamic>)
          : null,
    );
  }

  factory AdminSession.fromIdentityResponse(
    Map<String, dynamic> map, {
    required String accessToken,
  }) {
    return AdminSession(
      accessToken: accessToken,
      refreshToken: null,
      tokenType: 'Bearer',
      user: AdminUser.fromMap(_readMap(map, 'user')),
      company: AdminCompanyContext.fromMap(_readMap(map, 'company')),
      membership: AdminMembershipContext.fromMap(_readMap(map, 'membership')),
      activeSession: map['session'] is Map<String, dynamic>
          ? AdminDeviceSession.fromMap(map['session'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toStorageMap() {
    return <String, dynamic>{
      'tokenType': tokenType,
      'user': user.toMap(),
      'company': company.toMap(),
      'membership': membership.toMap(),
      if (activeSession != null) 'session': activeSession!.toMap(),
    };
  }

  factory AdminSession.fromStorageMap(
    Map<String, dynamic> map, {
    required String accessToken,
    String? refreshToken,
  }) {
    return AdminSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: _readString(map, 'tokenType', fallback: 'Bearer'),
      user: AdminUser.fromMap(_readMap(map, 'user')),
      company: AdminCompanyContext.fromMap(_readMap(map, 'company')),
      membership: AdminMembershipContext.fromMap(_readMap(map, 'membership')),
      activeSession: map['session'] is Map<String, dynamic>
          ? AdminDeviceSession.fromMap(map['session'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.name,
    required this.isPlatformAdmin,
  });

  final String id;
  final String email;
  final String name;
  final bool isPlatformAdmin;

  factory AdminUser.fromMap(Map<String, dynamic> map) {
    return AdminUser(
      id: _readString(map, 'id'),
      email: _readString(map, 'email'),
      name: _readString(map, 'name', fallback: 'Administrador'),
      isPlatformAdmin: map['isPlatformAdmin'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'name': name,
      'isPlatformAdmin': isPlatformAdmin,
    };
  }
}

class AdminCompanyContext {
  const AdminCompanyContext({
    required this.id,
    required this.name,
    required this.legalName,
    required this.documentNumber,
    required this.slug,
    required this.license,
  });

  final String id;
  final String name;
  final String legalName;
  final String? documentNumber;
  final String slug;
  final AdminLicenseSnapshot? license;

  factory AdminCompanyContext.fromMap(Map<String, dynamic> map) {
    final companyId = _readString(map, 'id');
    final companyName = _readString(map, 'name');
    final companyLegalName = _readString(
      map,
      'legalName',
      fallback: companyName,
    );
    final companySlug = _readString(map, 'slug');

    return AdminCompanyContext(
      id: companyId,
      name: companyName,
      legalName: companyLegalName,
      documentNumber: _readOptionalString(map, 'documentNumber'),
      slug: companySlug,
      license: map['license'] is Map<String, dynamic>
          ? AdminLicenseSnapshot.fromMap(
              map['license'] as Map<String, dynamic>,
              companyIdFallback: companyId,
              companyNameFallback: companyName,
              companyLegalNameFallback: companyLegalName,
              companySlugFallback: companySlug,
              companyIsActiveFallback: true,
            )
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'legalName': legalName,
      'documentNumber': documentNumber,
      'slug': slug,
      if (license != null) 'license': license!.toStorageMap(),
    };
  }
}

class AdminMembershipContext {
  const AdminMembershipContext({
    required this.id,
    required this.role,
    required this.isDefault,
  });

  final String id;
  final String role;
  final bool isDefault;

  factory AdminMembershipContext.fromMap(Map<String, dynamic> map) {
    return AdminMembershipContext(
      id: _readString(map, 'id'),
      role: _readString(map, 'role'),
      isDefault: map['isDefault'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'role': role,
      'isDefault': isDefault,
    };
  }
}

class AdminDashboardSnapshot {
  const AdminDashboardSnapshot({
    required this.companies,
    required this.auditSummary,
    required this.syncSummary,
  });

  final List<AdminCompanySummary> companies;
  final AdminAuditSummary auditSummary;
  final AdminSyncSummary syncSummary;
}

class AdminCompanySummary {
  const AdminCompanySummary({
    required this.id,
    required this.name,
    required this.legalName,
    required this.documentNumber,
    required this.slug,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.license,
    required this.counts,
  });

  final String id;
  final String name;
  final String legalName;
  final String? documentNumber;
  final String slug;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final AdminLicenseSnapshot? license;
  final AdminEntityCounts counts;

  int get remoteRecordCount => counts.totalRemoteRecords;

  factory AdminCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminCompanySummary(
      id: _readString(map, 'id'),
      name: _readString(map, 'name'),
      legalName: _readString(map, 'legalName', fallback: _readString(map, 'name')),
      documentNumber: _readOptionalString(map, 'documentNumber'),
      slug: _readString(map, 'slug'),
      isActive: map['isActive'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      license: map['license'] is Map<String, dynamic>
          ? AdminLicenseSnapshot.fromMap(map['license'] as Map<String, dynamic>)
          : null,
      counts: AdminEntityCounts.fromMap(
        map['counts'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

class AdminCompanyDetail {
  const AdminCompanyDetail({
    required this.company,
    required this.memberships,
    required this.sessions,
  });

  final AdminCompanySummary company;
  final List<AdminMembershipSummary> memberships;
  final List<AdminDeviceSession> sessions;

  factory AdminCompanyDetail.fromMap(Map<String, dynamic> map) {
    return AdminCompanyDetail(
      company: AdminCompanySummary.fromMap(_readMap(map, 'company')),
      memberships: (map['memberships'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminMembershipSummary.fromMap)
          .toList(),
      sessions: (map['sessions'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminDeviceSession.fromMap)
          .toList(),
    );
  }
}

class AdminDeviceSession {
  const AdminDeviceSession({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.companyId,
    required this.companyName,
    required this.membershipId,
    required this.membershipRole,
    required this.clientType,
    required this.clientInstanceId,
    required this.deviceLabel,
    required this.platform,
    required this.appVersion,
    required this.status,
    required this.createdAt,
    required this.lastSeenAt,
    required this.lastRefreshedAt,
    required this.refreshTokenExpiresAt,
    required this.revokedAt,
    required this.revokedReason,
  });

  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String companyId;
  final String companyName;
  final String membershipId;
  final String membershipRole;
  final String clientType;
  final String clientInstanceId;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? lastRefreshedAt;
  final DateTime? refreshTokenExpiresAt;
  final DateTime? revokedAt;
  final String? revokedReason;

  factory AdminDeviceSession.fromMap(Map<String, dynamic> map) {
    return AdminDeviceSession(
      id: _readString(map, 'id'),
      userId: _readString(map, 'userId'),
      userName: _readString(map, 'userName'),
      userEmail: _readString(map, 'userEmail'),
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      membershipId: _readString(map, 'membershipId'),
      membershipRole: _readString(map, 'membershipRole'),
      clientType: _readString(map, 'clientType'),
      clientInstanceId: _readString(map, 'clientInstanceId'),
      deviceLabel: _readOptionalString(map, 'deviceLabel'),
      platform: _readOptionalString(map, 'platform'),
      appVersion: _readOptionalString(map, 'appVersion'),
      status: _readString(map, 'status'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      lastSeenAt: _readOptionalDateTime(map, 'lastSeenAt'),
      lastRefreshedAt: _readOptionalDateTime(map, 'lastRefreshedAt'),
      refreshTokenExpiresAt: _readOptionalDateTime(map, 'refreshTokenExpiresAt'),
      revokedAt: _readOptionalDateTime(map, 'revokedAt'),
      revokedReason: _readOptionalString(map, 'revokedReason'),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'companyId': companyId,
      'companyName': companyName,
      'membershipId': membershipId,
      'membershipRole': membershipRole,
      'clientType': clientType,
      'clientInstanceId': clientInstanceId,
      'deviceLabel': deviceLabel,
      'platform': platform,
      'appVersion': appVersion,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'lastSeenAt': lastSeenAt?.toIso8601String(),
      'lastRefreshedAt': lastRefreshedAt?.toIso8601String(),
      'refreshTokenExpiresAt': refreshTokenExpiresAt?.toIso8601String(),
      'revokedAt': revokedAt?.toIso8601String(),
      'revokedReason': revokedReason,
    };
  }
}

class AdminMembershipSummary {
  const AdminMembershipSummary({
    required this.id,
    required this.role,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userIsActive,
    required this.userIsPlatformAdmin,
  });

  final String id;
  final String role;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String userId;
  final String userName;
  final String userEmail;
  final bool userIsActive;
  final bool userIsPlatformAdmin;

  factory AdminMembershipSummary.fromMap(Map<String, dynamic> map) {
    final user = _readMap(map, 'user');
    return AdminMembershipSummary(
      id: _readString(map, 'id'),
      role: _readString(map, 'role'),
      isDefault: map['isDefault'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      userId: _readString(user, 'id'),
      userName: _readString(user, 'name', fallback: 'Usuario'),
      userEmail: _readString(user, 'email', fallback: 'sem e-mail'),
      userIsActive: user['isActive'] == true,
      userIsPlatformAdmin: user['isPlatformAdmin'] == true,
    );
  }
}

class AdminLicenseSnapshot {
  const AdminLicenseSnapshot({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.companyLegalName,
    required this.companySlug,
    required this.companyIsActive,
    required this.plan,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.maxDevices,
    required this.syncEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String companyLegalName;
  final String companySlug;
  final bool companyIsActive;
  final String plan;
  final String status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? maxDevices;
  final bool syncEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminLicenseSnapshot.fromMap(
    Map<String, dynamic> map, {
    String? companyIdFallback,
    String? companyNameFallback,
    String? companyLegalNameFallback,
    String? companySlugFallback,
    bool companyIsActiveFallback = false,
  }) {
    return AdminLicenseSnapshot(
      id: _readString(map, 'id'),
      companyId: _readString(
        map,
        'companyId',
        fallback: companyIdFallback ?? '',
      ),
      companyName: _readString(
        map,
        'companyName',
        fallback: companyNameFallback ?? '',
      ),
      companyLegalName: _readString(
        map,
        'companyLegalName',
        fallback: companyLegalNameFallback ?? companyNameFallback ?? '',
      ),
      companySlug: _readString(
        map,
        'companySlug',
        fallback: companySlugFallback ?? '',
      ),
      companyIsActive: map['companyIsActive'] == true || companyIsActiveFallback,
      plan: _readString(map, 'plan'),
      status: _readString(map, 'status').toLowerCase(),
      startsAt: _readOptionalDateTime(map, 'startsAt'),
      expiresAt: _readOptionalDateTime(map, 'expiresAt'),
      maxDevices: _readOptionalInt(map, 'maxDevices'),
      syncEnabled: map['syncEnabled'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
    );
  }

  Map<String, dynamic> toStorageMap() {
    return <String, dynamic>{
      'id': id,
      'companyId': companyId,
      'companyName': companyName,
      'companyLegalName': companyLegalName,
      'companySlug': companySlug,
      'companyIsActive': companyIsActive,
      'plan': plan,
      'status': status,
      'startsAt': startsAt?.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'maxDevices': maxDevices,
      'syncEnabled': syncEnabled,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class AdminEntityCounts {
  const AdminEntityCounts({
    required this.memberships,
    required this.categories,
    required this.products,
    required this.customers,
    required this.suppliers,
    required this.purchases,
    required this.sales,
    required this.financialEvents,
    required this.cashEvents,
  });

  final int memberships;
  final int categories;
  final int products;
  final int customers;
  final int suppliers;
  final int purchases;
  final int sales;
  final int financialEvents;
  final int cashEvents;

  int get totalRemoteRecords =>
      categories +
      products +
      customers +
      suppliers +
      purchases +
      sales +
      financialEvents +
      cashEvents;

  factory AdminEntityCounts.fromMap(Map<String, dynamic> map) {
    return AdminEntityCounts(
      memberships: _readOptionalInt(map, 'memberships') ?? 0,
      categories: _readOptionalInt(map, 'categories') ?? 0,
      products: _readOptionalInt(map, 'products') ?? 0,
      customers: _readOptionalInt(map, 'customers') ?? 0,
      suppliers: _readOptionalInt(map, 'suppliers') ?? 0,
      purchases: _readOptionalInt(map, 'purchases') ?? 0,
      sales: _readOptionalInt(map, 'sales') ?? 0,
      financialEvents: _readOptionalInt(map, 'financialEvents') ?? 0,
      cashEvents: _readOptionalInt(map, 'cashEvents') ?? 0,
    );
  }
}

class AdminAuditSummary {
  const AdminAuditSummary({
    required this.totalEvents,
    required this.countsByAction,
    required this.recentEvents,
  });

  final int totalEvents;
  final Map<String, int> countsByAction;
  final List<AdminAuditEvent> recentEvents;

  factory AdminAuditSummary.fromMap(Map<String, dynamic> map) {
    return AdminAuditSummary(
      totalEvents: _readOptionalInt(map, 'totalEvents') ?? 0,
      countsByAction: {
        for (final entry
            in (map['countsByAction'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>())
          _readString(entry, 'action'): _readOptionalInt(entry, 'count') ?? 0,
      },
      recentEvents: (map['recentEvents'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminAuditEvent.fromMap)
          .toList(),
    );
  }
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.actorUserName,
    required this.actorUserEmail,
    required this.targetCompanyName,
    required this.details,
  });

  final String id;
  final String action;
  final DateTime? createdAt;
  final String actorUserName;
  final String actorUserEmail;
  final String? targetCompanyName;
  final Map<String, dynamic> details;

  factory AdminAuditEvent.fromMap(Map<String, dynamic> map) {
    final actor =
        map['actorUser'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final targetCompany = map['targetCompany'] as Map<String, dynamic>?;
    return AdminAuditEvent(
      id: _readString(map, 'id'),
      action: _readString(map, 'action'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      actorUserName: _readString(actor, 'name', fallback: 'Administrador'),
      actorUserEmail: _readString(actor, 'email', fallback: 'sem e-mail'),
      targetCompanyName: targetCompany == null
          ? null
          : _readOptionalString(targetCompany, 'name'),
      details:
          map['details'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }
}

class AdminSyncSummary {
  const AdminSyncSummary({
    required this.totalCompanies,
    required this.syncEnabledCompanies,
    required this.licenseStatusCounts,
    required this.companySummaries,
  });

  final int totalCompanies;
  final int syncEnabledCompanies;
  final Map<String, int> licenseStatusCounts;
  final List<AdminSyncCompanySummary> companySummaries;

  factory AdminSyncSummary.fromMap(Map<String, dynamic> map) {
    final overview =
        map['overview'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminSyncSummary(
      totalCompanies: _readOptionalInt(overview, 'totalCompanies') ?? 0,
      syncEnabledCompanies:
          _readOptionalInt(overview, 'syncEnabledCompanies') ?? 0,
      licenseStatusCounts: {
        for (final entry
            in (overview['licenseStatusCounts'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .entries)
          entry.key: _normalizeToInt(entry.value),
      },
      companySummaries:
          (map['companies'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(AdminSyncCompanySummary.fromMap)
              .toList(),
    );
  }
}

class AdminSyncCompanySummary {
  const AdminSyncCompanySummary({
    required this.companyId,
    required this.companyName,
    required this.companySlug,
    required this.licenseStatus,
    required this.licensePlan,
    required this.syncEnabled,
    required this.remoteRecordCount,
    required this.entityCounts,
  });

  final String companyId;
  final String companyName;
  final String companySlug;
  final String? licenseStatus;
  final String? licensePlan;
  final bool syncEnabled;
  final int remoteRecordCount;
  final AdminEntityCounts entityCounts;

  factory AdminSyncCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminSyncCompanySummary(
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      companySlug: _readString(map, 'companySlug'),
      licenseStatus: _readOptionalString(map, 'licenseStatus'),
      licensePlan: _readOptionalString(map, 'licensePlan'),
      syncEnabled: map['syncEnabled'] == true,
      remoteRecordCount: _readOptionalInt(map, 'remoteRecordCount') ?? 0,
      entityCounts: AdminEntityCounts.fromMap(
        map['entityCounts'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Campo "$key" ausente no payload administrativo.');
}

String _readString(Map<String, dynamic> map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (fallback != null) {
    return fallback;
  }
  throw FormatException('Campo "$key" ausente no payload administrativo.');
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
  if (value == null) {
    return null;
  }
  return _normalizeToInt(value);
}

int _normalizeToInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  if (rawValue is num) {
    return rawValue.toInt();
  }
  if (rawValue is String && rawValue.trim().isNotEmpty) {
    return int.tryParse(rawValue.trim()) ?? 0;
  }
  return 0;
}
