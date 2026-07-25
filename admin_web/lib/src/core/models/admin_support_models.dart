import 'admin_billing_models.dart';
import 'admin_models.dart';
import 'admin_sync_center_models.dart';

enum AdminSupportSeverity {
  critical,
  high,
  medium,
  low,
  healthy;

  String get label {
    return switch (this) {
      AdminSupportSeverity.critical => 'Critico',
      AdminSupportSeverity.high => 'Alto',
      AdminSupportSeverity.medium => 'Medio',
      AdminSupportSeverity.low => 'Baixo',
      AdminSupportSeverity.healthy => 'Saudavel',
    };
  }
}

class AdminSupportTriageSnapshot {
  const AdminSupportTriageSnapshot({
    required this.items,
    required this.generatedAt,
    required this.usesFallback,
    required this.unavailableSignals,
  });

  final List<AdminSupportTriageItem> items;
  final DateTime generatedAt;
  final bool usesFallback;
  final List<String> unavailableSignals;

  int get criticalCompanies => items
      .where((item) => item.severity == AdminSupportSeverity.critical)
      .length;

  int get highCompanies =>
      items.where((item) => item.severity == AdminSupportSeverity.high).length;

  int get actionableCompanies => items
      .where((item) => item.severity != AdminSupportSeverity.healthy)
      .length;

  factory AdminSupportTriageSnapshot.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    return AdminSupportTriageSnapshot(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(AdminSupportTriageItem.fromMap)
                .toList(growable: false)
          : const <AdminSupportTriageItem>[],
      generatedAt:
          DateTime.tryParse(map['generatedAt']?.toString() ?? '') ??
          DateTime.now(),
      usesFallback: map['usesFallback'] == true,
      unavailableSignals: _readStringList(map['unavailableSignals']),
    );
  }
}

class AdminSupportTriageItem {
  const AdminSupportTriageItem({
    required this.companyId,
    required this.companyName,
    required this.severity,
    required this.score,
    required this.status,
    required this.probableCauses,
    required this.signals,
    required this.nextBestActions,
    required this.lastActivityAt,
    required this.routeToCompanyWorkspace,
  });

  final String companyId;
  final String companyName;
  final AdminSupportSeverity severity;
  final int score;
  final String status;
  final List<String> probableCauses;
  final List<AdminSupportSignal> signals;
  final List<AdminSupportActionDefinition> nextBestActions;
  final DateTime? lastActivityAt;
  final String routeToCompanyWorkspace;

  factory AdminSupportTriageItem.fromMap(Map<String, dynamic> map) {
    final companyId = _readString(map, 'companyId');
    final rawSignals = map['signals'];
    final rawActions = map['nextBestActions'];
    return AdminSupportTriageItem(
      companyId: companyId,
      companyName: _readString(map, 'companyName', fallback: 'Empresa'),
      severity: adminSupportSeverityFromString(map['severity']?.toString()),
      score: _readInt(map['score']),
      status: _readString(map, 'status', fallback: 'Sem classificacao'),
      probableCauses: _readStringList(map['probableCauses']),
      signals: rawSignals is List
          ? rawSignals
                .whereType<Map<String, dynamic>>()
                .map(AdminSupportSignal.fromMap)
                .toList(growable: false)
          : const <AdminSupportSignal>[],
      nextBestActions: rawActions is List
          ? rawActions
                .whereType<Map<String, dynamic>>()
                .map(AdminSupportActionDefinition.fromMap)
                .toList(growable: false)
          : const <AdminSupportActionDefinition>[],
      lastActivityAt: DateTime.tryParse(
        map['lastActivityAt']?.toString() ?? '',
      ),
      routeToCompanyWorkspace: _readString(
        map,
        'routeToCompanyWorkspace',
        fallback: '/companies/$companyId/support',
      ),
    );
  }

