import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_access_models.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/models/admin_sync_center_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/utils/admin_safe_display.dart';
import '../../../core/widgets/admin_operational_status.dart';
import '../../../core/widgets/admin_surface.dart';
import '../../../core/widgets/admin_support_action_dry_run_panel.dart';

class CompanySupportPage extends ConsumerWidget {
  const CompanySupportPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminCompanyDetailProvider(companyId));

    return detailAsync.when(
      data: (detail) => _CompanySupportContent(detail: detail),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a central de suporte',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () =>
              ref.invalidate(adminCompanyDetailProvider(companyId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text('Nenhum payload sensivel foi exibido.'),
      ),
    );
  }
}

class _CompanySupportContent extends ConsumerWidget {
  const _CompanySupportContent({required this.detail});

  final AdminCompanyDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = detail.company;
    final billingAsync = ref.watch(
      adminBillingCompanyStatusProvider(company.id),
    );
    final accessAsync = ref.watch(
      adminCompanyAccessSummaryProvider(company.id),
    );
    final devicesAsync = ref.watch(
      adminDevicesProvider(
        AdminDevicesQuery(companyId: company.id, pageSize: 100),
      ),
    );
    final sessionsAsync = ref.watch(adminCompanySessionsProvider(company.id));
    final syncAsync = ref.watch(
      adminSyncCenterCompanySummaryProvider(company.id),
    );
    final healthAsync = ref.watch(adminCompanySyncHealthProvider(company.id));
    final auditAsync = ref.watch(
      adminAuditLogsProvider(
        AdminAuditQuery(companyId: company.id, pageSize: 5),
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SupportHeader(company: company),
          const SizedBox(height: 16),
          const _ReadOnlyNotice(),
          const SizedBox(height: 16),
          AdminSupportActionDryRunPanel(companyId: company.id),
          const SizedBox(height: 16),
          _SupportGrid(
            cards: [
              _companyCard(context, company),
              _licenseCard(context, company, billingAsync),
              _billingCard(context, company.id, billingAsync),
              _devicesCard(context, company.id, devicesAsync),
              _androidVersionCard(context, company.id, devicesAsync),
              _pushNotificationCard(),
              _sessionsCard(context, company.id, sessionsAsync),
              _permissionsCard(context),
              _simulationCard(),
              _revokeSessionRolloutCard(context, company.id),
              _usersCard(context, company.id, accessAsync),
              _employeesCard(context, company.id, accessAsync),
              _syncCard(context, company.id, syncAsync),
              _conflictsCard(context, company.id, syncAsync),
              _auditCard(context, company.id, auditAsync),
              _securityCard(context, company.id),
              _observabilityCard(
                context,
                company.id,
                healthAsync,
                billingAsync,
                devicesAsync,
                auditAsync,
              ),
              _operationalStatusCard(context, healthAsync, billingAsync),
            ],
          ),
        ],
      ),
    );
  }

  _SupportCard _companyCard(BuildContext context, AdminCompanySummary company) {
    return _SupportCard(
      icon: Icons.apartment_rounded,
      title: 'Dados da empresa',
      subtitle: 'Identificacao e status administrativo do tenant.',
      metrics: [
        _SupportMetric(label: 'Empresa', value: company.name),
        _SupportMetric(label: 'Tenant', value: company.slug),
        _SupportMetric(
          label: 'Documento',
          value: maskAdminIdentifier(
            company.documentNumber,
            fallback: 'Nao informado',
          ),
        ),
        _SupportMetric(
          label: 'Status',
          value: company.isActive ? 'Ativa' : 'Inativa',
        ),
      ],
      actionLabel: 'Abrir empresa',
      onAction: () => context.go('/companies/${company.id}'),
    );
  }

  _SupportCard _licenseCard(
    BuildContext context,
    AdminCompanySummary company,
    AsyncValue<AdminBillingCompanyStatus> billingAsync,
  ) {
    return _asyncCard<AdminBillingCompanyStatus>(
      icon: Icons.workspace_premium_rounded,
      title: 'Plano/licenca',
      subtitle: 'Plano ativo, validade e limites conhecidos.',
      value: billingAsync,
      fallbackMetrics: [
        _SupportMetric(
          label: 'Plano',
          value: AdminFormatters.formatPlan(company.license?.plan ?? 'FREE'),
        ),
        _SupportMetric(
          label: 'Status',
          value: AdminFormatters.formatLicenseStatus(company.license?.status),
        ),
      ],
      metricsBuilder: (status) {
        final license = status.license;
        return [
          _SupportMetric(
            label: 'Plano',
            value: AdminFormatters.formatPlan(
              license?.plan ?? company.license?.plan ?? 'FREE',
            ),
          ),
          _SupportMetric(
            label: 'Status',
            value: AdminFormatters.formatLicenseStatus(
              license?.status ?? company.license?.status,
            ),
          ),
          _SupportMetric(
            label: 'Validade',
            value: AdminFormatters.formatDate(
              license?.expiresAt ?? company.license?.expiresAt,
            ),
          ),
          _SupportMetric(
            label: 'Max dispositivos',
            value:
                (license?.maxDevices ?? company.license?.maxDevices)
                    ?.toString() ??
                'Livre',
          ),
        ];
      },
      actionLabel: 'Ver licenca',
      onAction: () => context.go('/companies/${company.id}/license'),
    );
  }

  _SupportCard _billingCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminBillingCompanyStatus> billingAsync,
  ) {
    return _asyncCard<AdminBillingCompanyStatus>(
      icon: Icons.payments_rounded,
      title: 'Billing',
      subtitle: 'Resumo restrito de assinatura e provider.',
      value: billingAsync,
      metricsBuilder: (status) {
        final billing = status.billing;
        return [
          _SupportMetric(
            label: 'Provider',
            value: billing.provider ?? 'Nao informado',
          ),
          _SupportMetric(
            label: 'Assinatura',
            value: billing.hasProviderSubscription
                ? 'Vinculada'
                : 'Sem provider',
          ),
          _SupportMetric(
            label: 'Status assinatura',
            value: billing.billingSubscriptionStatus ?? 'Nao informado',
          ),
          _SupportMetric(
            label: 'Cancelamento',
            value: billing.cancelAtPeriodEnd ? 'Agendado' : 'Nao agendado',
          ),
        ];
      },
      actionLabel: 'Abrir billing',
      onAction: () => context.go('/billing/$companyId'),
    );
  }

  _SupportCard _devicesCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminPaginatedResult<AdminDeviceInventoryItem>> devicesAsync,
  ) {
    return _asyncCard<AdminPaginatedResult<AdminDeviceInventoryItem>>(
      icon: Icons.devices_rounded,
      title: 'Dispositivos',
      subtitle: 'Inventario reportado por clientes da plataforma.',
      value: devicesAsync,
      metricsBuilder: (devices) {
        final mobile = devices.items
            .where((device) => device.clientType.toUpperCase() == 'MOBILE_APP')
            .length;
        final attention = devices.items
            .where((device) => device.hasLocalAttention)
            .length;
        final critical = devices.items
            .where(
              (device) =>
                  (device.diagnostic?.failedCount ?? 0) > 0 ||
                  (device.diagnostic?.openConflictCount ?? 0) > 0,
            )
            .length;
        final lastError = _firstLocalError(devices.items);
        return [
          _SupportMetric(label: 'Total', value: '${devices.pagination.total}'),
          _SupportMetric(label: 'Mobile', value: '$mobile'),
          _SupportMetric(label: 'Com atencao', value: '$attention'),
          _SupportMetric(
            label: 'Status',
            value: critical > 0
                ? 'Critico'
                : attention > 0
                ? 'Atencao'
                : devices.items.isEmpty
                ? 'Sem dados'
                : 'OK',
            tone: _deviceTone(devices.items),
          ),
          _SupportMetric(
            label: 'Ultimo erro',
            value: lastError ?? 'Nenhum erro',
          ),
        ];
      },
      actionLabel: 'Ver dispositivos',
      onAction: () => context.go('/companies/$companyId/devices'),
    );
  }

  _SupportCard _androidVersionCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminPaginatedResult<AdminDeviceInventoryItem>> devicesAsync,
  ) {
    return _asyncCard<AdminPaginatedResult<AdminDeviceInventoryItem>>(
      icon: Icons.android_rounded,
      title: 'Controle de versao Android',
      subtitle: 'Leitura read-only das versoes reportadas pelos dispositivos.',
      value: devicesAsync,
      metricsBuilder: (devices) {
        final mobileDevices = _androidDevices(devices.items);
        final known = mobileDevices
            .where((device) => _hasAppVersion(device.appVersion))
            .length;
        final missing = mobileDevices.length - known;
        final tone = _androidVersionTone(mobileDevices);
        return [
          _SupportMetric(
            label: 'Status geral',
            value: _operationalLabel(tone),
            tone: tone,
          ),
          _SupportMetric(label: 'MOBILE_APP', value: '${mobileDevices.length}'),
          _SupportMetric(label: 'Versao conhecida', value: '$known'),
          _SupportMetric(label: 'Versao nao informada', value: '$missing'),
          _SupportMetric(
            label: 'Versao mais antiga',
            value: _oldestAndroidVersion(mobileDevices),
          ),
          _SupportMetric(
            label: 'Sugestao',
            value: _androidVersionSuggestion(tone),
          ),
        ];
      },
      actionLabel: 'Ver dispositivos',
      onAction: () => context.go('/companies/$companyId/devices'),
    );
  }

  _SupportCard _pushNotificationCard() {
    return const _SupportCard(
      icon: Icons.notifications_active_outlined,
      title: 'Push Notification / FCM',
      subtitle: 'Preparacao read-only para notificacoes futuras.',
      metrics: [
        _SupportMetric(
          label: 'Status geral',
          value: 'Nao configurado',
          tone: AdminOperationalTone.noData,
        ),
        _SupportMetric(label: 'Tokens registrados', value: 'Indisponivel'),
        _SupportMetric(label: 'Historico de envios', value: 'Indisponivel'),
        _SupportMetric(label: 'Preferencias', value: 'Indisponivel'),
        _SupportMetric(label: 'Envio real', value: 'Bloqueado nesta fase'),
        _SupportMetric(
          label: 'Sugestao',
          value: 'FCM ainda nao esta integrado ao backend e Android.',
        ),
      ],
    );
  }

  _SupportCard _sessionsCard(
    BuildContext context,
    String companyId,
    AsyncValue<List<AdminDeviceSession>> sessionsAsync,
  ) {
    return _asyncCard<List<AdminDeviceSession>>(
      icon: Icons.login_rounded,
      title: 'Sessoes',
      subtitle: 'Sessoes recentes associadas aos dispositivos.',
      value: sessionsAsync,
      metricsBuilder: (sessions) {
        final active = sessions
            .where((session) => session.status == 'active')
            .length;
        final admin = sessions
            .where((session) => session.clientType.toUpperCase() == 'ADMIN_WEB')
            .length;
        final expired = sessions
            .where((session) => session.status.toLowerCase() == 'expired')
            .length;
        return [
          _SupportMetric(label: 'Total', value: '${sessions.length}'),
          _SupportMetric(label: 'Ativas', value: '$active'),
          _SupportMetric(label: 'ADMIN_WEB', value: '$admin'),
          _SupportMetric(
            label: 'Status',
            value: sessions.isEmpty
                ? 'Sem dados'
                : expired > 0
                ? 'Atencao'
                : 'OK',
            tone: sessions.isEmpty
                ? AdminOperationalTone.noData
                : expired > 0
                ? AdminOperationalTone.attention
                : AdminOperationalTone.ok,
          ),
        ];
      },
      actionLabel: 'Ver sessoes',
      onAction: () => context.go('/companies/$companyId/sessions'),
    );
  }

  _SupportCard _permissionsCard(BuildContext context) {
    return _SupportCard(
      icon: Icons.admin_panel_settings_rounded,
      title: 'Permissoes administrativas',
      subtitle:
          'Consulta de permissionKeys persistidas e catalogo de risco do backend.',
      metrics: const [
        _SupportMetric(
          label: 'Status',
          value: 'Read-only',
          tone: AdminOperationalTone.ok,
        ),
        _SupportMetric(label: 'Resolucao', value: 'Backend persistente'),
        _SupportMetric(label: 'isPlatformAdmin', value: 'Sem bypass sozinho'),
        _SupportMetric(label: 'Alteracoes', value: 'Fluxo controlado'),
      ],
      actionLabel: 'Ver permissoes',
      onAction: () => context.go('/permissions'),
    );
  }

  _SupportCard _simulationCard() {
    return const _SupportCard(
      icon: Icons.science_rounded,
      title: 'Simulacoes operacionais',
      subtitle:
          'Dry-run para prever impacto sem alterar dados reais da empresa.',
      metrics: [
        _SupportMetric(
          label: 'Dry-run',
          value: 'Disponivel',
          tone: AdminOperationalTone.ok,
        ),
        _SupportMetric(label: 'Motivo', value: 'Obrigatorio'),
        _SupportMetric(label: 'Auditoria', value: 'Preparada'),
        _SupportMetric(label: 'Execucao real', value: 'Indisponivel na UI'),
      ],
    );
  }

  _SupportCard _revokeSessionRolloutCard(
    BuildContext context,
    String companyId,
  ) {
    return _SupportCard(
      icon: Icons.lock_clock_rounded,
      title: 'Rollout revoke_session',
      subtitle:
          'Gate operacional antes de qualquer experiencia real no Admin Web.',
      metrics: const [
        _SupportMetric(
          label: 'Gate',
          value: 'Em observacao',
          tone: AdminOperationalTone.attention,
        ),
        _SupportMetric(label: 'Feature flag', value: 'Controlada no backend'),
        _SupportMetric(label: 'Rota legada', value: 'Observacao auditavel'),
        _SupportMetric(label: 'Confirmacao', value: 'REVOGAR_SESSAO mantida'),
        _SupportMetric(label: 'Botao real', value: 'Nao liberado'),
      ],
      actionLabel: 'Ver auditoria',
      onAction: () => context.go(
        '/audit?companyId=$companyId&action=admin.sessions.legacy_revoke.used',
      ),
    );
  }

  _SupportCard _usersCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminCompanyAccessSummary> accessAsync,
  ) {
    return _asyncCard<AdminCompanyAccessSummary>(
      icon: Icons.people_alt_rounded,
      title: 'Usuarios',
      subtitle: 'Contas de acesso vinculadas a empresa.',
      value: accessAsync,
      metricsBuilder: (access) => [
        _SupportMetric(label: 'Total', value: '${access.summary.totalUsers}'),
        _SupportMetric(label: 'Owners', value: '${access.summary.owners}'),
        _SupportMetric(label: 'Admins', value: '${access.summary.admins}'),
        _SupportMetric(
          label: 'Sem perfil',
          value: '${access.summary.usersWithoutEmployeeProfile}',
        ),
        _SupportMetric(
          label: 'Status',
          value: access.summary.totalUsers == 0 ? 'Sem dados' : 'OK',
          tone: access.summary.totalUsers == 0
              ? AdminOperationalTone.noData
              : AdminOperationalTone.ok,
        ),
      ],
      actionLabel: 'Ver usuarios',
      onAction: () => context.go('/companies/$companyId/users'),
    );
  }

  _SupportCard _employeesCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminCompanyAccessSummary> accessAsync,
  ) {
    return _asyncCard<AdminCompanyAccessSummary>(
      icon: Icons.badge_rounded,
      title: 'Funcionarios',
      subtitle: 'Perfis operacionais e situacao de acesso.',
      value: accessAsync,
      metricsBuilder: (access) => [
        _SupportMetric(
          label: 'Total',
          value: '${access.summary.totalEmployees}',
        ),
        _SupportMetric(
          label: 'Ativos',
          value: '${access.summary.activeEmployees}',
        ),
        _SupportMetric(
          label: 'Convidados',
          value: '${access.summary.invitedEmployees}',
        ),
        _SupportMetric(
          label: 'Desativados',
          value: '${access.summary.disabledEmployees}',
        ),
        _SupportMetric(
          label: 'Status',
          value: access.summary.totalEmployees == 0
              ? 'Sem dados'
              : access.summary.disabledEmployees > 0
              ? 'Atencao'
              : 'OK',
          tone: access.summary.totalEmployees == 0
              ? AdminOperationalTone.noData
              : access.summary.disabledEmployees > 0
              ? AdminOperationalTone.attention
              : AdminOperationalTone.ok,
        ),
      ],
      actionLabel: 'Ver funcionarios',
      onAction: () => context.go('/companies/$companyId/users'),
    );
  }

  _SupportCard _syncCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminSyncCenterCompanySummary> syncAsync,
  ) {
    return _asyncCard<AdminSyncCenterCompanySummary>(
      icon: Icons.sync_problem_rounded,
      title: 'Sync Center',
      subtitle: 'Triagem de eventos e recomendacao atual.',
      value: syncAsync,
      metricsBuilder: (sync) => [
        _SupportMetric(
          label: 'Status',
          value: _operationalLabel(_syncSummaryTone(sync)),
          tone: _syncSummaryTone(sync),
        ),
        _SupportMetric(
          label: 'Pendentes',
          value: '${sync.eventStatusCounts.pending}',
        ),
        _SupportMetric(
          label: 'Falhas',
          value: '${sync.eventStatusCounts.failed}',
        ),
        _SupportMetric(
          label: 'Conflitos',
          value: '${sync.eventStatusCounts.conflict}',
        ),
        _SupportMetric(
          label: 'Requer revisao',
          value: sync.requiresReview ? 'Sim' : 'Nao',
          tone: sync.requiresReview
              ? AdminOperationalTone.attention
              : AdminOperationalTone.ok,
        ),
        _SupportMetric(label: 'Sugestao', value: _syncSummarySuggestion(sync)),
      ],
      actionLabel: 'Abrir Sync Center',
      onAction: () => context.go('/companies/$companyId/sync'),
    );
  }

  _SupportCard _conflictsCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminSyncCenterCompanySummary> syncAsync,
  ) {
    return _asyncCard<AdminSyncCenterCompanySummary>(
      icon: Icons.report_problem_rounded,
      title: 'Conflitos',
      subtitle: 'Conflitos abertos e historicos conhecidos pelo Sync Center.',
      value: syncAsync,
      metricsBuilder: (sync) {
        final open = sync.conflictCounts
            .where((conflict) => conflict.status.toLowerCase() == 'open')
            .fold<int>(0, (sum, conflict) => sum + conflict.count);
        final historical = sync.conflictCounts
            .where((conflict) => conflict.status.toLowerCase() != 'open')
            .fold<int>(0, (sum, conflict) => sum + conflict.count);
        return [
          _SupportMetric(label: 'Abertos', value: '$open'),
          _SupportMetric(label: 'Historico', value: '$historical'),
          _SupportMetric(
            label: 'Ultimos conflitos',
            value: '${sync.latestConflicts.length}',
          ),
          _SupportMetric(
            label: 'Status',
            value: open > 0 ? 'Atencao' : 'OK',
            tone: open > 0
                ? AdminOperationalTone.attention
                : AdminOperationalTone.ok,
          ),
        ];
      },
      actionLabel: 'Ver conflitos',
      onAction: () => context.go('/companies/$companyId/sync'),
    );
  }

  _SupportCard _auditCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminAuditLogPage> auditAsync,
  ) {
    return _asyncCard<AdminAuditLogPage>(
      icon: Icons.fact_check_rounded,
      title: 'Auditoria',
      subtitle: 'Eventos administrativos filtrados pela empresa.',
      value: auditAsync,
      metricsBuilder: (audit) => [
        _SupportMetric(
          label: 'Status',
          value: _operationalLabel(_auditTone(audit)),
          tone: _auditTone(audit),
        ),
        _SupportMetric(label: 'Eventos', value: '${audit.pagination.total}'),
        _SupportMetric(label: 'Nesta pagina', value: '${audit.items.length}'),
        _SupportMetric(label: 'Ultimo evento', value: _lastAuditEvent(audit)),
        _SupportMetric(label: 'Sugestao', value: _auditSuggestion(audit)),
      ],
      actionLabel: 'Abrir auditoria',
      onAction: () => context.go('/audit?companyId=$companyId'),
    );
  }

  _SupportCard _securityCard(BuildContext context, String companyId) {
    return _SupportCard(
      icon: Icons.shield_outlined,
      title: 'Seguranca operacional',
      subtitle: 'Politicas read-only para proteger dados sensiveis.',
      metrics: const [
        _SupportMetric(
          label: 'Status',
          value: 'Read-only',
          tone: AdminOperationalTone.ok,
        ),
        _SupportMetric(label: 'Dados sensiveis', value: 'Minimizados'),
        _SupportMetric(label: 'Acoes futuras', value: 'Dry-run e auditoria'),
        _SupportMetric(label: 'Logs', value: 'Sem tokens ou secrets'),
      ],
      actionLabel: 'Abrir auditoria',
      onAction: () => context.go('/audit?companyId=$companyId'),
    );
  }

  _SupportCard _observabilityCard(
    BuildContext context,
    String companyId,
    AsyncValue<AdminCompanySyncHealth> healthAsync,
    AsyncValue<AdminBillingCompanyStatus> billingAsync,
    AsyncValue<AdminPaginatedResult<AdminDeviceInventoryItem>> devicesAsync,
    AsyncValue<AdminAuditLogPage> auditAsync,
  ) {
    return _asyncCard<AdminCompanySyncHealth>(
      icon: Icons.monitor_heart_rounded,
      title: 'Observabilidade operacional',
      subtitle: 'Leitura read-only dos sinais de saude da empresa.',
      value: healthAsync,
      fallbackMetrics: const [
        _SupportMetric(
          label: 'Status',
          value: 'Sem dados',
          tone: AdminOperationalTone.noData,
        ),
        _SupportMetric(
          label: 'Sugestao',
          value: 'Dados insuficientes para avaliar saude operacional.',
        ),
      ],
      metricsBuilder: (health) {
        final billing = billingAsync.valueOrNull;
        final devices = devicesAsync.valueOrNull?.items;
        final audit = auditAsync.valueOrNull;
        final syncTone = _healthTone(health);
        final billingTone = _billingTone(billing);
        final devicesTone = devices == null
            ? AdminOperationalTone.noData
            : _deviceTone(devices);
        final auditTone = audit == null
            ? AdminOperationalTone.noData
            : _auditTone(audit);
        final tones = [syncTone, billingTone, devicesTone, auditTone];
        final generalTone = _overallObservabilityTone(tones);
        return [
          _SupportMetric(
            label: 'Saude geral',
            value: _operationalLabel(generalTone),
            tone: generalTone,
          ),
          _SupportMetric(
            label: 'Ultimo sync',
            value: health.lastSyncAt == null
                ? 'Sem sync recente'
                : AdminFormatters.formatDateTime(health.lastSyncAt),
          ),
          _SupportMetric(
            label: 'Sinais criticos',
            value:
                '${tones.where((tone) => tone == AdminOperationalTone.critical).length}',
            tone: tones.contains(AdminOperationalTone.critical)
                ? AdminOperationalTone.critical
                : AdminOperationalTone.ok,
          ),
          _SupportMetric(
            label: 'Sinais de atencao',
            value:
                '${tones.where((tone) => tone == AdminOperationalTone.attention).length}',
            tone: tones.contains(AdminOperationalTone.attention)
                ? AdminOperationalTone.attention
                : AdminOperationalTone.ok,
          ),
          _SupportMetric(
            label: 'Billing',
            value: _billingObservabilityLabel(billing),
            tone: billingTone,
          ),
          _SupportMetric(
            label: 'Auditoria recente',
            value: audit == null
                ? 'Indisponivel'
                : _operationalLabel(auditTone),
            tone: auditTone,
          ),
          _SupportMetric(
            label: 'Sugestao',
            value: _observabilitySuggestion(generalTone),
          ),
        ];
      },
      actionLabel: 'Abrir Sync Center',
      onAction: () => context.go('/companies/$companyId/sync'),
    );
  }

  _SupportCard _operationalStatusCard(
    BuildContext context,
    AsyncValue<AdminCompanySyncHealth> healthAsync,
    AsyncValue<AdminBillingCompanyStatus> billingAsync,
  ) {
    final billingStatus = billingAsync.valueOrNull?.billing;
    return _asyncCard<AdminCompanySyncHealth>(
      icon: Icons.health_and_safety_rounded,
      title: 'Status operacional',
      subtitle: 'Leitura consolidada para orientar o atendimento.',
      value: healthAsync,
      metricsBuilder: (health) => [
        _SupportMetric(label: 'Sync', value: _syncStatusLabel(health.status)),
        _SupportMetric(
          label: 'Ultimo sync',
          value: health.lastSyncAt == null
              ? 'Nenhum sync recente'
              : AdminFormatters.formatDateTime(health.lastSyncAt),
        ),
        _SupportMetric(
          label: 'Alertas sync',
          value:
              '${health.events.pending} pendencias / ${health.events.failed} falhas',
          tone: health.events.failed > 0 || health.openConflictsCount > 0
              ? AdminOperationalTone.critical
              : health.events.pending > 0
              ? AdminOperationalTone.attention
              : AdminOperationalTone.ok,
        ),
        _SupportMetric(
          label: 'Billing',
          value: billingStatus?.billingSubscriptionStatus ?? 'Nao informado',
        ),
        _SupportMetric(
          label: 'Status geral',
          value: _syncStatusLabel(health.status),
          tone: _syncTone(health.status),
        ),
        const _SupportMetric(
          label: 'Modo',
          value: 'Read-only',
          tone: AdminOperationalTone.ok,
        ),
      ],
    );
  }
}

