class AdminSyncCenterCompaniesQuery {
  const AdminSyncCenterCompaniesQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.status = 'requires_review',
  });

  final int page;
  final int pageSize;
  final String? search;
  final String? status;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(status) case final value?) 'status': value,
      if (_normalized(search) case final value?) 'search': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminSyncCenterCompaniesQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(page, pageSize, search, status);
}

class AdminSyncCenterEventsQuery {
  const AdminSyncCenterEventsQuery({
    required this.companyId,
    this.page = 1,
    this.pageSize = 20,
    this.status,
    this.entity,
    this.operation,
    this.feature,
    this.startDate,
    this.endDate,
  });

  final String companyId;
  final int page;
  final int pageSize;
  final String? status;
  final String? entity;
  final String? operation;
  final String? feature;
  final DateTime? startDate;
  final DateTime? endDate;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(status) case final value?) 'status': value,
      if (_normalized(entity) case final value?) 'entity': value,
      if (_normalized(operation) case final value?) 'operation': value,
      if (_normalized(feature) case final value?) 'feature': value,
      if (startDate != null) 'startDate': startDate!.toIso8601String(),
      if (endDate != null) 'endDate': endDate!.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminSyncCenterEventsQuery &&
        other.companyId == companyId &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.status == status &&
        other.entity == entity &&
        other.operation == operation &&
        other.feature == feature &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode => Object.hash(
    companyId,
    page,
    pageSize,
    status,
    entity,
    operation,
    feature,
    startDate,
    endDate,
  );
}

class AdminSyncCenterConflictsQuery {
  const AdminSyncCenterConflictsQuery({
    required this.companyId,
    this.page = 1,
    this.pageSize = 20,
    this.status,
    this.code,
    this.entity,
  });

  final String companyId;
  final int page;
  final int pageSize;
  final String? status;
  final String? code;
  final String? entity;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(status) case final value?) 'status': value,
      if (_normalized(code) case final value?) 'code': value,
      if (_normalized(entity) case final value?) 'entity': value,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminSyncCenterConflictsQuery &&
        other.companyId == companyId &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.status == status &&
        other.code == code &&
        other.entity == entity;
  }

  @override
  int get hashCode =>
      Object.hash(companyId, page, pageSize, status, code, entity);
}

class AdminSyncCenterDetailKey {
  const AdminSyncCenterDetailKey({
    required this.companyId,
    required this.targetId,
  });

  final String companyId;
  final String targetId;

  @override
  bool operator ==(Object other) {
    return other is AdminSyncCenterDetailKey &&
        other.companyId == companyId &&
        other.targetId == targetId;
  }

  @override
  int get hashCode => Object.hash(companyId, targetId);
}

class AdminSyncCenterCompany {
  const AdminSyncCenterCompany({
    required this.companyId,
    required this.companyName,
    required this.plan,
    required this.syncStatus,
    required this.currentVersion,
    required this.serverFirstSnapshotVersion,
    required this.acceptedCount,
    required this.duplicateCount,
    required this.pendingCount,
    required this.conflictCount,
    required this.failedCount,
    required this.openConflictCount,
    required this.incidentCount,
    required this.lastEventAt,
    required this.lastIncidentAt,
    required this.requiresReview,
  });

  final String companyId;
  final String companyName;
  final String? plan;
  final String syncStatus;
  final String currentVersion;
  final String serverFirstSnapshotVersion;
  final int acceptedCount;
  final int duplicateCount;
  final int pendingCount;
  final int conflictCount;
  final int failedCount;
  final int openConflictCount;
  final int incidentCount;
  final DateTime? lastEventAt;
  final DateTime? lastIncidentAt;
  final bool requiresReview;

  factory AdminSyncCenterCompany.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterCompany(
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      plan: _readOptionalString(map, 'plan'),
      syncStatus: _readString(map, 'syncStatus', fallback: 'healthy'),
      currentVersion: _readString(map, 'currentVersion', fallback: '0'),
      serverFirstSnapshotVersion: _readString(
        map,
        'serverFirstSnapshotVersion',
        fallback: '0',
      ),
      acceptedCount: _readOptionalInt(map, 'acceptedCount') ?? 0,
      duplicateCount: _readOptionalInt(map, 'duplicateCount') ?? 0,
      pendingCount: _readOptionalInt(map, 'pendingCount') ?? 0,
      conflictCount: _readOptionalInt(map, 'conflictCount') ?? 0,
      failedCount: _readOptionalInt(map, 'failedCount') ?? 0,
      openConflictCount: _readOptionalInt(map, 'openConflictCount') ?? 0,
      incidentCount: _readOptionalInt(map, 'incidentCount') ?? 0,
      lastEventAt: _readOptionalDateTime(map, 'lastEventAt'),
      lastIncidentAt: _readOptionalDateTime(map, 'lastIncidentAt'),
      requiresReview: map['requiresReview'] == true,
    );
  }
}

