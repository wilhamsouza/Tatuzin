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
    return <String, dynamic>{'id': id, 'role': role, 'isDefault': isDefault};
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

class AdminSortMeta {
  const AdminSortMeta({required this.by, required this.direction});

  final String by;
  final String direction;

  factory AdminSortMeta.fromMap(Map<String, dynamic> map) {
    return AdminSortMeta(
      by: _readString(map, 'by'),
      direction: _readString(map, 'direction'),
    );
  }

  static AdminSortMeta? fromPayload(Map<String, dynamic> map) {
    final nestedSort = map['sort'];
    if (nestedSort is Map<String, dynamic>) {
      return AdminSortMeta.fromMap(nestedSort);
    }
    return null;
  }
}

class AdminPaginationMeta {
  const AdminPaginationMeta({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory AdminPaginationMeta.fromMap(Map<String, dynamic> map) {
    return AdminPaginationMeta(
      page: _readOptionalInt(map, 'page') ?? 1,
      pageSize: _readOptionalInt(map, 'pageSize') ?? 20,
      total: _readOptionalInt(map, 'total') ?? 0,
      count: _readOptionalInt(map, 'count') ?? 0,
      hasNext: map['hasNext'] == true,
      hasPrevious: map['hasPrevious'] == true,
    );
  }

  factory AdminPaginationMeta.fromPayload(Map<String, dynamic> map) {
    final nestedPagination = map['pagination'];
    if (nestedPagination is Map<String, dynamic>) {
      return AdminPaginationMeta.fromMap(nestedPagination);
    }
    throw const FormatException(
      'Campo "pagination" ausente no payload administrativo.',
    );
  }
}

class AdminPaginatedResult<T> {
  const AdminPaginatedResult({
    required this.items,
    required this.pagination,
    required this.filters,
    required this.sort,
  });

  final List<T> items;
  final AdminPaginationMeta pagination;
  final Map<String, dynamic> filters;
  final AdminSortMeta? sort;
}

class AdminCompaniesQuery {
  const AdminCompaniesQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.isActive,
    this.licenseStatus,
    this.syncEnabled,
    this.sortBy,
    this.sortDirection,
  });

  final int page;
  final int pageSize;
  final String? search;
  final bool? isActive;
  final String? licenseStatus;
  final bool? syncEnabled;
  final String? sortBy;
  final String? sortDirection;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(search) case final value?) 'search': value,
      if (isActive != null) 'isActive': '$isActive',
      if (_normalized(licenseStatus) case final value?) 'licenseStatus': value,
      if (syncEnabled != null) 'syncEnabled': '$syncEnabled',
      if (_normalized(sortBy) case final value?) 'sortBy': value,
      if (_normalized(sortDirection) case final value?) 'sortDirection': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminCompaniesQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.isActive == isActive &&
        other.licenseStatus == licenseStatus &&
        other.syncEnabled == syncEnabled &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection;
  }

  @override
  int get hashCode => Object.hash(
    page,
    pageSize,
    search,
    isActive,
    licenseStatus,
    syncEnabled,
    sortBy,
    sortDirection,
  );
}

class AdminLicensesQuery {
  const AdminLicensesQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.status,
    this.syncEnabled,
    this.sortBy,
    this.sortDirection,
  });

  final int page;
  final int pageSize;
  final String? search;
  final String? status;
  final bool? syncEnabled;
  final String? sortBy;
  final String? sortDirection;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(search) case final value?) 'search': value,
      if (_normalized(status) case final value?) 'status': value,
      if (syncEnabled != null) 'syncEnabled': '$syncEnabled',
      if (_normalized(sortBy) case final value?) 'sortBy': value,
      if (_normalized(sortDirection) case final value?) 'sortDirection': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminLicensesQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.status == status &&
        other.syncEnabled == syncEnabled &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection;
  }

  @override
  int get hashCode => Object.hash(
    page,
    pageSize,
    search,
    status,
    syncEnabled,
    sortBy,
    sortDirection,
  );
}

class AdminAuditQuery {
  const AdminAuditQuery({
    this.page = 1,
    this.pageSize = 20,
    this.action,
    this.actorUserId,
    this.companyId,
  });

  final int page;
  final int pageSize;
  final String? action;
  final String? actorUserId;
  final String? companyId;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(action) case final value?) 'action': value,
      if (_normalized(actorUserId) case final value?) 'actorUserId': value,
      if (_normalized(companyId) case final value?) 'companyId': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminAuditQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.action == action &&
        other.actorUserId == actorUserId &&
        other.companyId == companyId;
  }

  @override
  int get hashCode =>
      Object.hash(page, pageSize, action, actorUserId, companyId);
}

