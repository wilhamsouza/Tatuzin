class AdminSupportActionDryRunRequest {
  const AdminSupportActionDryRunRequest({
    required this.actionType,
    required this.companyId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.metadata = const <String, dynamic>{},
  });

  final String actionType;
  final String companyId;
  final String targetType;
  final String targetId;
  final String reason;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toApiPayload() {
    return <String, dynamic>{
      'actionType': actionType.trim(),
      'companyId': companyId.trim(),
      'targetType': targetType.trim(),
      'targetId': targetId.trim(),
      'reason': reason.trim(),
      'dryRun': true,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AdminSupportActionDryRunResponse {
  const AdminSupportActionDryRunResponse({
    required this.ok,
    required this.code,
    required this.message,
    required this.action,
  });

  final bool ok;
  final String code;
  final String message;
  final AdminSupportActionDryRun? action;

  factory AdminSupportActionDryRunResponse.fromMap(Map<String, dynamic> map) {
    final rawAction = map['action'];
    return AdminSupportActionDryRunResponse(
      ok: map['ok'] == true,
      code: _readString(map, 'code', fallback: 'OPERATIONAL_ACTION_UNKNOWN'),
      message: _readString(
        map,
        'message',
        fallback: 'Resposta de simulacao recebida.',
      ),
      action: rawAction is Map<String, dynamic>
          ? AdminSupportActionDryRun.fromMap(rawAction)
          : null,
    );
  }
}

class AdminSupportActionDryRun {
  const AdminSupportActionDryRun({
    required this.actionType,
    required this.permissionKey,
    required this.companyId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.dryRun,
    required this.confirmationRequired,
    required this.expectedImpact,
    required this.result,
    required this.auditRequired,
    required this.auditPrepared,
    required this.auditEventId,
    required this.auditDraft,
    required this.createdAt,
  });

  final String actionType;
  final String permissionKey;
  final String companyId;
  final String targetType;
  final String targetId;
  final String reason;
  final bool dryRun;
  final bool confirmationRequired;
  final AdminSupportActionExpectedImpact expectedImpact;
  final AdminSupportActionResult result;
  final bool auditRequired;
  final bool auditPrepared;
  final String? auditEventId;
  final AdminSupportActionAuditDraft auditDraft;
  final DateTime? createdAt;

  factory AdminSupportActionDryRun.fromMap(Map<String, dynamic> map) {
    return AdminSupportActionDryRun(
      actionType: _readString(map, 'actionType'),
      permissionKey: _readString(
        map,
        'permissionKey',
        fallback: 'Indisponivel',
      ),
      companyId: _readString(map, 'companyId'),
      targetType: _readString(map, 'targetType'),
      targetId: _readString(map, 'targetId'),
      reason: _readString(map, 'reason', fallback: 'Nao informado'),
      dryRun: map['dryRun'] == true,
      confirmationRequired: map['confirmationRequired'] == true,
      expectedImpact: AdminSupportActionExpectedImpact.fromMap(
        _readMap(map, 'expectedImpact'),
      ),
      result: AdminSupportActionResult.fromMap(_readMap(map, 'result')),
      auditRequired: map['auditRequired'] == true,
      auditPrepared: map['auditPrepared'] == true,
      auditEventId: _readOptionalString(map, 'auditEventId'),
      auditDraft: AdminSupportActionAuditDraft.fromMap(
        _readMap(map, 'auditDraft'),
      ),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
    );
  }
}

class AdminSupportActionExpectedImpact {
  const AdminSupportActionExpectedImpact({
    required this.summary,
    required this.risks,
    required this.affectedEntities,
    required this.confirmationRequired,
  });

  final String summary;
  final List<String> risks;
  final List<AdminSupportActionAffectedEntity> affectedEntities;
  final bool confirmationRequired;

  factory AdminSupportActionExpectedImpact.fromMap(Map<String, dynamic> map) {
    return AdminSupportActionExpectedImpact(
      summary: _readString(map, 'summary', fallback: 'Impacto indisponivel.'),
      risks: _readStringList(map['risks']),
      affectedEntities: _readMapList(
        map['affectedEntities'],
      ).map(AdminSupportActionAffectedEntity.fromMap).toList(growable: false),
      confirmationRequired: map['confirmationRequired'] == true,
    );
  }
}

class AdminSupportActionAffectedEntity {
  const AdminSupportActionAffectedEntity({
    required this.type,
    required this.id,
    required this.label,
  });

  final String type;
  final String id;
  final String? label;

  factory AdminSupportActionAffectedEntity.fromMap(Map<String, dynamic> map) {
    return AdminSupportActionAffectedEntity(
      type: _readString(map, 'type', fallback: 'unknown'),
      id: _readString(map, 'id', fallback: 'Indisponivel'),
      label: _readOptionalString(map, 'label'),
    );
  }
}

class AdminSupportActionResult {
  const AdminSupportActionResult({
    required this.status,
    required this.code,
    required this.message,
  });

  final String status;
  final String code;
  final String message;

  factory AdminSupportActionResult.fromMap(Map<String, dynamic> map) {
    return AdminSupportActionResult(
      status: _readString(map, 'status', fallback: 'unknown'),
      code: _readString(map, 'code', fallback: 'OPERATIONAL_ACTION_UNKNOWN'),
      message: _readString(map, 'message', fallback: 'Resultado indisponivel.'),
    );
  }
}

class AdminSupportActionAuditDraft {
  const AdminSupportActionAuditDraft({
    required this.dryRun,
    required this.confirmationRequired,
    required this.riskLevel,
    required this.createdAt,
  });

  final bool dryRun;
  final bool confirmationRequired;
  final String riskLevel;
  final DateTime? createdAt;

  factory AdminSupportActionAuditDraft.fromMap(Map<String, dynamic> map) {
    return AdminSupportActionAuditDraft(
      dryRun: map['dryRun'] == true,
      confirmationRequired: map['confirmationRequired'] == true,
      riskLevel: _readString(map, 'riskLevel', fallback: 'unknown'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
    );
  }
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  return value is List<dynamic>
      ? value.whereType<Map<String, dynamic>>().toList(growable: false)
      : const <Map<String, dynamic>>[];
}

List<String> _readStringList(Object? value) {
  return value is List<dynamic>
      ? value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
      : const <String>[];
}

String _readString(Map<String, dynamic> map, String key, {String? fallback}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (fallback != null) {
    return fallback;
  }
  throw FormatException('Campo "$key" ausente no payload de support-actions.');
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String ? DateTime.tryParse(value.trim()) : null;
}