class AdminSyncCenterCompanySummary {
  const AdminSyncCenterCompanySummary({
    required this.company,
    required this.syncState,
    required this.eventStatusCounts,
    required this.entityOperationStatusCounts,
    required this.conflictCounts,
    required this.incidentCounts,
    required this.latestEvents,
    required this.latestConflicts,
    required this.latestIncidents,
    required this.recommendation,
    required this.requiresReview,
  });

  final AdminSyncCenterCompanyRef company;
  final AdminSyncCenterState syncState;
  final AdminSyncCenterEventStatusCounts eventStatusCounts;
  final List<AdminSyncCenterEntityOperationStatusCount>
  entityOperationStatusCounts;
  final List<AdminSyncCenterConflictCount> conflictCounts;
  final List<AdminSyncCenterIncidentCount> incidentCounts;
  final List<AdminSyncCenterEvent> latestEvents;
  final List<AdminSyncCenterConflict> latestConflicts;
  final List<AdminSyncCenterIncident> latestIncidents;
  final String recommendation;
  final bool requiresReview;

  factory AdminSyncCenterCompanySummary.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterCompanySummary(
      company: AdminSyncCenterCompanyRef.fromMap(_readMap(map, 'company')),
      syncState: AdminSyncCenterState.fromMap(_readMap(map, 'syncState')),
      eventStatusCounts: AdminSyncCenterEventStatusCounts.fromMap(
        _readMap(map, 'eventStatusCounts'),
      ),
      entityOperationStatusCounts:
          _readMapList(map['entityOperationStatusCounts'])
              .map(AdminSyncCenterEntityOperationStatusCount.fromMap)
              .toList(growable: false),
      conflictCounts: _readMapList(
        map['conflictCounts'],
      ).map(AdminSyncCenterConflictCount.fromMap).toList(growable: false),
      incidentCounts: _readMapList(
        map['incidentCounts'],
      ).map(AdminSyncCenterIncidentCount.fromMap).toList(growable: false),
      latestEvents: _readMapList(
        map['latestEvents'],
      ).map(AdminSyncCenterEvent.fromMap).toList(growable: false),
      latestConflicts: _readMapList(
        map['latestConflicts'],
      ).map(AdminSyncCenterConflict.fromMap).toList(growable: false),
      latestIncidents: _readMapList(
        map['latestIncidents'],
      ).map(AdminSyncCenterIncident.fromMap).toList(growable: false),
      recommendation: _readString(map, 'recommendation', fallback: ''),
      requiresReview: map['requiresReview'] == true,
    );
  }
}

class AdminSyncCenterCompanyRef {
  const AdminSyncCenterCompanyRef({
    required this.companyId,
    required this.companyName,
    required this.plan,
  });

  final String companyId;
  final String companyName;
  final String? plan;

  factory AdminSyncCenterCompanyRef.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterCompanyRef(
      companyId: _readString(map, 'companyId'),
      companyName: _readString(map, 'companyName'),
      plan: _readOptionalString(map, 'plan'),
    );
  }
}

class AdminSyncCenterState {
  const AdminSyncCenterState({
    required this.currentVersion,
    required this.serverFirstSnapshotVersion,
    required this.updatedAt,
  });

  final String currentVersion;
  final String serverFirstSnapshotVersion;
  final DateTime? updatedAt;

  factory AdminSyncCenterState.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterState(
      currentVersion: _readString(map, 'currentVersion', fallback: '0'),
      serverFirstSnapshotVersion: _readString(
        map,
        'serverFirstSnapshotVersion',
        fallback: '0',
      ),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
    );
  }
}

class AdminSyncCenterEventStatusCounts {
  const AdminSyncCenterEventStatusCounts({
    required this.pending,
    required this.accepted,
    required this.duplicate,
    required this.rejected,
    required this.conflict,
    required this.failed,
  });

  final int pending;
  final int accepted;
  final int duplicate;
  final int rejected;
  final int conflict;
  final int failed;

  factory AdminSyncCenterEventStatusCounts.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterEventStatusCounts(
      pending: _readOptionalInt(map, 'pending') ?? 0,
      accepted: _readOptionalInt(map, 'accepted') ?? 0,
      duplicate: _readOptionalInt(map, 'duplicate') ?? 0,
      rejected: _readOptionalInt(map, 'rejected') ?? 0,
      conflict: _readOptionalInt(map, 'conflict') ?? 0,
      failed: _readOptionalInt(map, 'failed') ?? 0,
    );
  }
}