class AdminSyncQuery {
  const AdminSyncQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.licenseStatus,
    this.syncEnabled,
    this.sortBy,
    this.sortDirection,
  });

  final int page;
  final int pageSize;
  final String? search;
  final String? licenseStatus;
  final bool? syncEnabled;
  final String? sortBy;
  final String? sortDirection;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(search) case final value?) 'search': value,
      if (_normalized(licenseStatus) case final value?) 'licenseStatus': value,
      if (syncEnabled != null) 'syncEnabled': '$syncEnabled',
      if (_normalized(sortBy) case final value?) 'sortBy': value,
      if (_normalized(sortDirection) case final value?) 'sortDirection': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminSyncQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.licenseStatus == licenseStatus &&
        other.syncEnabled == syncEnabled &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection;
  }

  @override
  int get hashCode => Object.hash(
    page,
    pageSize,
    search,
    licenseStatus,
    syncEnabled,
    sortBy,
    sortDirection,
  );
}

class AdminSyncOperationalQuery {
  const AdminSyncOperationalQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.licenseStatus,
    this.syncEnabled,
    this.sortBy,
    this.sortDirection,
  });

  final int page;
  final int pageSize;
  final String? search;
  final String? licenseStatus;
  final bool? syncEnabled;
  final String? sortBy;
  final String? sortDirection;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(search) case final value?) 'search': value,
      if (_normalized(licenseStatus) case final value?) 'licenseStatus': value,
      if (syncEnabled != null) 'syncEnabled': '$syncEnabled',
      if (_normalized(sortBy) case final value?) 'sortBy': value,
      if (_normalized(sortDirection) case final value?) 'sortDirection': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminSyncOperationalQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.licenseStatus == licenseStatus &&
        other.syncEnabled == syncEnabled &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection;
  }

  @override
  int get hashCode => Object.hash(
    page,
    pageSize,
    search,
    licenseStatus,
    syncEnabled,
    sortBy,
    sortDirection,
  );
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
      legalName: _readString(
        map,
        'legalName',
        fallback: _readString(map, 'name'),
      ),
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
      refreshTokenExpiresAt: _readOptionalDateTime(
        map,
        'refreshTokenExpiresAt',
      ),
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
      companyIsActive:
          map['companyIsActive'] == true || companyIsActiveFallback,
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
    required this.pagination,
    required this.filters,
    required this.sort,
  });

  final int totalEvents;
  final Map<String, int> countsByAction;
  final List<AdminAuditEvent> recentEvents;
  final AdminPaginationMeta pagination;
  final Map<String, dynamic> filters;
  final AdminSortMeta? sort;

  factory AdminAuditSummary.fromMap(Map<String, dynamic> map) {
    final overview = _readOverviewPayload(map);
    return AdminAuditSummary(
      totalEvents: _readOptionalInt(overview, 'totalEvents') ?? 0,
      countsByAction: _countsByActionFromObject(overview['countsByAction']),
      recentEvents: _readAdminItemMaps(
        map,
      ).map(AdminAuditEvent.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(map),
      filters: _readFiltersPayload(map),
      sort: AdminSortMeta.fromPayload(map),
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
    required this.pagination,
    required this.filters,
    required this.sort,
  });

  final int totalCompanies;
  final int syncEnabledCompanies;
  final Map<String, int> licenseStatusCounts;
  final List<AdminSyncCompanySummary> companySummaries;
  final AdminPaginationMeta pagination;
  final Map<String, dynamic> filters;
  final AdminSortMeta? sort;

  factory AdminSyncSummary.fromMap(Map<String, dynamic> map) {
    final overview = _readOverviewPayload(map);
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
      companySummaries: _readAdminItemMaps(
        map,
      ).map(AdminSyncCompanySummary.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(map),
      filters: _readFiltersPayload(map),
      sort: AdminSortMeta.fromPayload(map),
    );
  }
}

class AdminSyncOperationalSummary {
  const AdminSyncOperationalSummary({
    required this.overview,
    required this.capabilities,
    required this.companies,
    required this.pagination,
    required this.filters,
    required this.sort,
  });

  final AdminSyncOperationalOverview overview;
  final AdminSyncOperationalCapabilities capabilities;
  final List<AdminSyncOperationalCompanySummary> companies;
  final AdminPaginationMeta pagination;
  final Map<String, dynamic> filters;
  final AdminSortMeta? sort;

