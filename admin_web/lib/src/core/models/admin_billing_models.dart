import 'dart:convert';

const Set<String> adminBillingSensitiveKeys = {
  'authorization',
  'access_token',
  'accesstoken',
  'refresh_token',
  'refreshtoken',
  'token',
  'mercado_pago_access_token',
  'mercado_pago_webhook_secret',
  'webhook_secret',
  'x-signature',
  'checkouturl',
  'sandboxcheckouturl',
  'init_point',
  'sandbox_init_point',
  'providersubscriptionid',
  'provider_subscription_id',
  'providerreference',
  'provider_reference',
  'providereventid',
  'provider_event_id',
  'card',
  'card_number',
  'security_code',
  'cvv',
};

Object? sanitizeAdminBillingValue(Object? value) {
  if (value == null || value is num || value is bool) {
    return value;
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  if (value is String) {
    return _sanitizeString(value);
  }

  if (value is List) {
    return value.map(sanitizeAdminBillingValue).toList(growable: false);
  }

  if (value is Map) {
    final sanitized = <String, Object?>{};
    value.forEach((key, rawValue) {
      final keyString = key.toString();
      final normalizedKey = _normalizeSensitiveKey(keyString);
      if (_isSensitiveKey(normalizedKey)) {
        sanitized[keyString] = '[redacted]';
        return;
      }
      sanitized[keyString] = sanitizeAdminBillingValue(rawValue);
    });
    return sanitized;
  }

  return value.toString();
}

String formatSanitizedAdminJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(sanitizeAdminBillingValue(value));
}

String maskAdminBillingUrl(String? value) {
  final normalized = _normalized(value);
  if (normalized == null) {
    return 'Não informado';
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) {
    return '[url mascarada]';
  }
  final suffix = uri.pathSegments.isEmpty ? '' : '/...';
  return '${uri.scheme}://${uri.host}$suffix';
}

String maskAdminBillingIdentifier(String? value) {
  final normalized = _normalized(value);
  if (normalized == null) {
    return 'NÃ£o informado';
  }
  if (normalized.length <= 8) {
    return normalized;
  }
  return '${normalized.substring(0, 4)}...${normalized.substring(normalized.length - 4)}';
}

String _sanitizeString(String value) {
  final trimmed = value.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('bearer ') ||
      lower.contains('access_token=') ||
      lower.contains('refresh_token=') ||
      lower.contains('x-signature=') ||
      lower.contains('mercado_pago_access_token') ||
      lower.contains('mercado_pago_webhook_secret')) {
    return '[redacted]';
  }
  if (_looksLikeCheckoutUrl(trimmed)) {
    return maskAdminBillingUrl(trimmed);
  }
  return value;
}

bool _looksLikeCheckoutUrl(String value) {
  final lower = value.toLowerCase();
  if (!lower.startsWith('http')) {
    return false;
  }
  return lower.contains('checkout') ||
      lower.contains('mercadopago') ||
      lower.contains('mercado_pago');
}

bool _isSensitiveKey(String normalizedKey) {
  if (normalizedKey.startsWith('maskedprovider') ||
      normalizedKey.contains('masked_provider')) {
    return false;
  }
  if (adminBillingSensitiveKeys.contains(normalizedKey)) {
    return true;
  }
  return normalizedKey.contains('authorization') ||
      normalizedKey.contains('access_token') ||
      normalizedKey.contains('accesstoken') ||
      normalizedKey.contains('refresh_token') ||
      normalizedKey.contains('refreshtoken') ||
      normalizedKey.contains('webhooksecret') ||
      normalizedKey.contains('webhook_secret') ||
      normalizedKey.contains('xsignature') ||
      normalizedKey.contains('x-signature') ||
      normalizedKey.contains('x_signature') ||
      normalizedKey.contains('securitycode') ||
      normalizedKey.contains('cardnumber') ||
      normalizedKey == 'card' ||
      normalizedKey == 'cvv' ||
      normalizedKey == 'token' ||
      normalizedKey.endsWith('token') ||
      normalizedKey.contains('checkouturl') ||
      normalizedKey.contains('init_point') ||
      normalizedKey.contains('providersubscriptionid') ||
      normalizedKey.contains('provider_subscription_id') ||
      normalizedKey.contains('providerreference') ||
      normalizedKey.contains('provider_reference') ||
      normalizedKey.contains('providereventid') ||
      normalizedKey.contains('provider_event_id');
}