class AdminSyncCenterEntityOperationStatusCount {
  const AdminSyncCenterEntityOperationStatusCount({
    required this.entity,
    required this.operation,
    required this.status,
    required this.count,
  });

  final String entity;
  final String operation;
  final String status;
  final int count;

  factory AdminSyncCenterEntityOperationStatusCount.fromMap(
    Map<String, dynamic> map,
  ) {
    return AdminSyncCenterEntityOperationStatusCount(
      entity: _readString(map, 'entity'),
      operation: _readString(map, 'operation'),
      status: _readString(map, 'status'),
      count: _readOptionalInt(map, 'count') ?? 0,
    );
  }
}

class AdminSyncCenterConflictCount {
  const AdminSyncCenterConflictCount({
    required this.code,
    required this.entity,
    required this.status,
    required this.count,
  });

  final String code;
  final String entity;
  final String status;
  final int count;

  factory AdminSyncCenterConflictCount.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterConflictCount(
      code: _readString(map, 'code'),
      entity: _readString(map, 'entity'),
      status: _readString(map, 'status'),
      count: _readOptionalInt(map, 'count') ?? 0,
    );
  }
}

class AdminSyncCenterIncidentCount {
  const AdminSyncCenterIncidentCount({
    required this.severity,
    required this.code,
    required this.count,
  });

  final String severity;
  final String code;
  final int count;

  factory AdminSyncCenterIncidentCount.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterIncidentCount(
      severity: _readString(map, 'severity'),
      code: _readString(map, 'code'),
      count: _readOptionalInt(map, 'count') ?? 0,
    );
  }
}

class AdminSyncCenterEvent {
  const AdminSyncCenterEvent({
    required this.id,
    required this.eventId,
    required this.feature,
    required this.entity,
    required this.operation,
    required this.entityLocalId,
    required this.entityServerId,
    required this.status,
    required this.serverVersion,
    required this.rejectionCode,
    required this.rejectionMessage,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    required this.materializedAt,
    required this.relatedConflictId,
    required this.classification,
    required this.recommendedAction,
    required this.canReprocess,
    required this.canArchive,
    required this.safePayloadPreview,
    required this.payload,
  });

  final String id;
  final String eventId;
  final String feature;
  final String entity;
  final String operation;
  final String? entityLocalId;
  final String? entityServerId;
  final String status;
  final String? serverVersion;
  final String? rejectionCode;
  final String? rejectionMessage;
  final DateTime? occurredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? materializedAt;
  final String? relatedConflictId;
  final String classification;
  final String recommendedAction;
  final bool canReprocess;
  final bool canArchive;
  final Map<String, dynamic> safePayloadPreview;
  final Map<String, dynamic> payload;

  factory AdminSyncCenterEvent.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterEvent(
      id: _readString(map, 'id'),
      eventId: _readString(map, 'eventId'),
      feature: _readString(map, 'feature'),
      entity: _readString(map, 'entity'),
      operation: _readString(map, 'operation'),
      entityLocalId: _readOptionalString(map, 'entityLocalId'),
      entityServerId: _readOptionalString(map, 'entityServerId'),
      status: _readString(map, 'status'),
      serverVersion: _readOptionalString(map, 'serverVersion'),
      rejectionCode: _readOptionalString(map, 'rejectionCode'),
      rejectionMessage: _readOptionalString(map, 'rejectionMessage'),
      occurredAt: _readOptionalDateTime(map, 'occurredAt'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      materializedAt: _readOptionalDateTime(map, 'materializedAt'),
      relatedConflictId: _readOptionalString(map, 'relatedConflictId'),
      classification: _readString(map, 'classification', fallback: 'UNKNOWN'),
      recommendedAction: _readString(
        map,
        'recommendedAction',
        fallback: 'CONTACT_SUPPORT',
      ),
      canReprocess: map['canReprocess'] == true,
      canArchive: map['canArchive'] == true,
      safePayloadPreview: _readOptionalMap(map, 'safePayloadPreview'),
      payload: _readOptionalMap(map, 'payload'),
    );
  }
}

class AdminSyncCenterConflict {
  const AdminSyncCenterConflict({
    required this.conflictId,
    required this.syncEventId,
    required this.entity,
    required this.entityLocalId,
    required this.entityServerId,
    required this.code,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.resolvedAt,
    required this.classification,
    required this.recommendedAction,
    required this.canReprocess,
    required this.canArchive,
    required this.canCreateManualStockAdjustment,
    required this.safePayloadPreview,
    required this.payload,
    required this.resolution,
  });