  factory AdminSyncOperationalSummary.fromMap(Map<String, dynamic> map) {
    return AdminSyncOperationalSummary(
      overview: AdminSyncOperationalOverview.fromMap(_readOverviewPayload(map)),
      capabilities: AdminSyncOperationalCapabilities.fromMap(
        map['capabilities'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      companies: _readAdminItemMaps(
        map,
      ).map(AdminSyncOperationalCompanySummary.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(map),
      filters: _readFiltersPayload(map),
      sort: AdminSortMeta.fromPayload(map),
    );
  }
}

class AdminSyncOperationalOverview {
  const AdminSyncOperationalOverview({
    required this.totalCompanies,
    required this.statusCounts,
    required this.telemetryLevelCounts,
  });

  final int totalCompanies;
  final Map<String, int> statusCounts;
  final Map<String, int> telemetryLevelCounts;

  factory AdminSyncOperationalOverview.fromMap(Map<String, dynamic> map) {
    return AdminSyncOperationalOverview(
      totalCompanies: _readOptionalInt(map, 'totalCompanies') ?? 0,
      statusCounts: _readIntMap(map, 'statusCounts'),
      telemetryLevelCounts: _readIntMap(map, 'telemetryLevelCounts'),
    );
  }
}

class AdminSyncOperationalCapabilities {
  const AdminSyncOperationalCapabilities({
    required this.observedSignals,
    required this.unavailableSignals,
    required this.observedFeatureKeys,
    required this.telemetryGaps,
    required this.notes,
  });

  final List<String> observedSignals;
  final List<String> unavailableSignals;
  final List<String> observedFeatureKeys;
  final List<AdminTelemetryGap> telemetryGaps;
  final List<String> notes;

  factory AdminSyncOperationalCapabilities.fromMap(Map<String, dynamic> map) {
    return AdminSyncOperationalCapabilities(
      observedSignals: _readStringList(map['observedSignals']),
      unavailableSignals: _readStringList(map['unavailableSignals']),
      observedFeatureKeys: _readStringList(map['observedFeatureKeys']),
      telemetryGaps:
          (map['telemetryGaps'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(AdminTelemetryGap.fromMap)
              .toList(),
      notes: _readStringList(map['notes']),
    );
  }
}

class AdminTelemetryGap {
  const AdminTelemetryGap({
    required this.featureKey,
    required this.gapType,
    required this.reason,
  });

  final String featureKey;
  final String gapType;
  final String reason;

  factory AdminTelemetryGap.fromMap(Map<String, dynamic> map) {
    return AdminTelemetryGap(
      featureKey: _readString(map, 'featureKey'),
      gapType: _readString(map, 'gapType'),
      reason: _readString(map, 'reason'),
    );
  }
}

class AdminSyncOperationalCompanySummary {
  const AdminSyncOperationalCompanySummary({
    required this.companyId,
    required this.companyName,
    required this.companySlug,
    required this.companyIsActive,
    required this.licenseStatus,
    required this.syncEnabled,
    required this.activeSessionsCount,
    required this.activeMobileSessionsCount,
    required this.lastSessionSeenAt,
    required this.observedRemoteRecordCount,
    required this.lastObservedRemoteChangeAt,
    required this.remoteCoverage,
    required this.status,
    required this.statusSource,
    required this.statusReason,
    required this.telemetryAvailability,
    required this.observedFeatures,
  });

  final String companyId;
  final String companyName;
  final String companySlug;
  final bool companyIsActive;
  final String licenseStatus;
  final bool syncEnabled;
  final int activeSessionsCount;
  final int activeMobileSessionsCount;
  final DateTime? lastSessionSeenAt;
  final int observedRemoteRecordCount;
  final DateTime? lastObservedRemoteChangeAt;
  final AdminRemoteCoverage remoteCoverage;
  final String status;
  final String statusSource;
  final String statusReason;
  final AdminTelemetryAvailability telemetryAvailability;
  final List<AdminObservedFeature> observedFeatures;

  factory AdminSyncOperationalCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminSyncOperationalCompanySummary(
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      companySlug: _readString(map, 'companySlug'),
      companyIsActive: map['companyIsActive'] == true,
      licenseStatus: _readString(map, 'licenseStatus'),
      syncEnabled: map['syncEnabled'] == true,
      activeSessionsCount: _readOptionalInt(map, 'activeSessionsCount') ?? 0,
      activeMobileSessionsCount:
          _readOptionalInt(map, 'activeMobileSessionsCount') ?? 0,
      lastSessionSeenAt: _readOptionalDateTime(map, 'lastSessionSeenAt'),
      observedRemoteRecordCount:
          _readOptionalInt(map, 'observedRemoteRecordCount') ?? 0,
      lastObservedRemoteChangeAt: _readOptionalDateTime(
        map,
        'lastObservedRemoteChangeAt',
      ),
      remoteCoverage: AdminRemoteCoverage.fromMap(
        map['remoteCoverage'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      status: _readString(map, 'status'),
      statusSource: _readString(map, 'statusSource'),
      statusReason: _readString(map, 'statusReason'),
      telemetryAvailability: AdminTelemetryAvailability.fromMap(
        map['telemetryAvailability'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      observedFeatures:
          (map['observedFeatures'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(AdminObservedFeature.fromMap)
              .toList(),
    );
  }
}

class AdminRemoteCoverage {
  const AdminRemoteCoverage({
    required this.observedFeatureCount,
    required this.featuresWithRemoteRecords,
    required this.telemetryScope,
  });

  final int observedFeatureCount;
  final int featuresWithRemoteRecords;
  final String telemetryScope;

  factory AdminRemoteCoverage.fromMap(Map<String, dynamic> map) {
    return AdminRemoteCoverage(
      observedFeatureCount: _readOptionalInt(map, 'observedFeatureCount') ?? 0,
      featuresWithRemoteRecords:
          _readOptionalInt(map, 'featuresWithRemoteRecords') ?? 0,
      telemetryScope: _readString(
        map,
        'telemetryScope',
        fallback: 'partial_remote_mirror',
      ),
    );
  }
}

class AdminTelemetryAvailability {
  const AdminTelemetryAvailability({
    required this.level,
    required this.hasDeviceSessionSignals,
    required this.hasRemoteMirrorSignals,
    required this.hasLocalQueueSignals,
    required this.hasConflictSignals,
    required this.hasRetrySignals,
    required this.hasClientRepairSignals,
  });

  final String level;
  final bool hasDeviceSessionSignals;
  final bool hasRemoteMirrorSignals;
  final bool hasLocalQueueSignals;
  final bool hasConflictSignals;
  final bool hasRetrySignals;
  final bool hasClientRepairSignals;

  factory AdminTelemetryAvailability.fromMap(Map<String, dynamic> map) {
    return AdminTelemetryAvailability(
      level: _readString(map, 'level', fallback: 'limited'),
      hasDeviceSessionSignals: map['hasDeviceSessionSignals'] == true,
      hasRemoteMirrorSignals: map['hasRemoteMirrorSignals'] == true,
      hasLocalQueueSignals: map['hasLocalQueueSignals'] == true,
      hasConflictSignals: map['hasConflictSignals'] == true,
      hasRetrySignals: map['hasRetrySignals'] == true,
      hasClientRepairSignals: map['hasClientRepairSignals'] == true,
    );
  }
}

class AdminObservedFeature {
  const AdminObservedFeature({
    required this.featureKey,
    required this.displayName,
    required this.remoteRecordCount,
    required this.lastObservedRemoteChangeAt,
    required this.observationKind,
  });

  final String featureKey;
  final String displayName;
  final int remoteRecordCount;
  final DateTime? lastObservedRemoteChangeAt;
  final String observationKind;

  factory AdminObservedFeature.fromMap(Map<String, dynamic> map) {
    return AdminObservedFeature(
      featureKey: _readString(map, 'featureKey'),
      displayName: _readString(map, 'displayName'),
      remoteRecordCount: _readOptionalInt(map, 'remoteRecordCount') ?? 0,
      lastObservedRemoteChangeAt: _readOptionalDateTime(
        map,
        'lastObservedRemoteChangeAt',
      ),
      observationKind: _readString(map, 'observationKind'),
    );
  }
}

List<Map<String, dynamic>> readAdminItems(Map<String, dynamic> map) {
  return _readAdminItemMaps(map);
}

Map<String, dynamic> readAdminFilters(Map<String, dynamic> map) {
  return _readFiltersPayload(map);
}

String? _normalized(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
        map['entityCounts'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
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

Map<String, int> _readIntMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! Map<String, dynamic>) {
    return const <String, int>{};
  }

  return <String, int>{
    for (final entry in value.entries) entry.key: _normalizeToInt(entry.value),
  };
}

List<String> _readStringList(Object? rawValue) {
  if (rawValue is! List<dynamic>) {
    return const <String>[];
  }

  return rawValue
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic> _readOverviewPayload(Map<String, dynamic> map) {
  final overview = map['overview'];
  if (overview is Map<String, dynamic>) {
    return overview;
  }
  return const <String, dynamic>{};
}

Map<String, dynamic> _readFiltersPayload(Map<String, dynamic> map) {
  final filters = map['filters'];
  if (filters is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(filters);
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _readAdminItemMaps(Map<String, dynamic> map) {
  final primaryItems = map['items'];
  if (primaryItems is List<dynamic>) {
    return primaryItems.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
  }
  return const <Map<String, dynamic>>[];
}

Map<String, int> _countsByActionFromObject(Object? rawValue) {
  if (rawValue is List<dynamic>) {
    return <String, int>{
      for (final entry in rawValue.whereType<Map<String, dynamic>>())
        _readString(entry, 'action'): _readOptionalInt(entry, 'count') ?? 0,
    };
  }

  if (rawValue is Map<String, dynamic>) {
    return <String, int>{
      for (final entry in rawValue.entries)
        entry.key: _normalizeToInt(entry.value),
    };
  }

  return const <String, int>{};
}
