class OwnerApiException implements Exception {
  const OwnerApiException({required this.message, this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

class OwnerSession {
  const OwnerSession({
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
  final OwnerUser user;
  final OwnerCompanyContext company;
  final OwnerMembershipContext membership;
  final OwnerDeviceSession? activeSession;

  factory OwnerSession.fromLoginResponse(Map<String, dynamic> map) {
    return OwnerSession(
      accessToken: _readString(map, 'accessToken'),
      refreshToken: _readOptionalString(map, 'refreshToken'),
      tokenType: _readString(map, 'tokenType', fallback: 'Bearer'),
      user: OwnerUser.fromMap(_readMap(map, 'user')),
      company: OwnerCompanyContext.fromMap(_readMap(map, 'company')),
      membership: OwnerMembershipContext.fromMap(_readMap(map, 'membership')),
      activeSession: map['session'] is Map<String, dynamic>
          ? OwnerDeviceSession.fromMap(map['session'] as Map<String, dynamic>)
          : null,
    );
  }

  factory OwnerSession.fromIdentityResponse(
    Map<String, dynamic> map, {
    required String accessToken,
  }) {
    return OwnerSession(
      accessToken: accessToken,
      refreshToken: null,
      tokenType: 'Bearer',
      user: OwnerUser.fromMap(_readMap(map, 'user')),
      company: OwnerCompanyContext.fromMap(_readMap(map, 'company')),
      membership: OwnerMembershipContext.fromMap(_readMap(map, 'membership')),
      activeSession: map['session'] is Map<String, dynamic>
          ? OwnerDeviceSession.fromMap(map['session'] as Map<String, dynamic>)
          : null,
    );
  }

  factory OwnerSession.fromStorageMap(
    Map<String, dynamic> map, {
    required String accessToken,
    String? refreshToken,
  }) {
    return OwnerSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: _readString(map, 'tokenType', fallback: 'Bearer'),
      user: OwnerUser.fromMap(_readMap(map, 'user')),
      company: OwnerCompanyContext.fromMap(_readMap(map, 'company')),
      membership: OwnerMembershipContext.fromMap(_readMap(map, 'membership')),
      activeSession: map['session'] is Map<String, dynamic>
          ? OwnerDeviceSession.fromMap(map['session'] as Map<String, dynamic>)
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
}

class OwnerUser {
  const OwnerUser({
    required this.id,
    required this.email,
    required this.name,
    required this.isPlatformAdmin,
  });

  final String id;
  final String email;
  final String name;
  final bool isPlatformAdmin;

  factory OwnerUser.fromMap(Map<String, dynamic> map) {
    return OwnerUser(
      id: _readString(map, 'id'),
      email: _readString(map, 'email'),
      name: _readString(map, 'name', fallback: 'Dono'),
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

class OwnerCompanyContext {
  const OwnerCompanyContext({
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
  final OwnerLicenseSnapshot? license;

  factory OwnerCompanyContext.fromMap(Map<String, dynamic> map) {
    final id = _readString(map, 'id');
    final name = _readString(map, 'name', fallback: 'Empresa');
    final legalName = _readString(map, 'legalName', fallback: name);
    return OwnerCompanyContext(
      id: id,
      name: name,
      legalName: legalName,
      documentNumber: _readOptionalString(map, 'documentNumber'),
      slug: _readString(map, 'slug', fallback: id),
      license: map['license'] is Map<String, dynamic>
          ? OwnerLicenseSnapshot.fromMap(map['license'] as Map<String, dynamic>)
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
      if (license != null) 'license': license!.toMap(),
    };
  }
}

class OwnerMembershipContext {
  const OwnerMembershipContext({
    required this.id,
    required this.role,
    required this.isDefault,
  });

  final String id;
  final String role;
  final bool isDefault;

  factory OwnerMembershipContext.fromMap(Map<String, dynamic> map) {
    return OwnerMembershipContext(
      id: _readString(map, 'id'),
      role: _readString(map, 'role', fallback: 'UNKNOWN'),
      isDefault: map['isDefault'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'id': id, 'role': role, 'isDefault': isDefault};
  }
}

class OwnerDeviceSession {
  const OwnerDeviceSession({required this.id});

  final String id;

  factory OwnerDeviceSession.fromMap(Map<String, dynamic> map) {
    return OwnerDeviceSession(id: _readString(map, 'id'));
  }

  Map<String, dynamic> toMap() => <String, dynamic>{'id': id};
}

class OwnerLicenseSnapshot {
  const OwnerLicenseSnapshot({
    required this.id,
    required this.plan,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.maxDevices,
    required this.syncEnabled,
  });

  final String id;
  final String plan;
  final String status;
  final String? startsAt;
  final String? expiresAt;
  final int maxDevices;
  final bool syncEnabled;

  factory OwnerLicenseSnapshot.fromMap(Map<String, dynamic> map) {
    return OwnerLicenseSnapshot(
      id: _readString(map, 'id'),
      plan: _readString(map, 'plan', fallback: 'FREE'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      startsAt: _readOptionalString(map, 'startsAt'),
      expiresAt: _readOptionalString(map, 'expiresAt'),
      maxDevices: _readOptionalInt(map, 'maxDevices') ?? 1,
      syncEnabled: map['syncEnabled'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'plan': plan,
      'status': status,
      'startsAt': startsAt,
      'expiresAt': expiresAt,
      'maxDevices': maxDevices,
      'syncEnabled': syncEnabled,
    };
  }
}

class OwnerCompanySummary {
  const OwnerCompanySummary({
    required this.companyId,
    required this.name,
    required this.setupCompleted,
    required this.createdAt,
    required this.membershipRole,
    required this.license,
    required this.limits,
    required this.features,
  });

  final String companyId;
  final String name;
  final bool setupCompleted;
  final String? createdAt;
  final String membershipRole;
  final OwnerLicenseSummary license;
  final OwnerLimits limits;
  final Map<String, bool> features;

  factory OwnerCompanySummary.fromMap(Map<String, dynamic> map) {
    return OwnerCompanySummary(
      companyId: _readString(map, 'companyId'),
      name: _readString(map, 'name', fallback: 'Empresa'),
      setupCompleted: map['setupCompleted'] == true,
      createdAt: _readOptionalString(map, 'createdAt'),
      membershipRole: _readString(_readMap(map, 'membership'), 'role'),
      license: OwnerLicenseSummary.fromMap(_readMap(map, 'license')),
      limits: OwnerLimits.fromMap(_readMap(map, 'limits')),
      features: _readBoolMap(map['features']),
    );
  }
}

class OwnerLicenseSummary {
  const OwnerLicenseSummary({
    required this.plan,
    required this.rawPlan,
    required this.status,
    required this.currentPeriodEnd,
    required this.nextPaymentDate,
    required this.cancelAtPeriodEnd,
    required this.pendingPlan,
    required this.billingSubscriptionStatus,
  });

  final String plan;
  final String? rawPlan;
  final String? status;
  final String? currentPeriodEnd;
  final String? nextPaymentDate;
  final bool cancelAtPeriodEnd;
  final String? pendingPlan;
  final String? billingSubscriptionStatus;

  factory OwnerLicenseSummary.fromMap(Map<String, dynamic> map) {
    return OwnerLicenseSummary(
      plan: _readString(map, 'plan', fallback: 'FREE'),
      rawPlan: _readOptionalString(map, 'rawPlan'),
      status: _readOptionalString(map, 'status'),
      currentPeriodEnd: _readOptionalString(map, 'currentPeriodEnd'),
      nextPaymentDate: _readOptionalString(map, 'nextPaymentDate'),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
      billingSubscriptionStatus: _readOptionalString(
        map,
        'billingSubscriptionStatus',
      ),
    );
  }
}

class OwnerLimits {
  const OwnerLimits({
    required this.maxDevices,
    required this.maxEmployees,
    required this.reportPeriods,
  });

  final int maxDevices;
  final int maxEmployees;
  final List<String> reportPeriods;

  factory OwnerLimits.fromMap(Map<String, dynamic> map) {
    return OwnerLimits(
      maxDevices: _readOptionalInt(map, 'maxDevices') ?? 1,
      maxEmployees: _readOptionalInt(map, 'maxEmployees') ?? 0,
      reportPeriods: _readStringList(map['reportPeriods']),
    );
  }
}

class OwnerBillingStatus {
  const OwnerBillingStatus({
    required this.companyId,
    required this.plan,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.expiresAt,
    required this.provider,
    required this.hasProviderSubscription,
    required this.maskedProviderSubscriptionId,
    required this.nextPaymentDate,
    required this.cancelAtPeriodEnd,
    required this.cancelRequestedAt,
    required this.canceledAt,
    required this.pendingPlan,
    required this.pendingPlanRequestedAt,
    required this.billingSubscriptionStatus,
    required this.limits,
    required this.features,
  });

  final String companyId;
  final String plan;
  final String status;
  final String? currentPeriodStart;
  final String? currentPeriodEnd;
  final String? expiresAt;
  final String? provider;
  final bool hasProviderSubscription;
  final String? maskedProviderSubscriptionId;
  final String? nextPaymentDate;
  final bool cancelAtPeriodEnd;
  final String? cancelRequestedAt;
  final String? canceledAt;
  final String? pendingPlan;
  final String? pendingPlanRequestedAt;
  final String? billingSubscriptionStatus;
  final OwnerLimits limits;
  final Map<String, bool> features;

  factory OwnerBillingStatus.fromMap(Map<String, dynamic> map) {
    return OwnerBillingStatus(
      companyId: _readString(map, 'companyId'),
      plan: _readString(map, 'plan', fallback: 'FREE'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      currentPeriodStart: _readOptionalString(map, 'currentPeriodStart'),
      currentPeriodEnd: _readOptionalString(map, 'currentPeriodEnd'),
      expiresAt: _readOptionalString(map, 'expiresAt'),
      provider: _readOptionalString(map, 'provider'),
      hasProviderSubscription: map['hasProviderSubscription'] == true,
      maskedProviderSubscriptionId: _readOptionalString(
        map,
        'maskedProviderSubscriptionId',
      ),
      nextPaymentDate: _readOptionalString(map, 'nextPaymentDate'),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      cancelRequestedAt: _readOptionalString(map, 'cancelRequestedAt'),
      canceledAt: _readOptionalString(map, 'canceledAt'),
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
      pendingPlanRequestedAt: _readOptionalString(
        map,
        'pendingPlanRequestedAt',
      ),
      billingSubscriptionStatus: _readOptionalString(
        map,
        'billingSubscriptionStatus',
      ),
      limits: OwnerLimits.fromMap(_readMap(map, 'limits')),
      features: _readBoolMap(map['features']),
    );
  }
}

class OwnerInvoice {
  const OwnerInvoice({
    required this.id,
    required this.provider,
    required this.status,
    required this.amountCents,
    required this.currency,
    required this.periodStart,
    required this.periodEnd,
    required this.dueAt,
    required this.paidAt,
    required this.failedAt,
    required this.invoiceUrl,
    required this.createdAt,
  });

  final String id;
  final String provider;
  final String status;
  final int amountCents;
  final String currency;
  final String? periodStart;
  final String? periodEnd;
  final String? dueAt;
  final String? paidAt;
  final String? failedAt;
  final String? invoiceUrl;
  final String? createdAt;

  factory OwnerInvoice.fromMap(Map<String, dynamic> map) {
    return OwnerInvoice(
      id: _readString(map, 'id'),
      provider: _readString(map, 'provider', fallback: 'mercadopago'),
      status: _readString(map, 'status', fallback: 'unknown'),
      amountCents: _readOptionalInt(map, 'amountCents') ?? 0,
      currency: _readString(map, 'currency', fallback: 'BRL'),
      periodStart: _readOptionalString(map, 'periodStart'),
      periodEnd: _readOptionalString(map, 'periodEnd'),
      dueAt: _readOptionalString(map, 'dueAt'),
      paidAt: _readOptionalString(map, 'paidAt'),
      failedAt: _readOptionalString(map, 'failedAt'),
      invoiceUrl: _readOptionalString(map, 'invoiceUrl'),
      createdAt: _readOptionalString(map, 'createdAt'),
    );
  }
}

class OwnerInvoicesPage {
  const OwnerInvoicesPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<OwnerInvoice> items;
  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory OwnerInvoicesPage.fromMap(Map<String, dynamic> map) {
    return OwnerInvoicesPage(
      items: _readMapList(map['items']).map(OwnerInvoice.fromMap).toList(),
      page: _readOptionalInt(map, 'page') ?? 1,
      pageSize: _readOptionalInt(map, 'pageSize') ?? 20,
      total: _readOptionalInt(map, 'total') ?? 0,
      count: _readOptionalInt(map, 'count') ?? 0,
      hasNext: map['hasNext'] == true,
      hasPrevious: map['hasPrevious'] == true,
    );
  }
}

class OwnerEmployeesPlaceholder {
  const OwnerEmployeesPlaceholder({
    required this.items,
    required this.count,
    required this.available,
    required this.reason,
  });

  final List<Map<String, dynamic>> items;
  final int count;
  final bool available;
  final String? reason;

  factory OwnerEmployeesPlaceholder.fromMap(Map<String, dynamic> map) {
    return OwnerEmployeesPlaceholder(
      items: _readMapList(map['items']),
      count: _readOptionalInt(map, 'count') ?? 0,
      available: map['available'] == true,
      reason: _readOptionalString(map, 'reason'),
    );
  }
}

class OwnerDevice {
  const OwnerDevice({
    required this.id,
    required this.maskedClientInstanceId,
    required this.deviceLabel,
    required this.platform,
    required this.appVersion,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lastSeenAt,
  });

  final String id;
  final String? maskedClientInstanceId;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final String? lastSeenAt;

  factory OwnerDevice.fromMap(Map<String, dynamic> map) {
    return OwnerDevice(
      id: _readString(map, 'id'),
      maskedClientInstanceId: _readOptionalString(
        map,
        'maskedClientInstanceId',
      ),
      deviceLabel: _readOptionalString(map, 'deviceLabel'),
      platform: _readOptionalString(map, 'platform'),
      appVersion: _readOptionalString(map, 'appVersion'),
      status: _readString(map, 'status', fallback: 'UNKNOWN'),
      createdAt: _readOptionalString(map, 'createdAt'),
      updatedAt: _readOptionalString(map, 'updatedAt'),
      lastSeenAt: _readOptionalString(map, 'lastSeenAt'),
    );
  }
}

class OwnerDevicesResult {
  const OwnerDevicesResult({
    required this.items,
    required this.count,
    required this.maxDevices,
  });

  final List<OwnerDevice> items;
  final int count;
  final int maxDevices;

  factory OwnerDevicesResult.fromMap(Map<String, dynamic> map) {
    return OwnerDevicesResult(
      items: _readMapList(map['items']).map(OwnerDevice.fromMap).toList(),
      count: _readOptionalInt(map, 'count') ?? 0,
      maxDevices: _readOptionalInt(_readMap(map, 'limits'), 'maxDevices') ?? 1,
    );
  }
}

class OwnerDashboard {
  const OwnerDashboard({
    required this.company,
    required this.billing,
    required this.employees,
    required this.devices,
    required this.sync,
    required this.reportsAvailable,
  });

  final OwnerDashboardCompany company;
  final OwnerDashboardBilling billing;
  final OwnerDashboardEmployees employees;
  final OwnerDashboardDevices devices;
  final OwnerDashboardSync? sync;
  final bool reportsAvailable;

  factory OwnerDashboard.fromMap(Map<String, dynamic> map) {
    return OwnerDashboard(
      company: OwnerDashboardCompany.fromMap(_readMap(map, 'company')),
      billing: OwnerDashboardBilling.fromMap(_readMap(map, 'billing')),
      employees: OwnerDashboardEmployees.fromMap(_readMap(map, 'employees')),
      devices: OwnerDashboardDevices.fromMap(_readMap(map, 'devices')),
      sync: map['sync'] is Map<String, dynamic>
          ? OwnerDashboardSync.fromMap(map['sync'] as Map<String, dynamic>)
          : null,
      reportsAvailable: map['reports'] is Map<String, dynamic>,
    );
  }
}

class OwnerDashboardCompany {
  const OwnerDashboardCompany({
    required this.companyId,
    required this.name,
    required this.setupCompleted,
  });

  final String companyId;
  final String name;
  final bool setupCompleted;

  factory OwnerDashboardCompany.fromMap(Map<String, dynamic> map) {
    return OwnerDashboardCompany(
      companyId: _readString(map, 'companyId'),
      name: _readString(map, 'name', fallback: 'Empresa'),
      setupCompleted: map['setupCompleted'] == true,
    );
  }
}

class OwnerDashboardBilling {
  const OwnerDashboardBilling({
    required this.plan,
    required this.status,
    required this.nextPaymentDate,
    required this.cancelAtPeriodEnd,
    required this.pendingPlan,
  });

  final String plan;
  final String status;
  final String? nextPaymentDate;
  final bool cancelAtPeriodEnd;
  final String? pendingPlan;

  factory OwnerDashboardBilling.fromMap(Map<String, dynamic> map) {
    return OwnerDashboardBilling(
      plan: _readString(map, 'plan', fallback: 'FREE'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      nextPaymentDate: _readOptionalString(map, 'nextPaymentDate'),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
    );
  }
}

class OwnerDashboardEmployees {
  const OwnerDashboardEmployees({
    required this.active,
    required this.invited,
    required this.disabled,
    required this.maxEmployees,
    required this.available,
    required this.reason,
  });

  final int active;
  final int invited;
  final int disabled;
  final int maxEmployees;
  final bool available;
  final String? reason;

  factory OwnerDashboardEmployees.fromMap(Map<String, dynamic> map) {
    return OwnerDashboardEmployees(
      active: _readOptionalInt(map, 'active') ?? 0,
      invited: _readOptionalInt(map, 'invited') ?? 0,
      disabled: _readOptionalInt(map, 'disabled') ?? 0,
      maxEmployees: _readOptionalInt(map, 'maxEmployees') ?? 0,
      available: map['available'] == true,
      reason: _readOptionalString(map, 'reason'),
    );
  }
}

class OwnerDashboardDevices {
  const OwnerDashboardDevices({
    required this.active,
    required this.blocked,
    required this.pending,
    required this.revoked,
    required this.maxDevices,
  });

  final int active;
  final int blocked;
  final int pending;
  final int revoked;
  final int maxDevices;

  factory OwnerDashboardDevices.fromMap(Map<String, dynamic> map) {
    return OwnerDashboardDevices(
      active: _readOptionalInt(map, 'active') ?? 0,
      blocked: _readOptionalInt(map, 'blocked') ?? 0,
      pending: _readOptionalInt(map, 'pending') ?? 0,
      revoked: _readOptionalInt(map, 'revoked') ?? 0,
      maxDevices: _readOptionalInt(map, 'maxDevices') ?? 1,
    );
  }
}

class OwnerDashboardSync {
  const OwnerDashboardSync({
    required this.lastSyncAt,
    required this.pendingEvents,
    required this.openConflicts,
  });

  final String? lastSyncAt;
  final int pendingEvents;
  final int openConflicts;

  factory OwnerDashboardSync.fromMap(Map<String, dynamic> map) {
    return OwnerDashboardSync(
      lastSyncAt: _readOptionalString(map, 'lastSyncAt'),
      pendingEvents: _readOptionalInt(map, 'pendingEvents') ?? 0,
      openConflicts: _readOptionalInt(map, 'openConflicts') ?? 0,
    );
  }
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

String _readString(
  Map<String, dynamic> map,
  String key, {
  String fallback = '',
}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

int? _readOptionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, bool> _readBoolMap(Object? value) {
  if (value is! Map) {
    return const <String, bool>{};
  }
  return Map<String, bool>.unmodifiable(
    value.map((key, item) => MapEntry(key.toString(), item == true)),
  );
}