  final String conflictId;
  final String syncEventId;
  final String entity;
  final String? entityLocalId;
  final String? entityServerId;
  final String code;
  final String message;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final String classification;
  final String recommendedAction;
  final bool canReprocess;
  final bool canArchive;
  final bool canCreateManualStockAdjustment;
  final Map<String, dynamic> safePayloadPreview;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> resolution;

  factory AdminSyncCenterConflict.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterConflict(
      conflictId: _readString(map, 'conflictId'),
      syncEventId: _readString(map, 'syncEventId'),
      entity: _readString(map, 'entity'),
      entityLocalId: _readOptionalString(map, 'entityLocalId'),
      entityServerId: _readOptionalString(map, 'entityServerId'),
      code: _readString(map, 'code'),
      message: _readString(map, 'message'),
      status: _readString(map, 'status'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      resolvedAt: _readOptionalDateTime(map, 'resolvedAt'),
      classification: _readString(map, 'classification', fallback: 'UNKNOWN'),
      recommendedAction: _readString(
        map,
        'recommendedAction',
        fallback: 'CONTACT_SUPPORT',
      ),
      canReprocess: map['canReprocess'] == true,
      canArchive: map['canArchive'] == true,
      canCreateManualStockAdjustment:
          map['canCreateManualStockAdjustment'] == true,
      safePayloadPreview: _readOptionalMap(map, 'safePayloadPreview'),
      payload: _readOptionalMap(map, 'payload'),
      resolution: _readOptionalMap(map, 'resolution'),
    );
  }
}

class AdminSyncCenterIncident {
  const AdminSyncCenterIncident({
    required this.id,
    required this.code,
    required this.message,
    required this.severity,
    required this.details,
    required this.createdAt,
  });

  final String id;
  final String code;
  final String message;
  final String severity;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  factory AdminSyncCenterIncident.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterIncident(
      id: _readString(map, 'id'),
      code: _readString(map, 'code'),
      message: _readString(map, 'message'),
      severity: _readString(map, 'severity'),
      details: _readOptionalMap(map, 'details'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
    );
  }
}

class AdminSyncCenterEventDetail {
  const AdminSyncCenterEventDetail({
    required this.event,
    required this.conflict,
    required this.incidents,
    required this.classification,
    required this.recommendedAction,
    required this.canReprocess,
    required this.canArchive,
    required this.risks,
    required this.blockers,
    required this.message,
  });

  final AdminSyncCenterEvent event;
  final AdminSyncCenterConflict? conflict;
  final List<AdminSyncCenterIncident> incidents;
  final String classification;
  final String recommendedAction;
  final bool canReprocess;
  final bool canArchive;
  final List<String> risks;
  final List<String> blockers;
  final String message;

  factory AdminSyncCenterEventDetail.fromMap(Map<String, dynamic> map) {
    final conflict = map['conflict'];
    return AdminSyncCenterEventDetail(
      event: AdminSyncCenterEvent.fromMap(_readMap(map, 'event')),
      conflict: conflict is Map<String, dynamic>
          ? AdminSyncCenterConflict.fromMap(conflict)
          : null,
      incidents: _readMapList(
        map['incidents'],
      ).map(AdminSyncCenterIncident.fromMap).toList(growable: false),
      classification: _readString(map, 'classification', fallback: 'UNKNOWN'),
      recommendedAction: _readString(
        map,
        'recommendedAction',
        fallback: 'CONTACT_SUPPORT',
      ),
      canReprocess: map['canReprocess'] == true,
      canArchive: map['canArchive'] == true,
      risks: _readStringList(map['risks']),
      blockers: _readStringList(map['blockers']),
      message: _readString(map, 'message', fallback: ''),
    );
  }
}

class AdminSyncCenterConflictDetail {
  const AdminSyncCenterConflictDetail({
    required this.conflict,
    required this.event,
    required this.incidents,
    required this.classification,
    required this.recommendedAction,
    required this.canReprocess,
    required this.canArchive,
    required this.canCreateManualStockAdjustment,
    required this.risks,
    required this.blockers,
    required this.message,
  });

  final AdminSyncCenterConflict conflict;
  final AdminSyncCenterEvent event;
  final List<AdminSyncCenterIncident> incidents;
  final String classification;
  final String recommendedAction;
  final bool canReprocess;
  final bool canArchive;
  final bool canCreateManualStockAdjustment;
  final List<String> risks;
  final List<String> blockers;
  final String message;