  static AdminSupportTriageItem fromFallback({
    required AdminCompanySummary company,
    AdminSyncCenterCompany? sync,
    AdminBillingCompanySummary? billing,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final signals = <AdminSupportSignal>[];
    final causes = <String>[];
    final actions = <AdminSupportActionDefinition>[];
    var score = 0;

    final license = company.license;
    final plan = (billing?.plan ?? license?.plan ?? 'FREE').toUpperCase();
    final licenseStatus = (billing?.licenseStatus ?? license?.status ?? '')
        .toLowerCase();
    final billingStatus = billing?.billingSubscriptionStatus?.toLowerCase();

    if (plan != 'FREE' && _isBlockedLicenseStatus(licenseStatus)) {
      score += 45;
      signals.add(
        const AdminSupportSignal(
          type: 'billing',
          label: 'Empresa paga com licenca bloqueada',
          value: 'Licenca exige revisao',
          severity: AdminSupportSeverity.critical,
        ),
      );
      causes.add('Licenca bloqueada apesar de plano pago');
      actions.add(AdminSupportActionDefinition.billingReconcile(company.id));
    }

    if (_isBadBillingStatus(billingStatus)) {
      score += 35;
      signals.add(
        AdminSupportSignal(
          type: 'billing',
          label: 'Billing com falha recente',
          value: billingStatus ?? 'Indisponivel',
          severity: AdminSupportSeverity.high,
        ),
      );
      causes.add('Assinatura com status de cobranca problemático');
      actions.add(AdminSupportActionDefinition.billingReconcile(company.id));
    }

    if (billing?.pendingPlan != null) {
      score += 10;
      signals.add(
        AdminSupportSignal(
          type: 'billing',
          label: 'Mudanca de plano pendente',
          value: billing!.pendingPlan!,
          severity: AdminSupportSeverity.low,
        ),
      );
      actions.add(AdminSupportActionDefinition.billingOpen(company.id));
    }

    if (billing?.cancelAtPeriodEnd == true) {
      score += 15;
      signals.add(
        const AdminSupportSignal(
          type: 'billing',
          label: 'Cancelamento agendado',
          value: 'cancelAtPeriodEnd',
          severity: AdminSupportSeverity.medium,
        ),
      );
      causes.add('Cancelamento local/agendado pode afetar acesso');
      actions.add(AdminSupportActionDefinition.billingOpen(company.id));
    }

    if (sync != null) {
      if (sync.failedCount > 0 ||
          sync.syncStatus.toLowerCase().contains('fail')) {
        score += 40;
        signals.add(
          AdminSupportSignal(
            type: 'sync',
            label: 'Eventos de sync com falha',
            value: '${sync.failedCount}',
            severity: AdminSupportSeverity.critical,
          ),
        );
        causes.add('Eventos de sync falhando');
        actions.add(AdminSupportActionDefinition.syncOpen(company.id));
      }
      if (sync.openConflictCount > 0) {
        score += 30 + sync.openConflictCount.clamp(0, 5).toInt();
        signals.add(
          AdminSupportSignal(
            type: 'sync',
            label: 'Conflitos abertos',
            value: '${sync.openConflictCount}',
            severity: AdminSupportSeverity.high,
          ),
        );
        causes.add('Conflito aberto impedindo consolidacao');
        actions.add(AdminSupportActionDefinition.syncOpen(company.id));
      }
      if (sync.pendingCount > 0) {
        score += 15;
        signals.add(
          AdminSupportSignal(
            type: 'sync',
            label: 'Eventos pendentes',
            value: '${sync.pendingCount}',
            severity: AdminSupportSeverity.medium,
          ),
        );
        causes.add('Fila de sync pendente');
        actions.add(AdminSupportActionDefinition.syncOpen(company.id));
      }
      if (_isStale(sync.lastEventAt, clock)) {
        score += 25;
        signals.add(
          const AdminSupportSignal(
            type: 'sync',
            label: 'Sync parado ou antigo',
            value: 'Sem evento recente',
            severity: AdminSupportSeverity.high,
          ),
        );
        causes.add('Device sem sync recente');
        actions.add(AdminSupportActionDefinition.syncOpen(company.id));
      }
    } else if (license?.syncEnabled == true) {
      score += 8;
      signals.add(
        const AdminSupportSignal(
          type: 'sync',
          label: 'Saude de sync indisponivel no fallback',
          value: 'Nao disponivel',
          severity: AdminSupportSeverity.low,
        ),
      );
    }

    if (!company.isActive) {
      score += 20;
      signals.add(
        const AdminSupportSignal(
          type: 'company',
          label: 'Empresa inativa',
          value: 'Inativa',
          severity: AdminSupportSeverity.medium,
        ),
      );
      causes.add('Tenant inativo');
    }

    if (actions.isEmpty) {
      actions.add(AdminSupportActionDefinition.openWorkspace(company.id));
    } else {
      actions.add(AdminSupportActionDefinition.openWorkspace(company.id));
    }

    final severity = adminSupportSeverityForScore(score);
    return AdminSupportTriageItem(
      companyId: company.id,
      companyName: company.name,
      severity: severity,
      score: score,
      status: severity == AdminSupportSeverity.healthy
          ? 'Sem sinais criticos no fallback'
          : 'Requer triagem',
      probableCauses: causes.isEmpty
          ? const <String>['Operacao aparentemente saudavel no fallback']
          : causes.toSet().toList(growable: false),
      signals: signals,
      nextBestActions: actions.toSet().toList(growable: false),
      lastActivityAt: _latestDate([
        company.updatedAt,
        sync?.lastIncidentAt,
        sync?.lastEventAt,
        billing?.updatedAt,
      ]),
      routeToCompanyWorkspace: '/companies/${company.id}/support',
    );
  }
}

class AdminSupportSignal {
  const AdminSupportSignal({
    required this.type,
    required this.label,
    required this.value,
    required this.severity,
  });

