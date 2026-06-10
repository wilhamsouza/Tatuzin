class AdminTenantDeletionQuery {
  const AdminTenantDeletionQuery({this.companyId, this.status});

  final String? companyId;
  final String? status;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (_normalized(companyId) case final value?) 'companyId': value,
      if (_normalized(status) case final value?) 'status': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminTenantDeletionQuery &&
        other.companyId == companyId &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(companyId, status);
}

class AdminTenantDeletionRequestsSnapshot {
  const AdminTenantDeletionRequestsSnapshot({
    required this.items,
    required this.auditEventId,
  });

  final List<AdminTenantDeletionRequest> items;
  final String? auditEventId;

  factory AdminTenantDeletionRequestsSnapshot.fromMap(
    Map<String, dynamic> map,
  ) {
    final requests = map['requests'];
    return AdminTenantDeletionRequestsSnapshot(
      items: requests is List<dynamic>
          ? requests
                .whereType<Map<String, dynamic>>()
                .map(AdminTenantDeletionRequest.fromMap)
                .toList(growable: false)
          : const <AdminTenantDeletionRequest>[],
      auditEventId: _readOptionalString(map, 'auditEventId'),
    );
  }
}

class AdminTenantDeletionMutationResult {
  const AdminTenantDeletionMutationResult({
    required this.ok,
    required this.code,
    required this.message,
    required this.auditEventId,
    required this.request,
  });

  final bool ok;
  final String code;
  final String message;
  final String? auditEventId;
  final AdminTenantDeletionRequest? request;

  factory AdminTenantDeletionMutationResult.fromMap(Map<String, dynamic> map) {
    final request = map['request'];
    return AdminTenantDeletionMutationResult(
      ok: map['ok'] == true,
      code: _readString(map, 'code', fallback: 'TENANT_DELETION_UNKNOWN'),
      message: _readString(map, 'message', fallback: 'Operacao registrada.'),
      auditEventId: _readOptionalString(map, 'auditEventId'),
      request: request is Map<String, dynamic>
          ? AdminTenantDeletionRequest.fromMap(request)
          : null,
    );
  }
}

class AdminTenantDeletionRequest {
  const AdminTenantDeletionRequest({
    required this.requestId,
    required this.company,
    required this.status,
    required this.identityStatus,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.latestAuditEventId,
    required this.latestAction,
    required this.reason,
    required this.requester,
    required this.dryRunSummary,
  });

  final String requestId;
  final AdminTenantDeletionCompany? company;
  final String status;
  final String identityStatus;
  final String source;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String latestAuditEventId;
  final String latestAction;
  final String? reason;
  final AdminTenantDeletionRequester requester;
  final AdminTenantDeletionDryRunSummary? dryRunSummary;

  factory AdminTenantDeletionRequest.fromMap(Map<String, dynamic> map) {
    final company = map['company'];
    final requester = map['requester'];
    final dryRunSummary = map['dryRunSummary'];
    return AdminTenantDeletionRequest(
      requestId: _readString(map, 'requestId'),
      company: company is Map<String, dynamic>
          ? AdminTenantDeletionCompany.fromMap(company)
          : null,
      status: _readString(map, 'status', fallback: 'REQUESTED'),
      identityStatus: _readString(
        map,
        'identityStatus',
        fallback: 'NOT_STARTED',
      ),
      source: _readString(map, 'source', fallback: 'admin_web'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      latestAuditEventId: _readString(map, 'latestAuditEventId'),
      latestAction: _readString(map, 'latestAction'),
      reason: _readOptionalString(map, 'reason'),
      requester: requester is Map<String, dynamic>
          ? AdminTenantDeletionRequester.fromMap(requester)
          : const AdminTenantDeletionRequester(
              name: null,
              email: null,
              channel: null,
            ),
      dryRunSummary: dryRunSummary is Map<String, dynamic>
          ? AdminTenantDeletionDryRunSummary.fromMap(dryRunSummary)
          : null,
    );
  }
}

class AdminTenantDeletionRequester {
  const AdminTenantDeletionRequester({
    required this.name,
    required this.email,
    required this.channel,
  });

  final String? name;
  final String? email;
  final String? channel;

  factory AdminTenantDeletionRequester.fromMap(Map<String, dynamic> map) {
    return AdminTenantDeletionRequester(
      name: _readOptionalString(map, 'name'),
      email: _readOptionalString(map, 'email'),
      channel: _readOptionalString(map, 'channel'),
    );
  }
}

class AdminTenantDeletionDryRunSummary {
  const AdminTenantDeletionDryRunSummary({
    required this.categories,
    required this.blockers,
  });

  final int categories;
  final int blockers;

  factory AdminTenantDeletionDryRunSummary.fromMap(Map<String, dynamic> map) {
    return AdminTenantDeletionDryRunSummary(
      categories: _readOptionalInt(map, 'categories') ?? 0,
      blockers: _readOptionalInt(map, 'blockers') ?? 0,
    );
  }
}

class AdminTenantDeletionCompany {
  const AdminTenantDeletionCompany({
    required this.id,
    required this.name,
    required this.legalName,
    required this.slug,
    required this.documentNumber,
    required this.isActive,
    required this.license,
  });

  final String id;
  final String name;
  final String legalName;
  final String slug;
  final String? documentNumber;
  final bool isActive;
  final AdminTenantDeletionLicense? license;

