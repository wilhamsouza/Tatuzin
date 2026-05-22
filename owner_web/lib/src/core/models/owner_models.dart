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
    required this.pendingPlan,
    required this.pendingPlanRequestedAt,
  });

  final String id;
  final String plan;
  final String status;
  final String? startsAt;
  final String? expiresAt;
  final int maxDevices;
  final bool syncEnabled;
  final String? pendingPlan;
  final String? pendingPlanRequestedAt;

  bool get isPro => plan.trim().toUpperCase() == 'PRO';

  bool get isWaitingForProConfirmation =>
      pendingPlan?.trim().toUpperCase() == 'PRO' && !isPro;

  factory OwnerLicenseSnapshot.fromMap(Map<String, dynamic> map) {
    return OwnerLicenseSnapshot(
      id: _readString(map, 'id'),
      plan: _readString(map, 'plan', fallback: 'FREE'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      startsAt: _readOptionalString(map, 'startsAt'),
      expiresAt: _readOptionalString(map, 'expiresAt'),
      maxDevices: _readOptionalInt(map, 'maxDevices') ?? 1,
      syncEnabled: map['syncEnabled'] == true,
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
      pendingPlanRequestedAt: _readOptionalString(
        map,
        'pendingPlanRequestedAt',
      ),
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
      'pendingPlan': pendingPlan,
      'pendingPlanRequestedAt': pendingPlanRequestedAt,
    };
  }
}

class OwnerCompanySummary {
  const OwnerCompanySummary({
    required this.companyId,
    required this.name,
    required this.legalName,
    required this.documentNumber,
    required this.setupCompleted,
    required this.createdAt,
    required this.owner,
    required this.membershipRole,
    required this.receiptSettings,
    required this.license,
    required this.limits,
    required this.features,
  });

  final String companyId;
  final String name;
  final String legalName;
  final String? documentNumber;
  final bool setupCompleted;
  final String? createdAt;
  final OwnerCompanyOwner owner;
  final String membershipRole;
  final OwnerReceiptSettings receiptSettings;
  final OwnerLicenseSummary license;
  final OwnerLimits limits;
  final Map<String, bool> features;

  factory OwnerCompanySummary.fromMap(Map<String, dynamic> map) {
    return OwnerCompanySummary(
      companyId: _readString(map, 'companyId'),
      name: _readString(map, 'name', fallback: 'Empresa'),
      legalName: _readString(map, 'legalName', fallback: 'Empresa'),
      documentNumber: _readOptionalString(map, 'documentNumber'),
      setupCompleted: map['setupCompleted'] == true,
      createdAt: _readOptionalString(map, 'createdAt'),
      owner: OwnerCompanyOwner.fromMap(_readMap(map, 'owner')),
      membershipRole: _readString(_readMap(map, 'membership'), 'role'),
      receiptSettings: OwnerReceiptSettings.fromMap(
        _readMap(map, 'receiptSettings'),
      ),
      license: OwnerLicenseSummary.fromMap(_readMap(map, 'license')),
      limits: OwnerLimits.fromMap(_readMap(map, 'limits')),
      features: _readBoolMap(map['features']),
    );
  }
}