  final String type;
  final String label;
  final String value;
  final AdminSupportSeverity severity;

  factory AdminSupportSignal.fromMap(Map<String, dynamic> map) {
    return AdminSupportSignal(
      type: _readString(map, 'type', fallback: 'unknown'),
      label: _readString(map, 'label', fallback: 'Sinal'),
      value: _readString(map, 'value', fallback: 'Indisponivel'),
      severity: adminSupportSeverityFromString(map['severity']?.toString()),
    );
  }
}

class AdminSupportActionDefinition {
  const AdminSupportActionDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.targetType,
    required this.targetId,
    required this.requiredPermission,
    required this.riskLevel,
    required this.requiresReason,
    required this.requiresExplicitConfirmation,
    required this.supportsDryRun,
    required this.dryRunEndpoint,
    required this.executeEndpoint,
    required this.rollbackHint,
    required this.auditCategory,
    required this.route,
    required this.available,
  });

  final String id;
  final String label;
  final String description;
  final String targetType;
  final String targetId;
  final String requiredPermission;
  final String riskLevel;
  final bool requiresReason;
  final bool requiresExplicitConfirmation;
  final bool supportsDryRun;
  final String? dryRunEndpoint;
  final String? executeEndpoint;
  final String rollbackHint;
  final String auditCategory;
  final String route;
  final bool available;

  factory AdminSupportActionDefinition.fromMap(Map<String, dynamic> map) {
    return AdminSupportActionDefinition(
      id: _readString(map, 'id', fallback: 'support.open'),
      label: _readString(map, 'label', fallback: 'Abrir workspace'),
      description: _readString(map, 'description', fallback: ''),
      targetType: _readString(map, 'targetType', fallback: 'company'),
      targetId: _readString(map, 'targetId', fallback: ''),
      requiredPermission: _readString(map, 'requiredPermission', fallback: ''),
      riskLevel: _readString(map, 'riskLevel', fallback: 'low'),
      requiresReason: map['requiresReason'] == true,
      requiresExplicitConfirmation: map['requiresExplicitConfirmation'] == true,
      supportsDryRun: map['supportsDryRun'] == true,
      dryRunEndpoint: map['dryRunEndpoint']?.toString(),
      executeEndpoint: map['executeEndpoint']?.toString(),
      rollbackHint: _readString(map, 'rollbackHint', fallback: ''),
      auditCategory: _readString(map, 'auditCategory', fallback: 'support'),
      route: _readString(map, 'route', fallback: ''),
      available: map['available'] != false,
    );
  }

  static AdminSupportActionDefinition openWorkspace(String companyId) {
    return AdminSupportActionDefinition(
      id: 'support.company.workspace',
      label: 'Abrir workspace',
      description: 'Investigar causa provavel, evidencias e proximos passos.',
      targetType: 'company',
      targetId: companyId,
      requiredPermission: 'support.company.read',
      riskLevel: 'low',
      requiresReason: false,
      requiresExplicitConfirmation: false,
      supportsDryRun: false,
      dryRunEndpoint: null,
      executeEndpoint: null,
      rollbackHint: 'Sem alteracao de dados.',
      auditCategory: 'support',
      route: '/companies/$companyId/support',
      available: true,
    );
  }

  static AdminSupportActionDefinition syncOpen(String companyId) {
    return AdminSupportActionDefinition(
      id: 'support.sync.open',
      label: 'Abrir Sync Center',
      description: 'Ver eventos, conflitos, devices e comandos com dry-run.',
      targetType: 'company',
      targetId: companyId,
      requiredPermission: 'support.sync.read',
      riskLevel: 'medium',
      requiresReason: false,
      requiresExplicitConfirmation: false,
      supportsDryRun: true,
      dryRunEndpoint:
          '/admin/sync/companies/:companyId/devices/:deviceId/support-actions/dry-run',
      executeEndpoint:
          '/admin/sync/companies/:companyId/devices/:deviceId/support-actions',
      rollbackHint: 'Comandos ficam pendentes e auditados por dispositivo.',
      auditCategory: 'sync_support',
      route: '/companies/$companyId/sync',
      available: true,
    );
  }

  static AdminSupportActionDefinition billingOpen(String companyId) {
    return AdminSupportActionDefinition(
      id: 'support.billing.open',
      label: 'Abrir billing',
      description: 'Investigar status de assinatura e eventos do provider.',
      targetType: 'company',
      targetId: companyId,
      requiredPermission: 'billing.read',
      riskLevel: 'medium',
      requiresReason: false,
      requiresExplicitConfirmation: false,
      supportsDryRun: false,
      dryRunEndpoint: null,
      executeEndpoint: null,
      rollbackHint: 'Acoes mutaveis seguem fluxo proprio com motivo.',
      auditCategory: 'billing',
      route: '/billing/$companyId',
      available: true,
    );
  }

  static AdminSupportActionDefinition billingReconcile(String companyId) {
    return AdminSupportActionDefinition(
      id: 'support.billing.reconcile',
      label: 'Reconciliar billing',
      description: 'Preparar reconciliacao auditada quando contrato permitir.',
      targetType: 'company',
      targetId: companyId,
      requiredPermission: 'billing.reconcile',
      riskLevel: 'high',
      requiresReason: true,
      requiresExplicitConfirmation: true,
      supportsDryRun: true,
      dryRunEndpoint: '/admin/companies/:companyId/billing/reconcile/dry-run',
      executeEndpoint: '/admin/companies/:companyId/billing/reconcile',
      rollbackHint: 'Revisar auditoria de billing e estado anterior.',
      auditCategory: 'billing',
      route: '/billing/$companyId',
      available: true,
    );
  }
}