String _normalizeSensitiveKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]'), '_');
}

class AdminBillingCompaniesQuery {
  const AdminBillingCompaniesQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.plan,
    this.status,
    this.provider,
    this.hasProviderSubscription,
    this.sort = 'updatedAt',
    this.sortDirection = 'desc',
  });

  final int page;
  final int pageSize;
  final String? search;
  final String? plan;
  final String? status;
  final String? provider;
  final bool? hasProviderSubscription;
  final String sort;
  final String sortDirection;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(search) case final value?) 'search': value,
      if (_normalized(plan) case final value?) 'plan': value,
      if (_normalized(status) case final value?) 'status': value,
      if (_normalized(provider) case final value?) 'provider': value,
      if (hasProviderSubscription != null)
        'hasProviderSubscription': '$hasProviderSubscription',
      'sort': sort,
      'sortDirection': sortDirection,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminBillingCompaniesQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.plan == plan &&
        other.status == status &&
        other.provider == provider &&
        other.hasProviderSubscription == hasProviderSubscription &&
        other.sort == sort &&
        other.sortDirection == sortDirection;
  }

  @override
  int get hashCode => Object.hash(
    page,
    pageSize,
    search,
    plan,
    status,
    provider,
    hasProviderSubscription,
    sort,
    sortDirection,
  );
}

class AdminBillingListQuery {
  const AdminBillingListQuery({
    required this.companyId,
    this.page = 1,
    this.pageSize = 20,
  });

  final String companyId;
  final int page;
  final int pageSize;

  Map<String, String> toQueryParameters() {
    return <String, String>{'page': '$page', 'pageSize': '$pageSize'};
  }

  @override
  bool operator ==(Object other) {
    return other is AdminBillingListQuery &&
        other.companyId == companyId &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(companyId, page, pageSize);
}

class AdminBillingCompanySummary {
  const AdminBillingCompanySummary({
    required this.companyId,
    required this.companyName,
    required this.plan,
    required this.licenseStatus,
    required this.billingProvider,
    required this.hasProviderSubscription,
    required this.maskedProviderSubscriptionId,
    required this.currentPeriodEnd,
    required this.nextPaymentDate,
    required this.cancelAtPeriodEnd,
    required this.pendingPlan,
    required this.billingSubscriptionStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String companyId;
  final String companyName;
  final String plan;
  final String? licenseStatus;
  final String? billingProvider;
  final bool hasProviderSubscription;
  final String? maskedProviderSubscriptionId;
  final DateTime? currentPeriodEnd;
  final DateTime? nextPaymentDate;
  final bool cancelAtPeriodEnd;
  final String? pendingPlan;
  final String? billingSubscriptionStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminBillingCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminBillingCompanySummary(
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      plan: _readString(map, 'plan', fallback: 'FREE'),
      licenseStatus: _readOptionalString(map, 'licenseStatus'),
      billingProvider: _readOptionalString(map, 'billingProvider'),
      hasProviderSubscription: map['hasProviderSubscription'] == true,
      maskedProviderSubscriptionId: _readOptionalString(
        map,
        'maskedProviderSubscriptionId',
      ),
      currentPeriodEnd: _readDate(map, 'currentPeriodEnd'),
      nextPaymentDate: _readDate(map, 'nextPaymentDate'),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
      billingSubscriptionStatus: _readOptionalString(
        map,
        'billingSubscriptionStatus',
      ),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
    );
  }
}

class AdminBillingCompanyStatus {
  const AdminBillingCompanyStatus({
    required this.companyId,
    required this.companyName,
    required this.license,
    required this.billing,
    required this.checkoutSessions,
    required this.events,
    required this.invoices,
  });