  factory AdminSyncCenterConflictDetail.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterConflictDetail(
      conflict: AdminSyncCenterConflict.fromMap(_readMap(map, 'conflict')),
      event: AdminSyncCenterEvent.fromMap(_readMap(map, 'event')),
      incidents: _readMapList(
        map['incidents'],
      ).map(AdminSyncCenterIncident.fromMap).toList(growable: false),
      classification: _readString(map, 'classification', fallback: 'UNKNOWN'),
      recommendedAction: _readString(
        map,
        'recommendedAction',
        fallback: 'CONTACT_SUPPORT',
      ),
      canReprocess: map['canReprocess'] == true,
      canArchive: map['canArchive'] == true,
      canCreateManualStockAdjustment:
          map['canCreateManualStockAdjustment'] == true,
      risks: _readStringList(map['risks']),
      blockers: _readStringList(map['blockers']),
      message: _readString(map, 'message', fallback: ''),
    );
  }
}

class AdminSyncCenterDryRunResult {
  const AdminSyncCenterDryRunResult({
    required this.wouldReprocess,
    required this.wouldArchive,
    required this.canCreateManualStockAdjustment,
    required this.classification,
    required this.expectedAction,
    required this.expectedConfirmationText,
    required this.blockers,
    required this.risks,
    required this.message,
  });

  final bool wouldReprocess;
  final bool wouldArchive;
  final bool canCreateManualStockAdjustment;
  final String classification;
  final String? expectedAction;
  final String? expectedConfirmationText;
  final List<String> blockers;
  final List<String> risks;
  final String message;

  factory AdminSyncCenterDryRunResult.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterDryRunResult(
      wouldReprocess: map['wouldReprocess'] == true,
      wouldArchive: map['wouldArchive'] == true,
      canCreateManualStockAdjustment:
          map['canCreateManualStockAdjustment'] == true,
      classification: _readString(map, 'classification', fallback: 'UNKNOWN'),
      expectedAction: _readOptionalString(map, 'expectedAction'),
      expectedConfirmationText: _readOptionalString(
        map,
        'expectedConfirmationText',
      ),
      blockers: _readStringList(map['blockers']),
      risks: _readStringList(map['risks']),
      message: _readString(map, 'message', fallback: ''),
    );
  }
}

class AdminSyncCenterActionResult {
  const AdminSyncCenterActionResult({required this.ok, required this.message});

  final bool ok;
  final String? message;

  factory AdminSyncCenterActionResult.fromMap(Map<String, dynamic> map) {
    return AdminSyncCenterActionResult(
      ok: map['ok'] == true,
      message: _readOptionalString(map, 'message'),
    );
  }
}

class AdminSyncSupportDevice {
  const AdminSyncSupportDevice({
    required this.id,
    required this.maskedDeviceId,
    required this.clientInstanceId,
    required this.deviceLabel,
    required this.platform,
    required this.appVersion,
    required this.status,
    required this.deviceStatus,
    required this.lastSeenAt,
    required this.lastPushAt,
    required this.lastPullAt,
    required this.user,
    required this.diagnostic,
    required this.remoteConflictCounts,
  });

  final String id;
  final String maskedDeviceId;
  final String clientInstanceId;
  final String? deviceLabel;
  final String? platform;
  final String? appVersion;
  final String status;
  final String deviceStatus;
  final DateTime? lastSeenAt;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final AdminSyncSupportUser? user;
  final AdminSyncSupportDiagnosticSummary? diagnostic;
  final Map<String, dynamic> remoteConflictCounts;

  int get pendingCount => diagnostic?.pendingCount ?? 0;
  int get failedCount => diagnostic?.failedCount ?? 0;
  int get openConflictCount => diagnostic?.openConflictCount ?? 0;
  String get title => deviceLabel?.trim().isNotEmpty == true
      ? deviceLabel!.trim()
      : 'Dispositivo $maskedDeviceId';

  factory AdminSyncSupportDevice.fromMap(Map<String, dynamic> map) {
    final user = map['user'];
    final diagnostic = map['diagnostic'];
    return AdminSyncSupportDevice(
      id: _readString(map, 'id'),
      maskedDeviceId: _readString(map, 'maskedDeviceId'),
      clientInstanceId: _readString(map, 'clientInstanceId'),
      deviceLabel: _readOptionalString(map, 'deviceLabel'),
      platform: _readOptionalString(map, 'platform'),
      appVersion: _readOptionalString(map, 'appVersion'),
      status: _readString(map, 'status', fallback: 'cloud_ok'),
      deviceStatus: _readString(map, 'deviceStatus', fallback: 'unknown'),
      lastSeenAt: _readOptionalDateTime(map, 'lastSeenAt'),
      lastPushAt: _readOptionalDateTime(map, 'lastPushAt'),
      lastPullAt: _readOptionalDateTime(map, 'lastPullAt'),
      user: user is Map<String, dynamic>
          ? AdminSyncSupportUser.fromMap(user)
          : null,
      diagnostic: diagnostic is Map<String, dynamic>
          ? AdminSyncSupportDiagnosticSummary.fromMap(diagnostic)
          : null,
      remoteConflictCounts: _readOptionalMap(map, 'remoteConflictCounts'),
    );
  }
}