  factory AdminTenantDeletionCompany.fromMap(Map<String, dynamic> map) {
    final license = map['license'];
    return AdminTenantDeletionCompany(
      id: _readString(map, 'id'),
      name: _readString(map, 'name', fallback: 'Empresa'),
      legalName: _readString(map, 'legalName', fallback: 'Empresa'),
      slug: _readString(map, 'slug', fallback: ''),
      documentNumber: _readOptionalString(map, 'documentNumber'),
      isActive: map['isActive'] == true,
      license: license is Map<String, dynamic>
          ? AdminTenantDeletionLicense.fromMap(license)
          : null,
    );
  }
}

class AdminTenantDeletionLicense {
  const AdminTenantDeletionLicense({
    required this.status,
    required this.plan,
    required this.syncEnabled,
    required this.billingProvider,
    required this.hasProviderSubscription,
    required this.cancelAtPeriodEnd,
    required this.billingSubscriptionStatus,
  });

  final String status;
  final String plan;
  final bool syncEnabled;
  final String? billingProvider;
  final bool hasProviderSubscription;
  final bool cancelAtPeriodEnd;
  final String? billingSubscriptionStatus;

  factory AdminTenantDeletionLicense.fromMap(Map<String, dynamic> map) {
    return AdminTenantDeletionLicense(
      status: _readString(map, 'status', fallback: 'unknown'),
      plan: _readString(map, 'plan', fallback: 'unknown'),
      syncEnabled: map['syncEnabled'] == true,
      billingProvider: _readOptionalString(map, 'billingProvider'),
      hasProviderSubscription: map['hasProviderSubscription'] == true,
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
      billingSubscriptionStatus: _readOptionalString(
        map,
        'billingSubscriptionStatus',
      ),
    );
  }
}

class AdminTenantDeletionDryRunResponse {
  const AdminTenantDeletionDryRunResponse({
    required this.ok,
    required this.code,
    required this.message,
    required this.auditEventId,
    required this.dryRun,
  });

  final bool ok;
  final String code;
  final String message;
  final String? auditEventId;
  final AdminTenantDeletionDryRun dryRun;

  factory AdminTenantDeletionDryRunResponse.fromMap(Map<String, dynamic> map) {
    final dryRun = map['dryRun'];
    if (dryRun is! Map<String, dynamic>) {
      throw const FormatException('Dry-run ausente no payload administrativo.');
    }
    return AdminTenantDeletionDryRunResponse(
      ok: map['ok'] == true,
      code: _readString(map, 'code', fallback: 'TENANT_DELETION_DRY_RUN_READY'),
      message: _readString(map, 'message', fallback: 'Dry-run gerado.'),
      auditEventId: _readOptionalString(map, 'auditEventId'),
      dryRun: AdminTenantDeletionDryRun.fromMap(dryRun),
    );
  }
}

class AdminTenantDeletionDryRun {
  const AdminTenantDeletionDryRun({
    required this.company,
    required this.generatedAt,
    required this.persistenceMode,
    required this.categories,
    required this.blockers,
    required this.notes,
  });

  final AdminTenantDeletionCompany company;
  final DateTime? generatedAt;
  final String persistenceMode;
  final List<AdminTenantDeletionInventoryCategory> categories;
  final List<AdminTenantDeletionBlocker> blockers;
  final List<String> notes;

  factory AdminTenantDeletionDryRun.fromMap(Map<String, dynamic> map) {
    return AdminTenantDeletionDryRun(
      company: AdminTenantDeletionCompany.fromMap(_readMap(map, 'company')),
      generatedAt: _readOptionalDateTime(map, 'generatedAt'),
      persistenceMode: _readString(
        map,
        'persistenceMode',
        fallback: 'tenant_deletion_request',
      ),
      categories: (map['categories'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminTenantDeletionInventoryCategory.fromMap)
          .toList(growable: false),
      blockers: (map['blockers'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminTenantDeletionBlocker.fromMap)
          .toList(growable: false),
      notes: _readStringList(map['notes']),
    );
  }
}

class AdminTenantDeletionInventoryCategory {
  const AdminTenantDeletionInventoryCategory({
    required this.key,
    required this.label,
    required this.count,
    required this.recommendedHandling,
    required this.retentionReason,
  });

  final String key;
  final String label;
  final int count;
  final String recommendedHandling;
  final String? retentionReason;

  factory AdminTenantDeletionInventoryCategory.fromMap(
    Map<String, dynamic> map,
  ) {
    return AdminTenantDeletionInventoryCategory(
      key: _readString(map, 'key'),
      label: _readString(map, 'label'),
      count: _readOptionalInt(map, 'count') ?? 0,
      recommendedHandling: _readString(
        map,
        'recommendedHandling',
        fallback: 'review_required',
      ),
      retentionReason: _readOptionalString(map, 'retentionReason'),
    );
  }
}

class AdminTenantDeletionBlocker {
  const AdminTenantDeletionBlocker({
    required this.key,
    required this.severity,
    required this.message,
    required this.count,
  });

  final String key;
  final String severity;
  final String message;
  final int? count;

  factory AdminTenantDeletionBlocker.fromMap(Map<String, dynamic> map) {
    return AdminTenantDeletionBlocker(
      key: _readString(map, 'key'),
      severity: _readString(map, 'severity', fallback: 'warning'),
      message: _readString(map, 'message'),
      count: _readOptionalInt(map, 'count'),
    );
  }
}

String? _normalized(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String && value.trim().isNotEmpty) {
    return int.tryParse(value.trim());
  }
  return null;
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