class _SupportHeader extends ConsumerWidget {
  const _SupportHeader({required this.company});

  final AdminCompanySummary company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminSurface(
      title: 'Central de suporte da empresa',
      subtitle:
          'Hub operacional read-only para investigar ${company.name} sem executar comandos reais.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go('/companies/${company.id}'),
            icon: const Icon(Icons.apartment_rounded),
            label: const Text('Voltar para empresa'),
          ),
          FilledButton.tonalIcon(
            onPressed: () =>
                ref.read(adminRefreshTickProvider.notifier).state++,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text(company.slug)),
          Chip(
            label: Text(company.isActive ? 'Empresa ativa' : 'Empresa inativa'),
          ),
          Chip(
            label: Text(
              AdminFormatters.formatLicenseStatus(company.license?.status),
            ),
          ),
          const Chip(label: Text('Read-only')),
        ],
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Somente leitura nesta fase: sem revogar sessoes, forcar logout, reprocessar sync, alterar licenca ou executar comandos de suporte.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SupportGrid extends StatelessWidget {
  const _SupportGrid({required this.cards});

  final List<_SupportCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 3
            : constraints.maxWidth >= 760
            ? 2
            : 1;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards
              .map((card) => SizedBox(width: cardWidth, child: card))
              .toList(growable: false),
        );
      },
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_SupportMetric> metrics;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...metrics.map(
              (metric) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: metric.tone == null
                            ? Text(
                                metric.value,
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : AdminOperationalStatus(
                                label: metric.value,
                                tone: metric.tone!,
                                compact: true,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onAction,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupportMetric {
  const _SupportMetric({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final AdminOperationalTone? tone;
}

_SupportCard _asyncCard<T>({
  required IconData icon,
  required String title,
  required String subtitle,
  required AsyncValue<T> value,
  required List<_SupportMetric> Function(T value) metricsBuilder,
  List<_SupportMetric> fallbackMetrics = const [],
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return value.when(
    data: (data) => _SupportCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      metrics: metricsBuilder(data),
      actionLabel: actionLabel,
      onAction: onAction,
    ),
    loading: () => _SupportCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      metrics: fallbackMetrics.isEmpty
          ? const [_SupportMetric(label: 'Status', value: 'Carregando')]
          : fallbackMetrics,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
    error: (error, _) => _SupportCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      metrics: [
        ...fallbackMetrics,
        const _SupportMetric(label: 'Status', value: 'Indisponivel'),
      ],
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

String _syncStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'healthy':
      return 'Saudavel';
    case 'attention':
    case 'warning':
      return 'Atencao';
    case 'critical':
      return 'Critico';
    case 'disabled':
      return 'Sync desativada';
    default:
      return status;
  }
}

AdminOperationalTone _syncTone(String status) {
  switch (status.toLowerCase()) {
    case 'healthy':
      return AdminOperationalTone.ok;
    case 'attention':
    case 'warning':
      return AdminOperationalTone.attention;
    case 'critical':
      return AdminOperationalTone.critical;
    case 'disabled':
      return AdminOperationalTone.noData;
    default:
      return AdminOperationalTone.noData;
  }
}

AdminOperationalTone _healthTone(AdminCompanySyncHealth health) {
  if (health.events.failed > 0 || health.openConflictsCount > 0) {
    return AdminOperationalTone.critical;
  }
  if (health.events.pending > 0 || health.status.toLowerCase() == 'attention') {
    return AdminOperationalTone.attention;
  }
  if (health.lastSyncAt == null || !health.syncEnabled) {
    return AdminOperationalTone.noData;
  }
  return _syncTone(health.status);
}

AdminOperationalTone _billingTone(AdminBillingCompanyStatus? status) {
  if (status == null) {
    return AdminOperationalTone.noData;
  }
  final billing = status.billing;
  final subscriptionStatus = billing.billingSubscriptionStatus?.toLowerCase();
  if (billing.cancelAtPeriodEnd ||
      subscriptionStatus == 'cancelled' ||
      subscriptionStatus == 'canceled' ||
      subscriptionStatus == 'past_due' ||
      subscriptionStatus == 'unpaid' ||
      subscriptionStatus == 'failed') {
    return AdminOperationalTone.critical;
  }
  if (!billing.hasProviderSubscription ||
      billing.pendingPlan != null ||
      subscriptionStatus == 'pending' ||
      subscriptionStatus == 'in_process') {
    return AdminOperationalTone.attention;
  }
  return AdminOperationalTone.ok;
}

AdminOperationalTone _overallObservabilityTone(
  List<AdminOperationalTone> tones,
) {
  if (tones.contains(AdminOperationalTone.critical)) {
    return AdminOperationalTone.critical;
  }
  if (tones.every((tone) => tone == AdminOperationalTone.noData)) {
    return AdminOperationalTone.noData;
  }
  if (tones.contains(AdminOperationalTone.attention) ||
      tones.contains(AdminOperationalTone.noData)) {
    return AdminOperationalTone.attention;
  }
  return AdminOperationalTone.ok;
}

String _billingObservabilityLabel(AdminBillingCompanyStatus? status) {
  if (status == null) {
    return 'Indisponivel';
  }
  if (status.billing.billingSubscriptionStatus?.trim().isNotEmpty == true) {
    return status.billing.billingSubscriptionStatus!;
  }
  if (status.billing.hasProviderSubscription) {
    return 'Vinculado';
  }
  return 'Sem provider';
}

String _observabilitySuggestion(AdminOperationalTone tone) {
  return switch (tone) {
    AdminOperationalTone.ok => 'Operacao aparentemente saudavel.',
    AdminOperationalTone.attention =>
      'Ha sinais de atencao em sincronizacao, billing ou auditoria.',
    AdminOperationalTone.critical =>
      'Existem indicadores criticos. Priorize conflitos, erros ou pendencias.',
    AdminOperationalTone.noData =>
      'Dados insuficientes para avaliar saude operacional.',
  };
}

AdminOperationalTone _syncSummaryTone(AdminSyncCenterCompanySummary sync) {
  if (sync.eventStatusCounts.failed > 0 ||
      sync.eventStatusCounts.conflict > 0 ||
      sync.conflictCounts.any(
        (conflict) =>
            conflict.status.toLowerCase() == 'open' && conflict.count > 0,
      )) {
    return AdminOperationalTone.critical;
  }
  if (sync.eventStatusCounts.pending > 0 || sync.requiresReview) {
    return AdminOperationalTone.attention;
  }
  if (sync.eventStatusCounts.accepted == 0 &&
      sync.eventStatusCounts.duplicate == 0 &&
      sync.latestEvents.isEmpty) {
    return AdminOperationalTone.noData;
  }
  return AdminOperationalTone.ok;
}

String _operationalLabel(AdminOperationalTone tone) {
  return switch (tone) {
    AdminOperationalTone.ok => 'OK',
    AdminOperationalTone.attention => 'Atencao',
    AdminOperationalTone.critical => 'Critico',
    AdminOperationalTone.noData => 'Sem dados',
  };
}

String _syncSummarySuggestion(AdminSyncCenterCompanySummary sync) {
  final tone = _syncSummaryTone(sync);
  if (tone == AdminOperationalTone.noData) {
    return 'Sem dados recentes de sync.';
  }
  if (sync.eventStatusCounts.conflict > 0) {
    return 'Conflitos encontrados. Avaliar dados antes de qualquer acao.';
  }
  if (sync.eventStatusCounts.failed > 0) {
    return 'Empresa com erros de sync. Verifique dispositivos relacionados.';
  }
  if (sync.eventStatusCounts.pending > 0) {
    return 'Empresa com pendencias de sync. Verifique dispositivos relacionados.';
  }
  return 'Sincronizacao aparentemente saudavel.';
}

AdminOperationalTone _auditTone(AdminAuditLogPage audit) {
  if (audit.items.isEmpty) {
    return AdminOperationalTone.noData;
  }
  if (audit.overview.failures > 0 ||
      audit.items.any((entry) {
        final status = entry.status.toLowerCase();
        final action = entry.action.toLowerCase();
        return status == 'failed' ||
            action.contains('block') ||
            action.contains('suspend');
      })) {
    return AdminOperationalTone.critical;
  }
  if (audit.items.any(
    (entry) =>
        entry.status.toLowerCase() == 'pending' ||
        entry.status.toLowerCase() == 'running',
  )) {
    return AdminOperationalTone.attention;
  }
  return AdminOperationalTone.ok;
}

String _lastAuditEvent(AdminAuditLogPage audit) {
  if (audit.items.isEmpty) {
    return 'Sem eventos recentes';
  }
  final first = audit.items.first;
  final date = AdminFormatters.formatDateTime(first.createdAt);
  return '${_auditActionLabel(first.action)} - $date';
}

String _auditSuggestion(AdminAuditLogPage audit) {
  final tone = _auditTone(audit);
  if (tone == AdminOperationalTone.noData) {
    return 'Nenhum evento recente para esta empresa.';
  }
  if (tone == AdminOperationalTone.critical) {
    return 'Ha falhas ou acoes sensiveis recentes. Revisar detalhes antes de agir.';
  }
  if (tone == AdminOperationalTone.attention) {
    return 'Ha eventos pendentes ou em andamento. Acompanhar antes de nova acao.';
  }
  return 'Auditoria recente sem alertas criticos.';
}

String _auditActionLabel(String action) {
  switch (action) {
    case 'license.emergency_extension':
      return 'Extensao emergencial';
    case 'billing.reconcile':
      return 'Reconciliacao de billing';
    case 'access.block':
    case 'admin.access.block':
      return 'Bloqueio de acesso operacional';
    case 'access.reactivate':
    case 'admin.access.reactivate':
      return 'Reativacao de acesso operacional';
    case 'sync.support_command.created':
      return 'Comando de suporte criado';
    default:
      return action;
  }
}

AdminOperationalTone _deviceTone(List<AdminDeviceInventoryItem> devices) {
  if (devices.isEmpty) {
    return AdminOperationalTone.noData;
  }
  final critical = devices.any(
    (device) =>
        (device.diagnostic?.failedCount ?? 0) > 0 ||
        (device.diagnostic?.openConflictCount ?? 0) > 0,
  );
  if (critical) {
    return AdminOperationalTone.critical;
  }
  if (devices.any((device) => (device.diagnostic?.pendingCount ?? 0) > 0)) {
    return AdminOperationalTone.attention;
  }
  if (devices.any((device) => device.diagnostic == null)) {
    return AdminOperationalTone.noData;
  }
  return AdminOperationalTone.ok;
}

List<AdminDeviceInventoryItem> _androidDevices(
  List<AdminDeviceInventoryItem> devices,
) {
  return devices
      .where((device) => device.clientType.toUpperCase() == 'MOBILE_APP')
      .toList(growable: false);
}

AdminOperationalTone _androidVersionTone(
  List<AdminDeviceInventoryItem> devices,
) {
  if (devices.isEmpty) {
    return AdminOperationalTone.noData;
  }
  if (devices.any((device) => !_hasAppVersion(device.appVersion))) {
    return AdminOperationalTone.attention;
  }
  return AdminOperationalTone.ok;
}

String _oldestAndroidVersion(List<AdminDeviceInventoryItem> devices) {
  final versions =
      devices
          .map((device) => device.appVersion?.trim())
          .whereType<String>()
          .where((version) => version.isNotEmpty)
          .toList()
        ..sort(_compareVersionLabels);
  if (versions.isEmpty) {
    return 'Versao nao informada';
  }
  return versions.first;
}

String _androidVersionSuggestion(AdminOperationalTone tone) {
  return switch (tone) {
    AdminOperationalTone.ok => 'Versoes do app aparentemente compativeis.',
    AdminOperationalTone.attention => 'Ha dispositivos sem versao informada.',
    AdminOperationalTone.critical =>
      'Ha dispositivos potencialmente desatualizados.',
    AdminOperationalTone.noData =>
      'Controle real de versao depende de backend e Android.',
  };
}

bool _hasAppVersion(String? value) => value?.trim().isNotEmpty == true;

int _compareVersionLabels(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    final comparison = leftValue.compareTo(rightValue);
    if (comparison != 0) {
      return comparison;
    }
  }
  return left.compareTo(right);
}

List<int> _versionParts(String value) {
  return value
      .split(RegExp(r'[^0-9]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
}

String? _firstLocalError(List<AdminDeviceInventoryItem> devices) {
  for (final device in devices) {
    final value = device.diagnostic?.lastLocalError?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