class AdminSyncSupportUser {
  const AdminSyncSupportUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory AdminSyncSupportUser.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportUser(
      id: _readString(map, 'id'),
      name: _readString(map, 'name'),
      email: _readString(map, 'email'),
    );
  }
}

class AdminSyncSupportDiagnosticSummary {
  const AdminSyncSupportDiagnosticSummary({
    required this.pendingCount,
    required this.failedCount,
    required this.openConflictCount,
    required this.resolvedConflictCount,
    required this.ignoredConflictCount,
    required this.lastLocalError,
    required this.reportedAt,
  });

  final int pendingCount;
  final int failedCount;
  final int openConflictCount;
  final int resolvedConflictCount;
  final int ignoredConflictCount;
  final String? lastLocalError;
  final DateTime? reportedAt;

  factory AdminSyncSupportDiagnosticSummary.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportDiagnosticSummary(
      pendingCount: _readOptionalInt(map, 'pendingCount') ?? 0,
      failedCount: _readOptionalInt(map, 'failedCount') ?? 0,
      openConflictCount: _readOptionalInt(map, 'openConflictCount') ?? 0,
      resolvedConflictCount:
          _readOptionalInt(map, 'resolvedConflictCount') ?? 0,
      ignoredConflictCount: _readOptionalInt(map, 'ignoredConflictCount') ?? 0,
      lastLocalError: _readOptionalString(map, 'lastLocalError'),
      reportedAt: _readOptionalDateTime(map, 'reportedAt'),
    );
  }
}

class AdminSyncSupportDeviceDetail {
  const AdminSyncSupportDeviceDetail({
    required this.device,
    required this.diagnostic,
    required this.failedEvents,
    required this.openConflicts,
    required this.resolvedConflicts,
    required this.commands,
  });

  final AdminSyncSupportDevice device;
  final AdminSyncSupportDiagnostic? diagnostic;
  final List<AdminSyncSupportFailedEvent> failedEvents;
  final List<AdminSyncSupportConflict> openConflicts;
  final List<AdminSyncSupportConflict> resolvedConflicts;
  final List<AdminSyncSupportCommand> commands;

  factory AdminSyncSupportDeviceDetail.fromMap(Map<String, dynamic> map) {
    final diagnostic = map['diagnostic'];
    return AdminSyncSupportDeviceDetail(
      device: AdminSyncSupportDevice.fromMap(_readMap(map, 'device')),
      diagnostic: diagnostic is Map<String, dynamic>
          ? AdminSyncSupportDiagnostic.fromMap(diagnostic)
          : null,
      failedEvents: _readMapList(
        map['failedEvents'],
      ).map(AdminSyncSupportFailedEvent.fromMap).toList(growable: false),
      openConflicts: _readMapList(
        map['openConflicts'],
      ).map(AdminSyncSupportConflict.fromMap).toList(growable: false),
      resolvedConflicts: _readMapList(
        map['resolvedConflicts'],
      ).map(AdminSyncSupportConflict.fromMap).toList(growable: false),
      commands: _readMapList(
        map['commands'],
      ).map(AdminSyncSupportCommand.fromMap).toList(growable: false),
    );
  }
}

class AdminSyncSupportDiagnostic {
  const AdminSyncSupportDiagnostic({
    required this.id,
    required this.pendingCount,
    required this.failedCount,
    required this.openConflictCount,
    required this.resolvedConflictCount,
    required this.ignoredConflictCount,
    required this.lastLocalError,
    required this.lastLocalErrorCode,
    required this.lastLocalErrorEntity,
    required this.appVersion,
    required this.platform,
    required this.localSchemaVersion,
    required this.lastPushAt,
    required this.lastPullAt,
    required this.lastSuccessfulSyncAt,
    required this.safeDetails,
    required this.reportedAt,
  });