class OwnerCompanyOwner {
  const OwnerCompanyOwner({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory OwnerCompanyOwner.fromMap(Map<String, dynamic> map) {
    return OwnerCompanyOwner(
      id: _readString(map, 'id'),
      name: _readString(map, 'name', fallback: 'Dono'),
      email: _readString(map, 'email'),
    );
  }
}

class OwnerReceiptSettings {
  const OwnerReceiptSettings({
    required this.displayName,
    required this.document,
    required this.phone,
    required this.address,
    required this.footerMessage,
    required this.showDocument,
    required this.showPhone,
    required this.showAddress,
    required this.showFooterMessage,
  });

  final String? displayName;
  final String? document;
  final String? phone;
  final String? address;
  final String? footerMessage;
  final bool showDocument;
  final bool showPhone;
  final bool showAddress;
  final bool showFooterMessage;

  factory OwnerReceiptSettings.fromMap(Map<String, dynamic> map) {
    return OwnerReceiptSettings(
      displayName: _readOptionalString(map, 'displayName'),
      document: _readOptionalString(map, 'document'),
      phone: _readOptionalString(map, 'phone'),
      address: _readOptionalString(map, 'address'),
      footerMessage: _readOptionalString(map, 'footerMessage'),
      showDocument: map['showDocument'] == true,
      showPhone: map['showPhone'] == true,
      showAddress: map['showAddress'] == true,
      showFooterMessage: map['showFooterMessage'] == true,
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
    required this.canManageBilling,
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
  final bool canManageBilling;
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
      canManageBilling: map['canManageBilling'] == true,
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

class OwnerEmployeesOverview {
  const OwnerEmployeesOverview({
    required this.available,
    required this.canManage,
    required this.summary,
    required this.items,
    required this.count,
  });

  final bool available;
  final bool canManage;
  final OwnerEmployeesSummary summary;
  final List<OwnerEmployeeItem> items;
  final int count;

  factory OwnerEmployeesOverview.fromMap(Map<String, dynamic> map) {
    final items = _readMapList(
      map['items'],
    ).map(OwnerEmployeeItem.fromMap).toList(growable: false);
    return OwnerEmployeesOverview(
      available: map['available'] == true,
      canManage: map['canManage'] == true,
      summary: OwnerEmployeesSummary.fromMap(_readMap(map, 'summary')),
      items: items,
      count: _readOptionalInt(map, 'count') ?? items.length,
    );
  }
}

class OwnerEmployeesSummary {
  const OwnerEmployeesSummary({
    required this.total,
    required this.active,
    required this.disabled,
    required this.invited,
    required this.withActiveAccess,
    required this.temporaryPasswordPending,
    required this.commissionEnabled,
    required this.maxEmployees,
  });

  final int total;
  final int active;
  final int disabled;
  final int invited;
  final int withActiveAccess;
  final int temporaryPasswordPending;
  final int commissionEnabled;
  final int maxEmployees;

  factory OwnerEmployeesSummary.fromMap(Map<String, dynamic> map) {
    return OwnerEmployeesSummary(
      total: _readOptionalInt(map, 'total') ?? 0,
      active: _readOptionalInt(map, 'active') ?? 0,
      disabled: _readOptionalInt(map, 'disabled') ?? 0,
      invited: _readOptionalInt(map, 'invited') ?? 0,
      withActiveAccess: _readOptionalInt(map, 'withActiveAccess') ?? 0,
      temporaryPasswordPending:
          _readOptionalInt(map, 'temporaryPasswordPending') ?? 0,
      commissionEnabled: _readOptionalInt(map, 'commissionEnabled') ?? 0,
      maxEmployees: _readOptionalInt(map, 'maxEmployees') ?? 0,
    );
  }
}

class OwnerEmployeeItem {
  const OwnerEmployeeItem({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.accessStatus,
    required this.permissions,
    required this.permissionsCount,
    required this.commissionEnabled,
    required this.commissionType,
    required this.commissionBase,
    required this.commissionRateBps,
    required this.commissionFixedCents,
    required this.temporaryPasswordPending,
    required this.temporaryPasswordExpiresAt,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String role;
  final String status;
  final String accessStatus;
  final List<String> permissions;
  final int permissionsCount;
  final bool commissionEnabled;
  final String commissionType;
  final String commissionBase;
  final int? commissionRateBps;
  final int? commissionFixedCents;
  final bool temporaryPasswordPending;
  final String? temporaryPasswordExpiresAt;
  final String? lastSeenAt;

  factory OwnerEmployeeItem.fromMap(Map<String, dynamic> map) {
    return OwnerEmployeeItem(
      id: _readString(map, 'id'),
      name: _readString(map, 'name', fallback: 'Funcionario'),
      email: _readOptionalString(map, 'email'),
      phone: _readOptionalString(map, 'phone'),
      role: _readString(map, 'role', fallback: 'READ_ONLY'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      accessStatus: _readString(map, 'accessStatus', fallback: 'NO_ACCESS'),
      permissions: _readStringList(map['permissions']),
      permissionsCount: _readOptionalInt(map, 'permissionsCount') ?? 0,
      commissionEnabled: map['commissionEnabled'] == true,
      commissionType: _readString(map, 'commissionType', fallback: 'NONE'),
      commissionBase: _readString(map, 'commissionBase', fallback: 'NET_SALES'),
      commissionRateBps: _readOptionalInt(map, 'commissionRateBps'),
      commissionFixedCents: _readOptionalInt(map, 'commissionFixedCents'),
      temporaryPasswordPending: map['temporaryPasswordPending'] == true,
      temporaryPasswordExpiresAt: _readOptionalString(
        map,
        'temporaryPasswordExpiresAt',
      ),
      lastSeenAt: _readOptionalString(map, 'lastSeenAt'),
    );
  }
}

class OwnerEmployeeMutationResult {
  const OwnerEmployeeMutationResult({required this.employee});

  final OwnerEmployeeItem employee;

  factory OwnerEmployeeMutationResult.fromMap(Map<String, dynamic> map) {
    return OwnerEmployeeMutationResult(
      employee: OwnerEmployeeItem.fromMap(_readMap(map, 'employee')),
    );
  }
}

class OwnerTemporaryPasswordResult {
  const OwnerTemporaryPasswordResult({
    required this.employee,
    required this.login,
    required this.temporaryPassword,
    required this.temporaryPasswordExpiresAt,
  });

  final OwnerEmployeeItem employee;
  final String login;
  final String temporaryPassword;
  final String? temporaryPasswordExpiresAt;

  factory OwnerTemporaryPasswordResult.fromMap(Map<String, dynamic> map) {
    return OwnerTemporaryPasswordResult(
      employee: OwnerEmployeeItem.fromMap(_readMap(map, 'employee')),
      login: _readString(map, 'login'),
      temporaryPassword: _readString(map, 'temporaryPassword'),
      temporaryPasswordExpiresAt: _readOptionalString(
        map,
        'temporaryPasswordExpiresAt',
      ),
    );
  }
}

class OwnerCommissionSettings {
  const OwnerCommissionSettings({
    required this.commissionEnabled,
    required this.commissionType,
    required this.commissionBase,
    required this.commissionRateBps,
    required this.commissionFixedCents,
    required this.commissionUpdatedAt,
  });

  final bool commissionEnabled;
  final String commissionType;
  final String commissionBase;
  final int? commissionRateBps;
  final int? commissionFixedCents;
  final String? commissionUpdatedAt;

  factory OwnerCommissionSettings.fromMap(Map<String, dynamic> map) {
    return OwnerCommissionSettings(
      commissionEnabled: map['commissionEnabled'] == true,
      commissionType: _readString(map, 'commissionType', fallback: 'NONE'),
      commissionBase: _readString(map, 'commissionBase', fallback: 'NET_SALES'),
      commissionRateBps: _readOptionalInt(map, 'commissionRateBps'),
      commissionFixedCents: _readOptionalInt(map, 'commissionFixedCents'),
      commissionUpdatedAt: _readOptionalString(map, 'commissionUpdatedAt'),
    );
  }
}

class OwnerCommissionsSummary {
  const OwnerCommissionsSummary({
    required this.period,
    required this.totals,
    required this.rows,
    required this.notes,
  });

  final OwnerReportPeriod period;
  final OwnerCommissionTotals totals;
  final List<OwnerCommissionRow> rows;
  final List<String> notes;

  factory OwnerCommissionsSummary.fromMap(Map<String, dynamic> map) {
    return OwnerCommissionsSummary(
      period: OwnerReportPeriod.fromMap(_readMap(map, 'period')),
      totals: OwnerCommissionTotals.fromMap(_readMap(map, 'totals')),
      rows: _readMapList(
        map['rows'],
      ).map(OwnerCommissionRow.fromMap).toList(growable: false),
      notes: _readStringList(_readMap(map, 'tracking')['notes']),
    );
  }
}

class OwnerCommissionTotals {
  const OwnerCommissionTotals({
    required this.employeesWithCommission,
    required this.totalEligibleSalesAmountCents,
    required this.totalCommissionCents,
    required this.totalSalesCount,
    required this.salesWithoutReliableCostCount,
  });

  final int employeesWithCommission;
  final int totalEligibleSalesAmountCents;
  final int totalCommissionCents;
  final int totalSalesCount;
  final int salesWithoutReliableCostCount;

  factory OwnerCommissionTotals.fromMap(Map<String, dynamic> map) {
    return OwnerCommissionTotals(
      employeesWithCommission:
          _readOptionalInt(map, 'employeesWithCommission') ?? 0,
      totalEligibleSalesAmountCents:
          _readOptionalInt(map, 'totalEligibleSalesAmountCents') ?? 0,
      totalCommissionCents: _readOptionalInt(map, 'totalCommissionCents') ?? 0,
      totalSalesCount: _readOptionalInt(map, 'totalSalesCount') ?? 0,
      salesWithoutReliableCostCount:
          _readOptionalInt(map, 'salesWithoutReliableCostCount') ?? 0,
    );
  }
}

class OwnerCommissionRow {
  const OwnerCommissionRow({
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.status,
    required this.commissionEnabled,
    required this.commissionType,
    required this.commissionBase,
    required this.commissionRateBps,
    required this.commissionFixedCents,
    required this.salesCount,
    required this.eligibleSalesCount,
    required this.salesAmountCents,
    required this.eligibleBaseAmountCents,
    required this.commissionAmountCents,
    required this.salesWithoutReliableCostCount,
  });

  final String employeeId;
  final String employeeName;
  final String role;
  final String status;
  final bool commissionEnabled;
  final String commissionType;
  final String commissionBase;
  final int? commissionRateBps;
  final int? commissionFixedCents;
  final int salesCount;
  final int eligibleSalesCount;
  final int salesAmountCents;
  final int eligibleBaseAmountCents;
  final int commissionAmountCents;
  final int salesWithoutReliableCostCount;

  factory OwnerCommissionRow.fromMap(Map<String, dynamic> map) {
    return OwnerCommissionRow(
      employeeId: _readString(map, 'employeeId'),
      employeeName: _readString(map, 'employeeName', fallback: 'Funcionario'),
      role: _readString(map, 'role', fallback: 'READ_ONLY'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      commissionEnabled: map['commissionEnabled'] == true,
      commissionType: _readString(map, 'commissionType', fallback: 'NONE'),
      commissionBase: _readString(map, 'commissionBase', fallback: 'NET_SALES'),
      commissionRateBps: _readOptionalInt(map, 'commissionRateBps'),
      commissionFixedCents: _readOptionalInt(map, 'commissionFixedCents'),
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      eligibleSalesCount: _readOptionalInt(map, 'eligibleSalesCount') ?? 0,
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      eligibleBaseAmountCents:
          _readOptionalInt(map, 'eligibleBaseAmountCents') ?? 0,
      commissionAmountCents:
          _readOptionalInt(map, 'commissionAmountCents') ?? 0,
      salesWithoutReliableCostCount:
          _readOptionalInt(map, 'salesWithoutReliableCostCount') ?? 0,
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

class OwnerSyncStatus {
  const OwnerSyncStatus({
    required this.online,
    required this.syncEnabled,
    required this.lastSyncAt,
    required this.pendingEvents,
    required this.openConflicts,
    required this.activeDevices,
    required this.health,
    required this.message,
    required this.recentErrors,
    required this.sessions,
  });

  final bool online;
  final bool syncEnabled;
  final String? lastSyncAt;
  final int pendingEvents;
  final int openConflicts;
  final int activeDevices;
  final String health;
  final String message;
  final List<OwnerSyncError> recentErrors;
  final List<OwnerSyncSession> sessions;

  factory OwnerSyncStatus.fromMap(Map<String, dynamic> map) {
    return OwnerSyncStatus(
      online: map['online'] == true,
      syncEnabled: map['syncEnabled'] == true,
      lastSyncAt: _readOptionalString(map, 'lastSyncAt'),
      pendingEvents: _readOptionalInt(map, 'pendingEvents') ?? 0,
      openConflicts: _readOptionalInt(map, 'openConflicts') ?? 0,
      activeDevices: _readOptionalInt(map, 'activeDevices') ?? 0,
      health: _readString(map, 'health', fallback: 'ok'),
      message: _readString(map, 'message', fallback: 'Tudo sincronizado'),
      recentErrors: _readMapList(
        map['recentErrors'],
      ).map(OwnerSyncError.fromMap).toList(growable: false),
      sessions: _readMapList(
        map['sessions'],
      ).map(OwnerSyncSession.fromMap).toList(growable: false),
    );
  }
}

class OwnerSyncError {
  const OwnerSyncError({
    required this.area,
    required this.status,
    required this.code,
    required this.message,
    required this.updatedAt,
  });

  final String area;
  final String status;
  final String? code;
  final String message;
  final String? updatedAt;

  factory OwnerSyncError.fromMap(Map<String, dynamic> map) {
    return OwnerSyncError(
      area: _readString(map, 'area', fallback: 'Sincronizacao'),
      status: _readString(map, 'status', fallback: 'FAILED'),
      code: _readOptionalString(map, 'code'),
      message: _readString(
        map,
        'message',
        fallback: 'Falha recente de sincronizacao.',
      ),
      updatedAt: _readOptionalString(map, 'updatedAt'),
    );
  }
}

class OwnerSyncSession {
  const OwnerSyncSession({
    required this.clientType,
    required this.deviceLabel,
    required this.platform,
    required this.appVersion,
    required this.lastSeenAt,
  });

  final String clientType;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;
  final String? lastSeenAt;

  factory OwnerSyncSession.fromMap(Map<String, dynamic> map) {
    return OwnerSyncSession(
      clientType: _readString(map, 'clientType', fallback: 'UNKNOWN'),
      deviceLabel: _readOptionalString(map, 'deviceLabel'),
      platform: _readOptionalString(map, 'platform'),
      appVersion: _readOptionalString(map, 'appVersion'),
      lastSeenAt: _readOptionalString(map, 'lastSeenAt'),
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

class OwnerReportPeriod {
  const OwnerReportPeriod({
    required this.startDate,
    required this.endDate,
    required this.timezone,
  });

  final String? startDate;
  final String? endDate;
  final String timezone;

  factory OwnerReportPeriod.fromMap(Map<String, dynamic> map) {
    return OwnerReportPeriod(
      startDate: _readOptionalString(map, 'startDate'),
      endDate: _readOptionalString(map, 'endDate'),
      timezone: _readString(map, 'timezone', fallback: 'UTC'),
    );
  }
}

class OwnerBusinessDashboard {
  const OwnerBusinessDashboard({
    required this.period,
    required this.sales,
    required this.receivables,
    required this.customers,
    required this.products,
    required this.employees,
    required this.alerts,
  });

  final OwnerReportPeriod period;
  final OwnerBusinessSalesMetrics sales;
  final OwnerBusinessReceivablesMetrics receivables;
  final OwnerBusinessCustomersMetrics customers;
  final OwnerBusinessProductsMetrics products;
  final OwnerBusinessEmployeesMetrics employees;
  final List<OwnerBusinessAlert> alerts;

  factory OwnerBusinessDashboard.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessDashboard(
      period: OwnerReportPeriod.fromMap(_readMap(map, 'period')),
      sales: OwnerBusinessSalesMetrics.fromMap(_readMap(map, 'sales')),
      receivables: OwnerBusinessReceivablesMetrics.fromMap(
        _readMap(map, 'receivables'),
      ),
      customers: OwnerBusinessCustomersMetrics.fromMap(
        _readMap(map, 'customers'),
      ),
      products: OwnerBusinessProductsMetrics.fromMap(_readMap(map, 'products')),
      employees: OwnerBusinessEmployeesMetrics.fromMap(
        _readMap(map, 'employees'),
      ),
      alerts: _readMapList(
        map['alerts'],
      ).map(OwnerBusinessAlert.fromMap).toList(growable: false),
    );
  }
}

class OwnerBusinessSalesMetrics {
  const OwnerBusinessSalesMetrics({
    required this.todayAmountCents,
    required this.monthAmountCents,
    required this.todayCount,
    required this.monthCount,
    required this.averageTicketCents,
  });

  final int? todayAmountCents;
  final int? monthAmountCents;
  final int? todayCount;
  final int? monthCount;
  final int? averageTicketCents;

  factory OwnerBusinessSalesMetrics.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessSalesMetrics(
      todayAmountCents: _readOptionalInt(map, 'todayAmountCents'),
      monthAmountCents: _readOptionalInt(map, 'monthAmountCents'),
      todayCount: _readOptionalInt(map, 'todayCount'),
      monthCount: _readOptionalInt(map, 'monthCount'),
      averageTicketCents: _readOptionalInt(map, 'averageTicketCents'),
    );
  }
}

class OwnerBusinessReceivablesMetrics {
  const OwnerBusinessReceivablesMetrics({
    required this.openAmountCents,
    required this.overdueAmountCents,
    required this.openCount,
    required this.overdueCount,
  });

  final int? openAmountCents;
  final int? overdueAmountCents;
  final int? openCount;
  final int? overdueCount;

  factory OwnerBusinessReceivablesMetrics.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessReceivablesMetrics(
      openAmountCents: _readOptionalInt(map, 'openAmountCents'),
      overdueAmountCents: _readOptionalInt(map, 'overdueAmountCents'),
      openCount: _readOptionalInt(map, 'openCount'),
      overdueCount: _readOptionalInt(map, 'overdueCount'),
    );
  }
}

class OwnerBusinessCustomersMetrics {
  const OwnerBusinessCustomersMetrics({
    required this.total,
    required this.active,
    required this.inactive,
    required this.newThisMonth,
    required this.topCustomers,
  });

  final int? total;
  final int? active;
  final int? inactive;
  final int? newThisMonth;
  final List<OwnerCrmCustomer> topCustomers;

  factory OwnerBusinessCustomersMetrics.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessCustomersMetrics(
      total: _readOptionalInt(map, 'total'),
      active: _readOptionalInt(map, 'active'),
      inactive: _readOptionalInt(map, 'inactive'),
      newThisMonth: _readOptionalInt(map, 'newThisMonth'),
      topCustomers: _readMapList(
        map['topCustomers'],
      ).map(OwnerCrmCustomer.fromMap).toList(growable: false),
    );
  }
}

class OwnerBusinessProductsMetrics {
  const OwnerBusinessProductsMetrics({
    required this.total,
    required this.lowStock,
    required this.outOfStock,
    required this.topSelling,
  });

  final int? total;
  final int? lowStock;
  final int? outOfStock;
  final List<OwnerProductSalesItem> topSelling;

  factory OwnerBusinessProductsMetrics.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessProductsMetrics(
      total: _readOptionalInt(map, 'total'),
      lowStock: _readOptionalInt(map, 'lowStock'),
      outOfStock: _readOptionalInt(map, 'outOfStock'),
      topSelling: _readMapList(
        map['topSelling'],
      ).map(OwnerProductSalesItem.fromMap).toList(growable: false),
    );
  }
}

class OwnerBusinessEmployeesMetrics {
  const OwnerBusinessEmployeesMetrics({
    required this.available,
    required this.reason,
    required this.topPerformers,
  });

  final bool available;
  final String? reason;
  final List<OwnerEmployeePerformance> topPerformers;

  factory OwnerBusinessEmployeesMetrics.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessEmployeesMetrics(
      available: map['available'] == true,
      reason: _readOptionalString(map, 'reason'),
      topPerformers: _readMapList(
        map['topPerformers'],
      ).map(OwnerEmployeePerformance.fromMap).toList(growable: false),
    );
  }
}

class OwnerBusinessAlert {
  const OwnerBusinessAlert({
    required this.key,
    required this.severity,
    required this.title,
    required this.message,
    required this.count,
  });

  final String key;
  final String severity;
  final String title;
  final String message;
  final int? count;

  factory OwnerBusinessAlert.fromMap(Map<String, dynamic> map) {
    return OwnerBusinessAlert(
      key: _readString(map, 'key'),
      severity: _readString(map, 'severity', fallback: 'info'),
      title: _readString(map, 'title', fallback: 'Alerta'),
      message: _readString(map, 'message'),
      count: _readOptionalInt(map, 'count'),
    );
  }
}

class OwnerSalesSummary {
  const OwnerSalesSummary({
    required this.period,
    required this.totalAmountCents,
    required this.totalCount,
    required this.averageTicketCents,
    required this.series,
    required this.byPaymentMethod,
    required this.recentSales,
  });

  final OwnerReportPeriod period;
  final int totalAmountCents;
  final int totalCount;
  final int averageTicketCents;
  final List<OwnerSalesSeriesPoint> series;
  final List<OwnerPaymentMethodSummary> byPaymentMethod;
  final OwnerRecentSalesPage recentSales;

  factory OwnerSalesSummary.fromMap(Map<String, dynamic> map) {
    return OwnerSalesSummary(
      period: OwnerReportPeriod.fromMap(_readMap(map, 'period')),
      totalAmountCents: _readOptionalInt(map, 'totalAmountCents') ?? 0,
      totalCount: _readOptionalInt(map, 'totalCount') ?? 0,
      averageTicketCents: _readOptionalInt(map, 'averageTicketCents') ?? 0,
      series: _readMapList(
        map['series'],
      ).map(OwnerSalesSeriesPoint.fromMap).toList(growable: false),
      byPaymentMethod: _readMapList(
        map['byPaymentMethod'],
      ).map(OwnerPaymentMethodSummary.fromMap).toList(growable: false),
      recentSales: OwnerRecentSalesPage.fromMap(_readMap(map, 'recentSales')),
    );
  }
}

class OwnerSalesSeriesPoint {
  const OwnerSalesSeriesPoint({
    required this.date,
    required this.totalAmountCents,
    required this.totalCount,
    required this.averageTicketCents,
  });

  final String date;
  final int totalAmountCents;
  final int totalCount;
  final int averageTicketCents;

  factory OwnerSalesSeriesPoint.fromMap(Map<String, dynamic> map) {
    return OwnerSalesSeriesPoint(
      date: _readString(map, 'date'),
      totalAmountCents: _readOptionalInt(map, 'totalAmountCents') ?? 0,
      totalCount: _readOptionalInt(map, 'totalCount') ?? 0,
      averageTicketCents: _readOptionalInt(map, 'averageTicketCents') ?? 0,
    );
  }
}

class OwnerPaymentMethodSummary {
  const OwnerPaymentMethodSummary({
    required this.key,
    required this.label,
    required this.totalAmountCents,
    required this.count,
  });

  final String key;
  final String label;
  final int totalAmountCents;
  final int count;

  factory OwnerPaymentMethodSummary.fromMap(Map<String, dynamic> map) {
    return OwnerPaymentMethodSummary(
      key: _readString(map, 'key', fallback: 'outro'),
      label: _friendlyPaymentMethodLabel(
        _readString(
          map,
          'label',
          fallback: _readString(map, 'key', fallback: 'Outro'),
        ),
      ),
      totalAmountCents: _readOptionalInt(map, 'totalAmountCents') ?? 0,
      count: _readOptionalInt(map, 'count') ?? 0,
    );
  }
}

class OwnerRecentSalesPage {
  const OwnerRecentSalesPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<OwnerRecentSale> items;
  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory OwnerRecentSalesPage.fromMap(Map<String, dynamic> map) {
    return OwnerRecentSalesPage(
      items: _readMapList(
        map['items'],
      ).map(OwnerRecentSale.fromMap).toList(growable: false),
      page: _readOptionalInt(map, 'page') ?? 1,
      pageSize: _readOptionalInt(map, 'pageSize') ?? 20,
      total: _readOptionalInt(map, 'total') ?? 0,
      count: _readOptionalInt(map, 'count') ?? 0,
      hasNext: map['hasNext'] == true,
      hasPrevious: map['hasPrevious'] == true,
    );
  }
}

class OwnerRecentSale {
  const OwnerRecentSale({
    required this.title,
    required this.receiptNumber,
    required this.customerName,
    required this.paymentMethod,
    required this.totalAmountCents,
    required this.status,
    required this.soldAt,
    required this.canceledAt,
  });

  final String title;
  final String? receiptNumber;
  final String? customerName;
  final String paymentMethod;
  final int totalAmountCents;
  final String status;
  final String? soldAt;
  final String? canceledAt;

  factory OwnerRecentSale.fromMap(Map<String, dynamic> map) {
    return OwnerRecentSale(
      title: _readString(map, 'title', fallback: 'Venda recebida'),
      receiptNumber: _safeReceiptNumber(
        _readOptionalString(map, 'receiptNumber'),
      ),
      customerName: _readOptionalString(map, 'customerName'),
      paymentMethod: _friendlyPaymentMethodLabel(
        _readString(map, 'paymentMethod', fallback: 'Outro'),
      ),
      totalAmountCents: _readOptionalInt(map, 'totalAmountCents') ?? 0,
      status: _readString(map, 'status', fallback: 'active'),
      soldAt: _readOptionalString(map, 'soldAt'),
      canceledAt: _readOptionalString(map, 'canceledAt'),
    );
  }
}

class OwnerProductsReport {
  const OwnerProductsReport({
    required this.period,
    required this.topSellingProducts,
    required this.lowSellingProducts,
    required this.byCategory,
    required this.stockSummary,
  });

  final OwnerReportPeriod period;
  final List<OwnerProductSalesItem> topSellingProducts;
  final List<OwnerProductSalesItem> lowSellingProducts;
  final List<OwnerProductCategorySummary> byCategory;
  final OwnerProductsStockSummary stockSummary;

  factory OwnerProductsReport.fromMap(Map<String, dynamic> map) {
    return OwnerProductsReport(
      period: OwnerReportPeriod.fromMap(_readMap(map, 'period')),
      topSellingProducts: _readMapList(
        map['topSellingProducts'],
      ).map(OwnerProductSalesItem.fromMap).toList(growable: false),
      lowSellingProducts: _readMapList(
        map['lowSellingProducts'],
      ).map(OwnerProductSalesItem.fromMap).toList(growable: false),
      byCategory: _readMapList(
        map['byCategory'],
      ).map(OwnerProductCategorySummary.fromMap).toList(growable: false),
      stockSummary: OwnerProductsStockSummary.fromMap(
        _readMap(map, 'stockSummary'),
      ),
    );
  }
}

class OwnerProductSalesItem {
  const OwnerProductSalesItem({
    required this.productId,
    required this.productName,
    required this.quantityMil,
    required this.salesCount,
    required this.amountCents,
    required this.salePriceCents,
  });

  final String? productId;
  final String productName;
  final int quantityMil;
  final int salesCount;
  final int amountCents;
  final int? salePriceCents;

  factory OwnerProductSalesItem.fromMap(Map<String, dynamic> map) {
    return OwnerProductSalesItem(
      productId: _readOptionalString(map, 'productId'),
      productName: _readString(map, 'productName', fallback: 'Produto'),
      quantityMil: _readOptionalInt(map, 'quantityMil') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      amountCents: _readOptionalInt(map, 'amountCents') ?? 0,
      salePriceCents: _readOptionalInt(map, 'salePriceCents'),
    );
  }
}

class OwnerProductCategorySummary {
  const OwnerProductCategorySummary({
    required this.categoryId,
    required this.categoryName,
    required this.quantityMil,
    required this.amountCents,
    required this.salesCount,
  });

  final String? categoryId;
  final String categoryName;
  final int quantityMil;
  final int amountCents;
  final int salesCount;

  factory OwnerProductCategorySummary.fromMap(Map<String, dynamic> map) {
    return OwnerProductCategorySummary(
      categoryId: _readOptionalString(map, 'categoryId'),
      categoryName: _readString(map, 'categoryName', fallback: 'Sem categoria'),
      quantityMil: _readOptionalInt(map, 'quantityMil') ?? 0,
      amountCents: _readOptionalInt(map, 'amountCents') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
    );
  }
}

class OwnerProductsStockSummary {
  const OwnerProductsStockSummary({
    required this.totalProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.totalEstimatedCostCents,
  });

  final int totalProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final int? totalEstimatedCostCents;

  factory OwnerProductsStockSummary.fromMap(Map<String, dynamic> map) {
    return OwnerProductsStockSummary(
      totalProducts: _readOptionalInt(map, 'totalProducts') ?? 0,
      lowStockCount: _readOptionalInt(map, 'lowStockCount') ?? 0,
      outOfStockCount: _readOptionalInt(map, 'outOfStockCount') ?? 0,
      totalEstimatedCostCents: _readOptionalInt(map, 'totalEstimatedCostCents'),
    );
  }
}

class OwnerStockSummary {
  const OwnerStockSummary({
    required this.totalProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.totalEstimatedCostCents,
    required this.lowStockThresholdMil,
    required this.itemsLowStock,
    required this.itemsOutOfStock,
  });

  final int totalProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final int? totalEstimatedCostCents;
  final int lowStockThresholdMil;
  final List<OwnerStockItem> itemsLowStock;
  final List<OwnerStockItem> itemsOutOfStock;

  factory OwnerStockSummary.fromMap(Map<String, dynamic> map) {
    return OwnerStockSummary(
      totalProducts: _readOptionalInt(map, 'totalProducts') ?? 0,
      lowStockCount: _readOptionalInt(map, 'lowStockCount') ?? 0,
      outOfStockCount: _readOptionalInt(map, 'outOfStockCount') ?? 0,
      totalEstimatedCostCents: _readOptionalInt(map, 'totalEstimatedCostCents'),
      lowStockThresholdMil: _readOptionalInt(map, 'lowStockThresholdMil') ?? 0,
      itemsLowStock: _readMapList(
        map['itemsLowStock'],
      ).map(OwnerStockItem.fromMap).toList(growable: false),
      itemsOutOfStock: _readMapList(
        map['itemsOutOfStock'],
      ).map(OwnerStockItem.fromMap).toList(growable: false),
    );
  }
}

class OwnerStockItem {
  const OwnerStockItem({
    required this.id,
    required this.productId,
    required this.productVariantId,
    required this.name,
    required this.variantName,
    required this.sku,
    required this.currentStockMil,
    required this.costPriceCents,
    required this.salePriceCents,
    required this.estimatedCostCents,
  });

  final String id;
  final String productId;
  final String? productVariantId;
  final String name;
  final String? variantName;
  final String? sku;
  final int currentStockMil;
  final int costPriceCents;
  final int salePriceCents;
  final int estimatedCostCents;

  factory OwnerStockItem.fromMap(Map<String, dynamic> map) {
    return OwnerStockItem(
      id: _readString(map, 'id'),
      productId: _readString(map, 'productId'),
      productVariantId: _readOptionalString(map, 'productVariantId'),
      name: _readString(map, 'name', fallback: 'Produto'),
      variantName: _readOptionalString(map, 'variantName'),
      sku: _readOptionalString(map, 'sku'),
      currentStockMil: _readOptionalInt(map, 'currentStockMil') ?? 0,
      costPriceCents: _readOptionalInt(map, 'costPriceCents') ?? 0,
      salePriceCents: _readOptionalInt(map, 'salePriceCents') ?? 0,
      estimatedCostCents: _readOptionalInt(map, 'estimatedCostCents') ?? 0,
    );
  }
}

class OwnerCrmSummary {
  const OwnerCrmSummary({
    required this.inactiveAfterDays,
    required this.totalCustomers,
    required this.activeCustomers,
    required this.inactiveCustomers,
    required this.newCustomersThisMonth,
    required this.customersWithReceivables,
    required this.topCustomers,
    required this.customersAtRisk,
  });

  final int inactiveAfterDays;
  final int totalCustomers;
  final int activeCustomers;
  final int inactiveCustomers;
  final int newCustomersThisMonth;
  final int customersWithReceivables;
  final List<OwnerCrmCustomer> topCustomers;
  final List<OwnerCrmCustomer> customersAtRisk;

  factory OwnerCrmSummary.fromMap(Map<String, dynamic> map) {
    return OwnerCrmSummary(
      inactiveAfterDays: _readOptionalInt(map, 'inactiveAfterDays') ?? 90,
      totalCustomers: _readOptionalInt(map, 'totalCustomers') ?? 0,
      activeCustomers: _readOptionalInt(map, 'activeCustomers') ?? 0,
      inactiveCustomers: _readOptionalInt(map, 'inactiveCustomers') ?? 0,
      newCustomersThisMonth:
          _readOptionalInt(map, 'newCustomersThisMonth') ?? 0,
      customersWithReceivables:
          _readOptionalInt(map, 'customersWithReceivables') ?? 0,
      topCustomers: _readMapList(
        map['topCustomers'],
      ).map(OwnerCrmCustomer.fromMap).toList(growable: false),
      customersAtRisk: _readMapList(
        map['customersAtRisk'],
      ).map(OwnerCrmCustomer.fromMap).toList(growable: false),
    );
  }
}

class OwnerCrmCustomerPage {
  const OwnerCrmCustomerPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<OwnerCrmCustomer> items;
  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory OwnerCrmCustomerPage.fromMap(Map<String, dynamic> map) {
    return OwnerCrmCustomerPage(
      items: _readMapList(
        map['items'],
      ).map(OwnerCrmCustomer.fromMap).toList(growable: false),
      page: _readOptionalInt(map, 'page') ?? 1,
      pageSize: _readOptionalInt(map, 'pageSize') ?? 20,
      total: _readOptionalInt(map, 'total') ?? 0,
      count: _readOptionalInt(map, 'count') ?? 0,
      hasNext: map['hasNext'] == true,
      hasPrevious: map['hasPrevious'] == true,
    );
  }
}

class OwnerCrmCustomer {
  const OwnerCrmCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.totalPurchasedCents,
    required this.purchasesCount,
    required this.averageTicketCents,
    required this.lastPurchaseAt,
    required this.openReceivableAmountCents,
    required this.status,
    required this.statusLabel,
    required this.tags,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final int totalPurchasedCents;
  final int purchasesCount;
  final int averageTicketCents;
  final String? lastPurchaseAt;
  final int openReceivableAmountCents;
  final String status;
  final String statusLabel;
  final List<OwnerCustomerTag> tags;

  factory OwnerCrmCustomer.fromMap(Map<String, dynamic> map) {
    return OwnerCrmCustomer(
      id: _readString(map, 'id'),
      name: _readString(map, 'name', fallback: 'Cliente'),
      phone: _readOptionalString(map, 'phone'),
      email: _readOptionalString(map, 'email'),
      totalPurchasedCents: _readOptionalInt(map, 'totalPurchasedCents') ?? 0,
      purchasesCount: _readOptionalInt(map, 'purchasesCount') ?? 0,
      averageTicketCents: _readOptionalInt(map, 'averageTicketCents') ?? 0,
      lastPurchaseAt: _readOptionalString(map, 'lastPurchaseAt'),
      openReceivableAmountCents:
          _readOptionalInt(map, 'openReceivableAmountCents') ?? 0,
      status: _readString(map, 'status', fallback: 'inactive'),
      statusLabel: _readString(map, 'statusLabel', fallback: 'Inativo'),
      tags: _readMapList(
        map['tags'],
      ).map(OwnerCustomerTag.fromMap).toList(growable: false),
    );
  }
}

class OwnerCustomerTag {
  const OwnerCustomerTag({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final String? color;

  factory OwnerCustomerTag.fromMap(Map<String, dynamic> map) {
    return OwnerCustomerTag(
      id: _readString(map, 'id'),
      label: _readString(map, 'label', fallback: 'Etiqueta'),
      color: _readOptionalString(map, 'color'),
    );
  }
}

class OwnerCrmCustomerDetail {
  const OwnerCrmCustomerDetail({
    required this.customer,
    required this.topProducts,
    required this.recentPurchases,
    required this.receivables,
  });

  final OwnerCrmCustomer customer;
  final List<OwnerProductSalesItem> topProducts;
  final List<OwnerRecentSale> recentPurchases;
  final OwnerReceivablesSummary receivables;

  factory OwnerCrmCustomerDetail.fromMap(Map<String, dynamic> map) {
    return OwnerCrmCustomerDetail(
      customer: OwnerCrmCustomer.fromMap(_readMap(map, 'customer')),
      topProducts: _readMapList(
        map['topProducts'],
      ).map(OwnerProductSalesItem.fromMap).toList(growable: false),
      recentPurchases: _readMapList(
        map['recentPurchases'],
      ).map(OwnerRecentSale.fromMap).toList(growable: false),
      receivables: OwnerReceivablesSummary.fromMap(
        _readMap(map, 'receivables'),
      ),
    );
  }
}

class OwnerReceivablesReport {
  const OwnerReceivablesReport({required this.summary, required this.items});

  final OwnerReceivablesSummary summary;
  final OwnerReceivableItemPage items;

  factory OwnerReceivablesReport.fromMap(Map<String, dynamic> map) {
    return OwnerReceivablesReport(
      summary: OwnerReceivablesSummary.fromMap(_readMap(map, 'summary')),
      items: OwnerReceivableItemPage.fromMap(_readMap(map, 'items')),
    );
  }
}

class OwnerReceivablesSummary {
  const OwnerReceivablesSummary({
    required this.openAmountCents,
    required this.overdueAmountCents,
    required this.openCount,
    required this.overdueCount,
    required this.paidCount,
    required this.receivedThisMonthCents,
  });

  final int openAmountCents;
  final int overdueAmountCents;
  final int openCount;
  final int overdueCount;
  final int paidCount;
  final int receivedThisMonthCents;

  factory OwnerReceivablesSummary.fromMap(Map<String, dynamic> map) {
    return OwnerReceivablesSummary(
      openAmountCents: _readOptionalInt(map, 'openAmountCents') ?? 0,
      overdueAmountCents: _readOptionalInt(map, 'overdueAmountCents') ?? 0,
      openCount: _readOptionalInt(map, 'openCount') ?? 0,
      overdueCount: _readOptionalInt(map, 'overdueCount') ?? 0,
      paidCount: _readOptionalInt(map, 'paidCount') ?? 0,
      receivedThisMonthCents:
          _readOptionalInt(map, 'receivedThisMonthCents') ?? 0,
    );
  }
}

class OwnerReceivableItemPage {
  const OwnerReceivableItemPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<OwnerReceivableItem> items;
  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory OwnerReceivableItemPage.fromMap(Map<String, dynamic> map) {
    return OwnerReceivableItemPage(
      items: _readMapList(
        map['items'],
      ).map(OwnerReceivableItem.fromMap).toList(growable: false),
      page: _readOptionalInt(map, 'page') ?? 1,
      pageSize: _readOptionalInt(map, 'pageSize') ?? 20,
      total: _readOptionalInt(map, 'total') ?? 0,
      count: _readOptionalInt(map, 'count') ?? 0,
      hasNext: map['hasNext'] == true,
      hasPrevious: map['hasPrevious'] == true,
    );
  }
}

class OwnerReceivableItem {
  const OwnerReceivableItem({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.openAmountCents,
    required this.overdueAmountCents,
    required this.paidAmountCents,
    required this.totalAmountCents,
    required this.salesCount,
    required this.dueDate,
    required this.status,
  });

  final String id;
  final String? customerId;
  final String customerName;
  final int openAmountCents;
  final int overdueAmountCents;
  final int paidAmountCents;
  final int totalAmountCents;
  final int salesCount;
  final String? dueDate;
  final String status;

  factory OwnerReceivableItem.fromMap(Map<String, dynamic> map) {
    return OwnerReceivableItem(
      id: _readString(map, 'id'),
      customerId: _readOptionalString(map, 'customerId'),
      customerName: _readString(map, 'customerName', fallback: 'Cliente'),
      openAmountCents: _readOptionalInt(map, 'openAmountCents') ?? 0,
      overdueAmountCents: _readOptionalInt(map, 'overdueAmountCents') ?? 0,
      paidAmountCents: _readOptionalInt(map, 'paidAmountCents') ?? 0,
      totalAmountCents: _readOptionalInt(map, 'totalAmountCents') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      dueDate: _readOptionalString(map, 'dueDate'),
      status: _readString(map, 'status', fallback: 'open'),
    );
  }
}

class OwnerEmployeeReports {
  const OwnerEmployeeReports({
    required this.available,
    required this.reason,
    required this.period,
    required this.topEmployees,
  });

  final bool available;
  final String? reason;
  final OwnerReportPeriod period;
  final List<OwnerEmployeePerformance> topEmployees;

  factory OwnerEmployeeReports.fromMap(Map<String, dynamic> map) {
    return OwnerEmployeeReports(
      available: map['available'] == true,
      reason: _readOptionalString(map, 'reason'),
      period: OwnerReportPeriod.fromMap(_readMap(map, 'period')),
      topEmployees: _readMapList(
        map['topEmployees'],
      ).map(OwnerEmployeePerformance.fromMap).toList(growable: false),
    );
  }
}

class OwnerEmployeePerformance {
  const OwnerEmployeePerformance({
    required this.employeeId,
    required this.userId,
    required this.name,
    required this.role,
    required this.status,
    required this.salesAmountCents,
    required this.salesCount,
    required this.averageTicketCents,
    required this.lastSaleAt,
  });

  final String employeeId;
  final String userId;
  final String name;
  final String? role;
  final String? status;
  final int salesAmountCents;
  final int salesCount;
  final int averageTicketCents;
  final String? lastSaleAt;

  factory OwnerEmployeePerformance.fromMap(Map<String, dynamic> map) {
    return OwnerEmployeePerformance(
      employeeId: _readString(map, 'employeeId'),
      userId: _readString(map, 'userId'),
      name: _readString(map, 'name', fallback: 'Funcionário'),
      role: _readOptionalString(map, 'role'),
      status: _readOptionalString(map, 'status'),
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      averageTicketCents: _readOptionalInt(map, 'averageTicketCents') ?? 0,
      lastSaleAt: _readOptionalString(map, 'lastSaleAt'),
    );
  }
}

class OwnerReportsCatalog {
  const OwnerReportsCatalog({required this.items});

  final List<OwnerReportCatalogItem> items;

  factory OwnerReportsCatalog.fromMap(Map<String, dynamic> map) {
    return OwnerReportsCatalog(
      items: _readMapList(
        map['items'],
      ).map(OwnerReportCatalogItem.fromMap).toList(growable: false),
    );
  }
}

class OwnerReportCatalogItem {
  const OwnerReportCatalogItem({
    required this.key,
    required this.title,
    required this.description,
    required this.available,
    required this.reason,
  });

  final String key;
  final String title;
  final String description;
  final bool available;
  final String? reason;

  factory OwnerReportCatalogItem.fromMap(Map<String, dynamic> map) {
    return OwnerReportCatalogItem(
      key: _readString(map, 'key'),
      title: _readString(map, 'title', fallback: 'Relatório'),
      description: _readString(map, 'description'),
      available: map['available'] == true,
      reason: _readOptionalString(map, 'reason'),
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

String? _safeReceiptNumber(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed.length > 20) {
    return null;
  }
  return trimmed;
}

String _friendlyPaymentMethodLabel(String value) {
  final raw = value.trim();
  final rawLower = raw.toLowerCase();
  final normalized = rawLower
      .replaceAll('[pm:', '')
      .replaceAll('pm:', '')
      .replaceAll(']', '')
      .replaceAll(' ', '_');
  switch (normalized) {
    case 'dinheiro':
      return 'Dinheiro';
    case 'pix':
      return 'Pix';
    case 'cartao':
    case 'cartao_credito':
    case 'cartao_debito':
    case 'cartão':
    case 'cartão_crédito':
    case 'cartão_débito':
      return 'Cartão';
    case 'fiado':
      return 'Fiado';
    default:
      if (raw.isEmpty || rawLower.contains('pm:') || raw.contains('[')) {
        return 'Outro';
      }
      return raw;
  }
}