  final String companyId;
  final String companyName;
  final AdminBillingLicenseSnapshot? license;
  final AdminBillingStatusSnapshot billing;
  final List<AdminBillingCheckoutSession> checkoutSessions;
  final List<AdminBillingEvent> events;
  final List<AdminBillingInvoiceSummary> invoices;

  factory AdminBillingCompanyStatus.fromMap(Map<String, dynamic> map) {
    final company = _readMap(map, 'company');
    return AdminBillingCompanyStatus(
      companyId: _readString(company, 'id'),
      companyName: _readString(company, 'name', fallback: 'Empresa'),
      license: map['license'] is Map<String, dynamic>
          ? AdminBillingLicenseSnapshot.fromMap(
              map['license'] as Map<String, dynamic>,
            )
          : null,
      billing: map['billing'] is Map<String, dynamic>
          ? AdminBillingStatusSnapshot.fromMap(
              map['billing'] as Map<String, dynamic>,
            )
          : const AdminBillingStatusSnapshot(),
      checkoutSessions: _readList(
        map,
        'checkoutSessions',
      ).map(AdminBillingCheckoutSession.fromMap).toList(growable: false),
      events: _readList(
        map,
        'events',
      ).map(AdminBillingEvent.fromMap).toList(growable: false),
      invoices: _readList(
        map,
        'invoices',
      ).map(AdminBillingInvoiceSummary.fromMap).toList(growable: false),
    );
  }
}

class AdminBillingStatusSnapshot {
  const AdminBillingStatusSnapshot({
    this.provider,
    this.providerSubscriptionId,
    this.hasProviderSubscription = false,
    this.maskedProviderSubscriptionId,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.nextPaymentDate,
    this.cancelAtPeriodEnd = false,
    this.cancelRequestedAt,
    this.canceledAt,
    this.pendingPlan,
    this.pendingPlanRequestedAt,
    this.billingSubscriptionStatus,
  });

  final String? provider;
  final String? providerSubscriptionId;
  final bool hasProviderSubscription;
  final String? maskedProviderSubscriptionId;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextPaymentDate;
  final bool cancelAtPeriodEnd;
  final DateTime? cancelRequestedAt;
  final DateTime? canceledAt;
  final String? pendingPlan;
  final DateTime? pendingPlanRequestedAt;
  final String? billingSubscriptionStatus;