  final String id;
  final int pendingCount;
  final int failedCount;
  final int openConflictCount;
  final int resolvedConflictCount;
  final int ignoredConflictCount;
  final String? lastLocalError;
  final String? lastLocalErrorCode;
  final String? lastLocalErrorEntity;
  final String? appVersion;
  final String? platform;
  final String? localSchemaVersion;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final DateTime? lastSuccessfulSyncAt;
  final Map<String, dynamic> safeDetails;
  final DateTime? reportedAt;

  factory AdminSyncSupportDiagnostic.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportDiagnostic(
      id: _readString(map, 'id'),
      pendingCount: _readOptionalInt(map, 'pendingCount') ?? 0,
      failedCount: _readOptionalInt(map, 'failedCount') ?? 0,
      openConflictCount: _readOptionalInt(map, 'openConflictCount') ?? 0,
      resolvedConflictCount:
          _readOptionalInt(map, 'resolvedConflictCount') ?? 0,
      ignoredConflictCount: _readOptionalInt(map, 'ignoredConflictCount') ?? 0,
      lastLocalError: _readOptionalString(map, 'lastLocalError'),
      lastLocalErrorCode: _readOptionalString(map, 'lastLocalErrorCode'),
      lastLocalErrorEntity: _readOptionalString(map, 'lastLocalErrorEntity'),
      appVersion: _readOptionalString(map, 'appVersion'),
      platform: _readOptionalString(map, 'platform'),
      localSchemaVersion: _readOptionalString(map, 'localSchemaVersion'),
      lastPushAt: _readOptionalDateTime(map, 'lastPushAt'),
      lastPullAt: _readOptionalDateTime(map, 'lastPullAt'),
      lastSuccessfulSyncAt: _readOptionalDateTime(map, 'lastSuccessfulSyncAt'),
      safeDetails: _readOptionalMap(map, 'safeDetails'),
      reportedAt: _readOptionalDateTime(map, 'reportedAt'),
    );
  }
}

class AdminSyncSupportFailedEvent {
  const AdminSyncSupportFailedEvent({
    required this.id,
    required this.eventId,
    required this.entity,
    required this.operation,
    required this.errorCode,
    required this.errorMessage,
    required this.updatedAt,
    required this.payloadSummary,
  });

  final String id;
  final String eventId;
  final String entity;
  final String operation;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? updatedAt;
  final String? payloadSummary;

  factory AdminSyncSupportFailedEvent.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportFailedEvent(
      id: _readString(map, 'id'),
      eventId: _readString(map, 'eventId'),
      entity: _readString(map, 'entity'),
      operation: _readString(map, 'operation'),
      errorCode: _readOptionalString(map, 'errorCode'),
      errorMessage: _readOptionalString(map, 'errorMessage'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      payloadSummary: _readOptionalString(map, 'payloadSummary'),
    );
  }
}

class AdminSyncSupportConflict {
  const AdminSyncSupportConflict({
    required this.id,
    required this.entity,
    required this.code,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.resolvedAt,
  });

  final String id;
  final String entity;
  final String code;
  final String message;
  final String status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  factory AdminSyncSupportConflict.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportConflict(
      id: _readString(map, 'id'),
      entity: _readString(map, 'entity'),
      code: _readString(map, 'code'),
      message: _readString(map, 'message'),
      status: _readString(map, 'status'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      resolvedAt: _readOptionalDateTime(map, 'resolvedAt'),
    );
  }
}

class AdminSyncSupportCommand {
  const AdminSyncSupportCommand({
    required this.id,
    required this.command,
    required this.label,
    required this.status,
    required this.reason,
    required this.errorMessage,
    required this.requestedAt,
    required this.pickedUpAt,
    required this.completedAt,
    required this.expiresAt,
  });

  final String id;
  final String command;
  final String label;
  final String status;
  final String reason;
  final String? errorMessage;
  final DateTime? requestedAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;

  factory AdminSyncSupportCommand.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportCommand(
      id: _readString(map, 'id'),
      command: _readString(map, 'command'),
      label: _readString(map, 'label'),
      status: _readString(map, 'status'),
      reason: _readString(map, 'reason'),
      errorMessage: _readOptionalString(map, 'errorMessage'),
      requestedAt: _readOptionalDateTime(map, 'requestedAt'),
      pickedUpAt: _readOptionalDateTime(map, 'pickedUpAt'),
      completedAt: _readOptionalDateTime(map, 'completedAt'),
      expiresAt: _readOptionalDateTime(map, 'expiresAt'),
    );
  }
}

class AdminSyncSupportDryRunResult {
  const AdminSyncSupportDryRunResult({
    required this.allowed,
    required this.command,
    required this.label,
    required this.expectedConfirmationText,
    required this.blockers,
    required this.risks,
    required this.summary,
  });