AdminSupportTriageSnapshot buildFallbackSupportTriageSnapshot({
  required List<AdminCompanySummary> companies,
  required List<AdminSyncCenterCompany> syncCompanies,
  required List<AdminBillingCompanySummary> billingCompanies,
  DateTime? now,
}) {
  final syncByCompany = {
    for (final item in syncCompanies) item.companyId: item,
  };
  final billingByCompany = {
    for (final item in billingCompanies) item.companyId: item,
  };
  final items =
      companies
          .map(
            (company) => AdminSupportTriageItem.fromFallback(
              company: company,
              sync: syncByCompany[company.id],
              billing: billingByCompany[company.id],
              now: now,
            ),
          )
          .toList()
        ..sort(_compareTriageItems);

  return AdminSupportTriageSnapshot(
    items: items,
    generatedAt: now ?? DateTime.now(),
    usesFallback: true,
    unavailableSignals: const <String>[
      'comandos pendentes/expirados por empresa',
      'sessoes suspeitas consolidadas',
      'usuarios bloqueados e convites pendentes globais',
      'versao antiga do app em escala global',
      'latencia por endpoint e taxa de erro',
    ],
  );
}

AdminSupportSeverity adminSupportSeverityForScore(int score) {
  if (score >= 80) {
    return AdminSupportSeverity.critical;
  }
  if (score >= 55) {
    return AdminSupportSeverity.high;
  }
  if (score >= 30) {
    return AdminSupportSeverity.medium;
  }
  if (score >= 10) {
    return AdminSupportSeverity.low;
  }
  return AdminSupportSeverity.healthy;
}

AdminSupportSeverity adminSupportSeverityFromString(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'critical' || 'critico' => AdminSupportSeverity.critical,
    'high' || 'alto' => AdminSupportSeverity.high,
    'medium' || 'medio' => AdminSupportSeverity.medium,
    'low' || 'baixo' => AdminSupportSeverity.low,
    'healthy' || 'saudavel' => AdminSupportSeverity.healthy,
    _ => AdminSupportSeverity.healthy,
  };
}

int _compareTriageItems(
  AdminSupportTriageItem left,
  AdminSupportTriageItem right,
) {
  final score = right.score.compareTo(left.score);
  if (score != 0) {
    return score;
  }
  final leftDate = left.lastActivityAt;
  final rightDate = right.lastActivityAt;
  if (leftDate != null && rightDate != null) {
    return rightDate.compareTo(leftDate);
  }
  if (leftDate == null && rightDate != null) {
    return 1;
  }
  if (leftDate != null && rightDate == null) {
    return -1;
  }
  return left.companyName.compareTo(right.companyName);
}

bool _isBlockedLicenseStatus(String value) {
  return value == 'blocked' ||
      value == 'suspended' ||
      value == 'inactive' ||
      value == 'expired' ||
      value == 'canceled' ||
      value == 'cancelled';
}

bool _isBadBillingStatus(String? value) {
  return value == 'failed' ||
      value == 'past_due' ||
      value == 'unpaid' ||
      value == 'cancelled' ||
      value == 'canceled' ||
      value == 'rejected';
}

bool _isStale(DateTime? value, DateTime now) {
  if (value == null) {
    return true;
  }
  return now.difference(value) > const Duration(hours: 24);
}

DateTime? _latestDate(List<DateTime?> values) {
  final dates = values.whereType<DateTime>().toList(growable: false);
  if (dates.isEmpty) {
    return null;
  }
  dates.sort((left, right) => right.compareTo(left));
  return dates.first;
}

String _readString(
  Map<String, dynamic> map,
  String key, {
  String fallback = '',
}) {
  final value = map[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }
  return value;
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
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