  factory AdminBillingStatusSnapshot.fromMap(Map<String, dynamic> map) {
    return AdminBillingStatusSnapshot(
      provider: _readOptionalString(map, 'provider'),
      providerSubscriptionId: _readOptionalString(
        map,
        'providerSubscriptionId',
      ),
      hasProviderSubscription: map['hasProviderSubscription'] == true,
      maskedProviderSubscriptionId: _readOptionalString(
        map,
        'maskedProviderSubscriptionId',
      ),
      currentPeriodStart: _readDate(map, 'currentPeriodStart'),
      currentPeriodEnd: _readDate(map, 'currentPeriodEnd'),
      nextPaymentDate: _readDate(map, 'nextPaymentDate'),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      cancelRequestedAt: _readDate(map, 'cancelRequestedAt'),
      canceledAt: _readDate(map, 'canceledAt'),
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
      pendingPlanRequestedAt: _readDate(map, 'pendingPlanRequestedAt'),
      billingSubscriptionStatus: _readOptionalString(
        map,
        'billingSubscriptionStatus',
      ),
    );
  }
}

class AdminBillingLicenseSnapshot {
  const AdminBillingLicenseSnapshot({
    this.id,
    this.companyId,
    required this.plan,
    this.normalizedPlan,
    required this.status,
    this.providerSubscriptionId,
    this.billingProvider,
    this.startsAt,
    this.expiresAt,
    this.maxDevices,
    this.syncEnabled = false,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.nextPaymentDate,
    this.cancelAtPeriodEnd = false,
    this.cancelRequestedAt,
    this.canceledAt,
    this.pendingPlan,
    this.pendingPlanRequestedAt,
    this.billingSubscriptionStatus,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? companyId;
  final String plan;
  final String? normalizedPlan;
  final String status;
  final String? providerSubscriptionId;
  final String? billingProvider;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? maxDevices;
  final bool syncEnabled;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextPaymentDate;
  final bool cancelAtPeriodEnd;
  final DateTime? cancelRequestedAt;
  final DateTime? canceledAt;
  final String? pendingPlan;
  final DateTime? pendingPlanRequestedAt;
  final String? billingSubscriptionStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminBillingLicenseSnapshot.fromMap(Map<String, dynamic> map) {
    return AdminBillingLicenseSnapshot(
      id: _readOptionalString(map, 'id'),
      companyId: _readOptionalString(map, 'companyId'),
      plan: _readString(map, 'plan', fallback: 'FREE'),
      normalizedPlan: _readOptionalString(map, 'normalizedPlan'),
      status: _readString(map, 'status', fallback: 'ACTIVE'),
      providerSubscriptionId: _readOptionalString(
        map,
        'providerSubscriptionId',
      ),
      billingProvider: _readOptionalString(map, 'billingProvider'),
      startsAt: _readDate(map, 'startsAt'),
      expiresAt: _readDate(map, 'expiresAt'),
      maxDevices: _readInt(map, 'maxDevices'),
      syncEnabled: map['syncEnabled'] == true,
      currentPeriodStart: _readDate(map, 'currentPeriodStart'),
      currentPeriodEnd: _readDate(map, 'currentPeriodEnd'),
      nextPaymentDate: _readDate(map, 'nextPaymentDate'),
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      cancelRequestedAt: _readDate(map, 'cancelRequestedAt'),
      canceledAt: _readDate(map, 'canceledAt'),
      pendingPlan: _readOptionalString(map, 'pendingPlan'),
      pendingPlanRequestedAt: _readDate(map, 'pendingPlanRequestedAt'),
      billingSubscriptionStatus: _readOptionalString(
        map,
        'billingSubscriptionStatus',
      ),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
    );
  }
}

class AdminBillingCheckoutSession {
  const AdminBillingCheckoutSession({
    required this.id,
    required this.plan,
    required this.status,
    this.billingCycle,
    this.provider,
    this.providerReference,
    this.checkoutUrl,
    this.sandboxCheckoutUrl,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String plan;
  final String status;
  final String? billingCycle;
  final String? provider;
  final String? providerReference;
  final String? checkoutUrl;
  final String? sandboxCheckoutUrl;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminBillingCheckoutSession.fromMap(Map<String, dynamic> map) {
    return AdminBillingCheckoutSession(
      id: _readString(map, 'id'),
      plan: _readString(map, 'plan', fallback: 'FREE'),
      status: _readString(map, 'status', fallback: 'unknown'),
      billingCycle: _readOptionalString(map, 'billingCycle'),
      provider: _readOptionalString(map, 'provider'),
      providerReference: _readOptionalString(map, 'providerReference'),
      checkoutUrl: _readOptionalString(map, 'checkoutUrl') == null
          ? null
          : maskAdminBillingUrl(_readOptionalString(map, 'checkoutUrl')),
      sandboxCheckoutUrl: _readOptionalString(map, 'sandboxCheckoutUrl') == null
          ? null
          : maskAdminBillingUrl(_readOptionalString(map, 'sandboxCheckoutUrl')),
      expiresAt: _readDate(map, 'expiresAt'),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
    );
  }
}

class AdminBillingEvent {
  const AdminBillingEvent({
    required this.id,
    required this.provider,
    required this.eventType,
    this.providerEventId,
    this.dedupeKey,
    this.payload,
    required this.status,
    this.processedAt,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String provider;
  final String eventType;
  final String? providerEventId;
  final String? dedupeKey;
  final Object? payload;
  final String status;
  final DateTime? processedAt;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminBillingEvent.fromMap(Map<String, dynamic> map) {
    return AdminBillingEvent(
      id: _readString(map, 'id'),
      provider: _readString(map, 'provider', fallback: 'provider'),
      eventType: _readString(map, 'eventType', fallback: 'event'),
      providerEventId: _readOptionalString(map, 'providerEventId'),
      dedupeKey: _readOptionalString(map, 'dedupeKey'),
      payload: sanitizeAdminBillingValue(map['payload']),
      status: _readString(map, 'status', fallback: 'unknown'),
      processedAt: _readDate(map, 'processedAt'),
      errorMessage: _readOptionalString(map, 'errorMessage'),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
    );
  }
}

class AdminBillingAuditLog {
  const AdminBillingAuditLog({
    required this.id,
    required this.action,
    this.reason,
    required this.actorUserId,
    this.actorName,
    this.actorEmail,
    this.companyId,
    this.before,
    this.after,
    this.metadata,
    this.ipAddress,
    this.userAgent,
    this.createdAt,
  });

  final String id;
  final String action;
  final String? reason;
  final String actorUserId;
  final String? actorName;
  final String? actorEmail;
  final String? companyId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final Map<String, dynamic>? metadata;
  final String? ipAddress;
  final Object? userAgent;
  final DateTime? createdAt;

  factory AdminBillingAuditLog.fromMap(Map<String, dynamic> map) {
    return AdminBillingAuditLog(
      id: _readString(map, 'id'),
      action: _readString(map, 'action', fallback: 'admin.billing.action'),
      reason: _readOptionalString(map, 'reason'),
      actorUserId: _readString(map, 'actorUserId'),
      actorName: _readOptionalString(map, 'actorName'),
      actorEmail: _readOptionalString(map, 'actorEmail'),
      companyId: _readOptionalString(map, 'companyId'),
      before: _readNullableSafeMap(map, 'before'),
      after: _readNullableSafeMap(map, 'after'),
      metadata: _readNullableSafeMap(map, 'metadata'),
      ipAddress: _readOptionalString(map, 'ipAddress'),
      userAgent: sanitizeAdminBillingValue(map['userAgent']),
      createdAt: _readDate(map, 'createdAt'),
    );
  }
}

class AdminBillingInvoiceSummary {
  const AdminBillingInvoiceSummary({
    required this.id,
    required this.provider,
    this.providerInvoiceId,
    this.maskedProviderSubscriptionId,
    this.plan,
    required this.status,
    required this.amountCents,
    required this.currency,
    this.periodStart,
    this.periodEnd,
    this.dueAt,
    this.paidAt,
    this.failedAt,
    this.invoiceUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String provider;
  final String? providerInvoiceId;
  final String? maskedProviderSubscriptionId;
  final String? plan;
  final String status;
  final int amountCents;
  final String currency;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? dueAt;
  final DateTime? paidAt;
  final DateTime? failedAt;
  final String? invoiceUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminBillingInvoiceSummary.fromMap(Map<String, dynamic> map) {
    return AdminBillingInvoiceSummary(
      id: _readString(map, 'id'),
      provider: _readString(map, 'provider', fallback: 'provider'),
      providerInvoiceId: _readOptionalString(map, 'providerInvoiceId'),
      maskedProviderSubscriptionId: _readOptionalString(
        map,
        'providerSubscriptionId',
      ),
      plan: _readOptionalString(map, 'plan'),
      status: _readString(map, 'status', fallback: 'unknown'),
      amountCents: _readInt(map, 'amountCents') ?? 0,
      currency: _readString(map, 'currency', fallback: 'BRL'),
      periodStart: _readDate(map, 'periodStart'),
      periodEnd: _readDate(map, 'periodEnd'),
      dueAt: _readDate(map, 'dueAt'),
      paidAt: _readDate(map, 'paidAt'),
      failedAt: _readDate(map, 'failedAt'),
      invoiceUrl: _readOptionalString(map, 'invoiceUrl') == null
          ? null
          : maskAdminBillingUrl(_readOptionalString(map, 'invoiceUrl')),
      createdAt: _readDate(map, 'createdAt'),
      updatedAt: _readDate(map, 'updatedAt'),
    );
  }
}

class AdminLicenseExtensionDryRun {
  const AdminLicenseExtensionDryRun({
    required this.allowed,
    required this.expectedConfirmationText,
    required this.summary,
    required this.risks,
    required this.blockers,
    required this.currentLicense,
    required this.proposedChange,
    required this.maxAllowedDays,
    required this.allowedDaysMin,
    required this.allowedDaysMax,
  });

  final bool allowed;
  final String expectedConfirmationText;
  final String summary;
  final List<String> risks;
  final List<String> blockers;
  final Map<String, dynamic>? currentLicense;
  final Map<String, dynamic>? proposedChange;
  final int maxAllowedDays;
  final int allowedDaysMin;
  final int allowedDaysMax;

  factory AdminLicenseExtensionDryRun.fromMap(Map<String, dynamic> map) {
    final range = _readMap(map, 'allowedDaysRange');
    return AdminLicenseExtensionDryRun(
      allowed: map['allowed'] == true,
      expectedConfirmationText:
          _readOptionalString(map, 'expectedConfirmationText') ?? 'ESTENDER',
      summary: _readOptionalString(map, 'summary') ?? 'Sem resumo.',
      risks: _readStringList(map, 'risks'),
      blockers: _readStringList(map, 'blockers'),
      currentLicense: _readNullableSafeMap(map, 'currentLicense'),
      proposedChange: _readNullableSafeMap(map, 'proposedChange'),
      maxAllowedDays: _readInt(map, 'maxAllowedDays') ?? 7,
      allowedDaysMin: _readInt(range, 'min') ?? 1,
      allowedDaysMax: _readInt(range, 'max') ?? 7,
    );
  }
}

class AdminLicenseExtensionResult {
  const AdminLicenseExtensionResult({
    required this.success,
    this.message,
    this.license,
    this.proposedChange,
  });

  final bool success;
  final String? message;
  final Map<String, dynamic>? license;
  final Map<String, dynamic>? proposedChange;

  factory AdminLicenseExtensionResult.fromMap(Map<String, dynamic> map) {
    return AdminLicenseExtensionResult(
      success: map['success'] == true,
      message: _readOptionalString(map, 'message'),
      license: _readNullableSafeMap(map, 'license'),
      proposedChange: _readNullableSafeMap(map, 'proposedChange'),
    );
  }
}

class AdminLicenseStatusActionDryRun {
  const AdminLicenseStatusActionDryRun({
    required this.allowed,
    required this.expectedConfirmationText,
    required this.summary,
    required this.risks,
    required this.blockers,
    required this.currentLicense,
    required this.proposedChange,
  });

  final bool allowed;
  final String expectedConfirmationText;
  final String summary;
  final List<String> risks;
  final List<String> blockers;
  final Map<String, dynamic>? currentLicense;
  final Map<String, dynamic>? proposedChange;

  factory AdminLicenseStatusActionDryRun.fromMap(Map<String, dynamic> map) {
    return AdminLicenseStatusActionDryRun(
      allowed: map['allowed'] == true,
      expectedConfirmationText:
          _readOptionalString(map, 'expectedConfirmationText') ?? '',
      summary: _readOptionalString(map, 'summary') ?? 'Sem resumo.',
      risks: _readStringList(map, 'risks'),
      blockers: _readStringList(map, 'blockers'),
      currentLicense: _readNullableSafeMap(map, 'currentLicense'),
      proposedChange: _readNullableSafeMap(map, 'proposedChange'),
    );
  }
}

class AdminLicenseStatusActionResult {
  const AdminLicenseStatusActionResult({
    required this.success,
    this.message,
    this.license,
    this.proposedChange,
  });

  final bool success;
  final String? message;
  final Map<String, dynamic>? license;
  final Map<String, dynamic>? proposedChange;

  factory AdminLicenseStatusActionResult.fromMap(Map<String, dynamic> map) {
    return AdminLicenseStatusActionResult(
      success: map['success'] == true,
      message: _readOptionalString(map, 'message'),
      license: _readNullableSafeMap(map, 'license'),
      proposedChange: _readNullableSafeMap(map, 'proposedChange'),
    );
  }
}

class AdminBillingReconcileDryRun {
  const AdminBillingReconcileDryRun({
    required this.allowed,
    required this.expectedConfirmationText,
    required this.summary,
    required this.risks,
    required this.blockers,
    required this.currentBillingStatus,
    required this.pendingCheckoutSessions,
    required this.likelyActions,
    required this.providerCheckSummary,
  });

  final bool allowed;
  final String expectedConfirmationText;
  final String summary;
  final List<String> risks;
  final List<String> blockers;
  final Map<String, dynamic>? currentBillingStatus;
  final List<Map<String, dynamic>> pendingCheckoutSessions;
  final List<String> likelyActions;
  final Map<String, dynamic>? providerCheckSummary;

  factory AdminBillingReconcileDryRun.fromMap(Map<String, dynamic> map) {
    return AdminBillingReconcileDryRun(
      allowed: map['allowed'] == true,
      expectedConfirmationText:
          _readOptionalString(map, 'expectedConfirmationText') ?? 'RECONCILIAR',
      summary: _readOptionalString(map, 'summary') ?? 'Sem resumo.',
      risks: _readStringList(map, 'risks'),
      blockers: _readStringList(map, 'blockers'),
      currentBillingStatus: _readNullableSafeMap(map, 'currentBillingStatus'),
      pendingCheckoutSessions: _readSafeMapList(map, 'pendingCheckoutSessions'),
      likelyActions: _readStringList(map, 'likelyActions'),
      providerCheckSummary: _readNullableSafeMap(map, 'providerCheckSummary'),
    );
  }
}

class AdminBillingReconcileResult {
  const AdminBillingReconcileResult({
    required this.success,
    this.message,
    this.updatedStatus,
    required this.invoicesReconciled,
    required this.checkoutSessionsUpdated,
    required this.warnings,
  });

  final bool success;
  final String? message;
  final Map<String, dynamic>? updatedStatus;
  final int invoicesReconciled;
  final int checkoutSessionsUpdated;
  final List<String> warnings;

  factory AdminBillingReconcileResult.fromMap(Map<String, dynamic> map) {
    return AdminBillingReconcileResult(
      success: map['success'] == true,
      message: _readOptionalString(map, 'message'),
      updatedStatus: _readNullableSafeMap(map, 'updatedStatus'),
      invoicesReconciled: _readInt(map, 'invoicesReconciled') ?? 0,
      checkoutSessionsUpdated: _readInt(map, 'checkoutSessionsUpdated') ?? 0,
      warnings: _readStringList(map, 'warnings'),
    );
  }
}

class AdminBillingActionResult {
  const AdminBillingActionResult({
    this.message,
    this.providerCancelled,
    this.requiresNewCheckout,
    this.metadata,
  });

  final String? message;
  final bool? providerCancelled;
  final bool? requiresNewCheckout;
  final Map<String, dynamic>? metadata;

  factory AdminBillingActionResult.fromMap(Map<String, dynamic> map) {
    final sanitizedMetadata = sanitizeAdminBillingValue(map['metadata']);
    return AdminBillingActionResult(
      message: _readOptionalString(map, 'message'),
      providerCancelled: map['providerCancelled'] == true
          ? true
          : map['providerCancelled'] == false
          ? false
          : null,
      requiresNewCheckout: map['requiresNewCheckout'] == true,
      metadata: sanitizedMetadata is Map
          ? Map<String, dynamic>.from(sanitizedMetadata)
          : null,
    );
  }
}

List<String> _readStringList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

Map<String, dynamic>? _readNullableSafeMap(
  Map<String, dynamic> map,
  String key,
) {
  final sanitized = sanitizeAdminBillingValue(map[key]);
  if (sanitized is Map) {
    return Map<String, dynamic>.from(sanitized);
  }
  return null;
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

List<Map<String, dynamic>> _readSafeMapList(
  Map<String, dynamic> map,
  String key,
) {
  return _readList(map, key)
      .map((item) {
        final sanitized = sanitizeAdminBillingValue(item);
        return sanitized is Map
            ? Map<String, dynamic>.from(sanitized)
            : <String, dynamic>{};
      })
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
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
  return _normalized(map[key]?.toString());
}

DateTime? _readDate(Map<String, dynamic> map, String key) {
  final value = _readOptionalString(map, key);
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value);
}

int? _readInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

String? _normalized(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