  final bool allowed;
  final String command;
  final String label;
  final String expectedConfirmationText;
  final List<String> blockers;
  final List<String> risks;
  final String summary;

  factory AdminSyncSupportDryRunResult.fromMap(Map<String, dynamic> map) {
    return AdminSyncSupportDryRunResult(
      allowed: map['allowed'] == true,
      command: _readString(map, 'command'),
      label: _readString(map, 'label'),
      expectedConfirmationText: _readString(map, 'expectedConfirmationText'),
      blockers: _readStringList(map['blockers']),
      risks: _readStringList(map['risks']),
      summary: _readString(map, 'summary'),
    );
  }
}

class AdminSyncSupportActionResult {
  const AdminSyncSupportActionResult({
    required this.ok,
    required this.message,
    required this.command,
  });

  final bool ok;
  final String? message;
  final AdminSyncSupportCommand? command;

  factory AdminSyncSupportActionResult.fromMap(Map<String, dynamic> map) {
    final command = map['command'];
    return AdminSyncSupportActionResult(
      ok: map['ok'] == true,
      message: _readOptionalString(map, 'message'),
      command: command is Map<String, dynamic>
          ? AdminSyncSupportCommand.fromMap(command)
          : null,
    );
  }
}

String adminSyncCenterClassificationLabel(String value) {
  switch (value) {
    case 'REPROCESSABLE':
      return 'Reprocessável';
    case 'NEEDS_PRODUCT_MAPPING':
      return 'Requer mapeamento';
    case 'MANUAL_STOCK_REVIEW':
      return 'Revisão manual de estoque';
    case 'IRRECOVERABLE_LEGACY_EVENT':
      return 'Evento legado';
    case 'DANGEROUS':
      return 'Perigoso';
    case 'UNKNOWN':
      return 'Requer revisão';
    default:
      return value;
  }
}

String adminSyncCenterActionLabel(String value) {
  switch (value) {
    case 'REPROCESS':
      return 'Reprocessar';
    case 'ARCHIVE_LEGACY':
      return 'Arquivar com auditoria';
    case 'MANUAL_STOCK_ADJUSTMENT':
      return 'Revisão manual de estoque';
    case 'REVIEW_PRODUCT_MAPPING':
      return 'Revisar mapeamento';
    case 'CONTACT_SUPPORT':
      return 'Acionar suporte';
    case 'NO_ACTION':
      return 'Sem ação';
    default:
      return value;
  }
}

String adminSyncCenterEntityLabel(String value) {
  switch (value) {
    case 'stockDeduction':
      return 'Baixa de estoque';
    case 'cashSession':
      return 'Sessão de caixa';
    case 'saleItem':
      return 'Item da venda';
    case 'cashMovement':
      return 'Movimento de caixa';
    case 'payment':
      return 'Pagamento';
    case 'receipt':
      return 'Recibo';
    case 'sale':
      return 'Venda';
    case 'customer':
      return 'Cliente';
    case 'product':
      return 'Produto';
    case 'category':
      return 'Categoria';
    case 'supplier':
      return 'Fornecedor';
    default:
      return value;
  }
}

String adminSyncCenterOperationLabel(String value) {
  switch (value) {
    case 'create':
      return 'Criar';
    case 'update':
      return 'Atualizar';
    case 'delete':
      return 'Excluir';
    default:
      return value;
  }
}

String adminSyncCenterFeatureLabel(String value) {
  switch (value) {
    case 'pdv':
      return 'PDV';
    case 'cash':
      return 'Caixa';
    case 'inventory':
      return 'Estoque';
    case 'catalog':
      return 'Catálogo';
    default:
      return value;
  }
}

String adminSyncCenterStatusLabel(String value) {
  switch (value.toLowerCase()) {
    case 'failed':
      return 'Falhas';
    case 'conflict':
      return 'Conflitos';
    case 'requires_review':
      return 'Requer revisão';
    case 'healthy':
      return 'Saudável';
    case 'pending':
      return 'Pendente';
    case 'accepted':
      return 'Aceito';
    case 'duplicate':
      return 'Duplicado';
    case 'open':
      return 'Aberto';
    case 'resolved':
      return 'Resolvido';
    default:
      return value;
  }
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  return const <String, dynamic>{};
}

Map<String, dynamic> _readOptionalMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(value);
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is List<dynamic>) {
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

String _readString(Map<String, dynamic> map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value != null && value is! Map && value is! List) {
    final normalized = value.toString().trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  if (fallback != null) {
    return fallback;
  }
  return '';
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value != null && value is! Map && value is! List) {
    final normalized = value.toString().trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
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
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

String? _normalized(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
