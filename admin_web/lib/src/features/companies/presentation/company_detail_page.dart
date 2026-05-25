import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_access_models.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';
import 'company_sync_health_tab.dart';

class CompanyDetailPage extends ConsumerWidget {
  const CompanyDetailPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminCompanyDetailProvider(companyId));
    return detail.when(
      data: (payload) => _CompanyDetailContent(payload: payload),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar a empresa',
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

class _CompanyDetailContent extends ConsumerWidget {
  const _CompanyDetailContent({required this.payload});

  final AdminCompanyDetail payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = payload.company;
    final license = company.license;

    return DefaultTabController(
      length: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompanyHeader(company: company),
          const SizedBox(height: 16),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.info_outline_rounded), text: 'Resumo'),
              Tab(icon: Icon(Icons.sync_rounded), text: 'Sync'),
              Tab(icon: Icon(Icons.workspace_premium_rounded), text: 'Licenca'),
              Tab(icon: Icon(Icons.devices_rounded), text: 'Dispositivos'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Funcionarios'),
              Tab(icon: Icon(Icons.fact_check_rounded), text: 'Auditoria'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(payload: payload),
                CompanySyncHealthTab(companyId: company.id),
                _LicenseTab(company: company, license: license),
                _DevicesTab(sessions: payload.sessions),
                _EmployeesTab(memberships: payload.memberships),
                const _AuditPlaceholder(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyHeader extends StatelessWidget {
  const _CompanyHeader({required this.company});

  final AdminCompanySummary company;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: company.name,
      subtitle: company.legalName,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => context.go('/companies/${company.id}/sync'),
            icon: const Icon(Icons.sync_problem_rounded),
            label: const Text('Abrir console de sync'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/companies/${company.id}/license'),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('Ver licenca e assinatura'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/companies/${company.id}/users'),
            icon: const Icon(Icons.people_alt_rounded),
            label: const Text('Ver usuarios e funcionarios'),
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
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.payload});

  final AdminCompanyDetail payload;

  @override
  Widget build(BuildContext context) {
    final company = payload.company;
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1000;
          final info = AdminSurface(
            title: 'Resumo da conta',
            child: Column(
              children: [
                _DetailRow(label: 'Tenant', value: company.slug),
                _DetailRow(
                  label: 'Documento',
                  value: company.documentNumber ?? 'Nao informado',
                ),
                _DetailRow(
                  label: 'Criada em',
                  value: AdminFormatters.formatDateTime(company.createdAt),
                ),
                _DetailRow(
                  label: 'Atualizada em',
                  value: AdminFormatters.formatDateTime(company.updatedAt),
                ),
              ],
            ),
          );
          final counts = AdminSurface(
            title: 'Dados remotos',
            subtitle: 'Contadores lidos da plataforma.',
            child: Column(
              children: [
                _CountRow(
                  label: 'Categorias',
                  value: company.counts.categories,
                ),
                _CountRow(label: 'Produtos', value: company.counts.products),
                _CountRow(label: 'Clientes', value: company.counts.customers),
                _CountRow(
                  label: 'Fornecedores',
                  value: company.counts.suppliers,
                ),
                _CountRow(label: 'Compras', value: company.counts.purchases),
                _CountRow(label: 'Vendas', value: company.counts.sales),
                const Divider(height: 22),
                _CountRow(
                  label: 'Total remoto',
                  value: company.counts.totalRemoteRecords,
                  emphasize: true,
                ),
              ],
            ),
          );
          final sync = _SyncSummaryCard(companyId: company.id);
          final licenseSummary = _CompanyLicenseSummaryCard(
            companyId: company.id,
            fallbackLicense: company.license,
          );
          final accessSummary = _CompanyAccessSummaryCard(
            companyId: company.id,
          );
          if (compact) {
            return Column(
              children: [
                info,
                const SizedBox(height: 16),
                counts,
                const SizedBox(height: 16),
                sync,
                const SizedBox(height: 16),
                licenseSummary,
                const SizedBox(height: 16),
                accessSummary,
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  Expanded(child: counts),
                ],
              ),
              const SizedBox(height: 16),
              sync,
              const SizedBox(height: 16),
              licenseSummary,
              const SizedBox(height: 16),
              accessSummary,
            ],
          );
        },
      ),
    );
  }
}

class _CompanyAccessSummaryCard extends ConsumerWidget {
  const _CompanyAccessSummaryCard({required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(adminCompanyAccessSummaryProvider(companyId));
    return accessAsync.when(
      data: (access) => _CompanyAccessSummarySurface(access: access),
      loading: () => const AdminSurface(
        title: 'Usuarios e funcionarios',
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => AdminSurface(
        title: 'Usuarios e funcionarios',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => context.go('/companies/$companyId/users'),
          icon: const Icon(Icons.people_alt_rounded),
          label: const Text('Ver usuarios e funcionarios'),
        ),
        child: const Text('Nao disponivel nesta versao.'),
      ),
    );
  }
}

class _CompanyAccessSummarySurface extends StatelessWidget {
  const _CompanyAccessSummarySurface({required this.access});

  final AdminCompanyAccessSummary access;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Usuarios e funcionarios',
      subtitle: 'Resumo read-only de contas, perfis e acesso.',
      trailing: FilledButton.tonalIcon(
        onPressed: () => context.go('/companies/${access.company.id}/users'),
        icon: const Icon(Icons.people_alt_rounded),
        label: const Text('Ver usuarios e funcionarios'),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniMetric(label: 'Usuarios', value: '${access.summary.totalUsers}'),
          _MiniMetric(
            label: 'Funcionarios',
            value: '${access.summary.totalEmployees}',
          ),
          _MiniMetric(
            label: 'Ativos',
            value: '${access.summary.activeEmployees}',
          ),
          _MiniMetric(
            label: 'Convidados',
            value: '${access.summary.invitedEmployees}',
          ),
          _MiniMetric(
            label: 'Desativados',
            value: '${access.summary.disabledEmployees}',
          ),
          _MiniMetric(label: 'Owners', value: '${access.summary.owners}'),
        ],
      ),
    );
  }
}

class _CompanyLicenseSummaryCard extends ConsumerWidget {
  const _CompanyLicenseSummaryCard({
    required this.companyId,
    required this.fallbackLicense,
  });

  final String companyId;
  final AdminLicenseSnapshot? fallbackLicense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billingAsync = ref.watch(
      adminBillingCompanyStatusProvider(companyId),
    );
    return billingAsync.when(
      data: (status) => _CompanyLicenseSummarySurface(
        companyId: companyId,
        status: status,
        fallbackLicense: fallbackLicense,
      ),
      loading: () => const AdminSurface(
        title: 'Licenca e assinatura',
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => AdminSurface(
        title: 'Licenca e assinatura',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () => context.go('/companies/$companyId/license'),
          icon: const Icon(Icons.workspace_premium_rounded),
          label: const Text('Ver licenca e assinatura'),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MiniMetric(
              label: 'Plano ativo',
              value: fallbackLicense == null
                  ? 'Nao disponivel'
                  : AdminFormatters.formatPlan(fallbackLicense!.plan),
            ),
            _MiniMetric(
              label: 'Status',
              value: AdminFormatters.formatLicenseStatus(
                fallbackLicense?.status,
              ),
            ),
            const _MiniMetric(label: 'Billing', value: 'Nao disponivel'),
          ],
        ),
      ),
    );
  }
}

class _CompanyLicenseSummarySurface extends StatelessWidget {
  const _CompanyLicenseSummarySurface({
    required this.companyId,
    required this.status,
    required this.fallbackLicense,
  });

  final String companyId;
  final AdminBillingCompanyStatus status;
  final AdminLicenseSnapshot? fallbackLicense;

  @override
  Widget build(BuildContext context) {
    final billing = status.billing;
    final license = status.license;
    final plan = license?.plan ?? fallbackLicense?.plan ?? '';
    final licenseStatus = license?.status ?? fallbackLicense?.status;
    final pendingPlan = license?.pendingPlan ?? billing.pendingPlan;
    final periodEnd = billing.currentPeriodEnd ?? license?.currentPeriodEnd;
    return AdminSurface(
      title: 'Licenca e assinatura',
      subtitle: 'Resumo read-only. pendingPlan nao e tratado como plano ativo.',
      trailing: FilledButton.tonalIcon(
        onPressed: () => context.go('/companies/$companyId/license'),
        icon: const Icon(Icons.workspace_premium_rounded),
        label: const Text('Ver licenca e assinatura'),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniMetric(
            label: 'Plano ativo',
            value: plan.isEmpty
                ? 'Nao disponivel'
                : AdminFormatters.formatPlan(plan),
          ),
          _MiniMetric(
            label: 'Status',
            value: AdminFormatters.formatLicenseStatus(licenseStatus),
          ),
          _MiniMetric(
            label: 'Mudanca pendente',
            value: pendingPlan == null
                ? 'Nenhuma'
                : AdminFormatters.formatPlan(pendingPlan),
          ),
          _MiniMetric(
            label: 'Status assinatura',
            value: billing.billingSubscriptionStatus ?? 'Nao disponivel',
          ),
          _MiniMetric(
            label: 'Fim do periodo',
            value: AdminFormatters.formatDate(periodEnd),
          ),
          _MiniMetric(
            label: 'Cancelamento',
            value: billing.cancelAtPeriodEnd
                ? 'Cancelamento agendado'
                : 'Nao agendado',
          ),
        ],
      ),
    );
  }
}

class _SyncSummaryCard extends ConsumerWidget {
  const _SyncSummaryCard({required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncAsync = ref.watch(adminCompanySyncHealthProvider(companyId));
    return syncAsync.when(
      data: (health) => AdminSurface(
        title: 'Resumo de sync',
        subtitle: 'Dados read-only do endpoint de saude por empresa.',
        trailing: FilledButton.tonalIcon(
          onPressed: () => context.go('/companies/$companyId/sync'),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Abrir console de sync'),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MiniMetric(
              label: 'Status',
              value: _syncStatusLabel(health.status),
            ),
            _MiniMetric(
              label: 'Conflitos abertos',
              value: '${health.openConflictsCount}',
            ),
            _MiniMetric(
              label: 'Incidentes recentes',
              value: health.lastIncident == null ? 'Sem dados' : '1',
            ),
            _MiniMetric(
              label: 'Dispositivos',
              value: '${health.devices.total}',
            ),
            _MiniMetric(
              label: 'Ultimo evento',
              value: AdminFormatters.formatDateTime(health.lastSyncAt),
            ),
          ],
        ),
      ),
      loading: () => const AdminSurface(
        title: 'Resumo de sync',
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => AdminSurface(
        title: 'Resumo de sync',
        subtitle: _safeError(error),
        child: const Text('Resumo indisponivel nesta versao.'),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseTab extends StatelessWidget {
  const _LicenseTab({required this.company, required this.license});

  final AdminCompanySummary company;
  final AdminLicenseSnapshot? license;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Licenca read-only',
        subtitle: 'Plano, status, validade e limites sem edicao real.',
        trailing: FilledButton.tonalIcon(
          onPressed: () => context.go('/companies/${company.id}/license'),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Abrir detalhe'),
        ),
        child: license == null
            ? const _EmptyState(message: 'Empresa sem licenca cadastrada.')
            : Column(
                children: [
                  _DetailRow(
                    label: 'Plano atual',
                    value: AdminFormatters.formatPlan(license!.plan),
                  ),
                  _DetailRow(
                    label: 'Status',
                    value: AdminFormatters.formatLicenseStatus(license!.status),
                  ),
                  _DetailRow(
                    label: 'Inicio',
                    value: AdminFormatters.formatDate(license!.startsAt),
                  ),
                  _DetailRow(
                    label: 'Vencimento',
                    value: AdminFormatters.formatDate(license!.expiresAt),
                  ),
                  _DetailRow(
                    label: 'Sync cloud',
                    value: AdminFormatters.formatBool(
                      license!.syncEnabled,
                      yes: 'Habilitada',
                      no: 'Desativada',
                    ),
                  ),
                  _DetailRow(
                    label: 'Max dispositivos',
                    value: license!.maxDevices?.toString() ?? 'Livre',
                  ),
                ],
              ),
      ),
    );
  }
}

class _DevicesTab extends StatelessWidget {
  const _DevicesTab({required this.sessions});

  final List<AdminDeviceSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const SingleChildScrollView(
        child: AdminSurface(
          title: 'Dispositivos',
          child: _EmptyState(message: 'Nenhuma sessao registrada.'),
        ),
      );
    }
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Sessoes e dispositivos',
        subtitle: 'MOBILE_APP e ADMIN_WEB aparecem separados para suporte.',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Dispositivo')),
              DataColumn(label: Text('Tipo')),
              DataColumn(label: Text('Plataforma')),
              DataColumn(label: Text('Versao')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Ultimo acesso')),
              DataColumn(label: Text('Usuario')),
            ],
            rows: sessions
                .map((session) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(session.deviceLabel ?? session.clientInstanceId),
                      ),
                      DataCell(Text(_clientTypeLabel(session.clientType))),
                      DataCell(Text(session.platform ?? 'Nao informado')),
                      DataCell(Text(session.appVersion ?? 'Nao informado')),
                      DataCell(Text(_sessionStatusLabel(session.status))),
                      DataCell(
                        Text(
                          AdminFormatters.formatDateTime(session.lastSeenAt),
                        ),
                      ),
                      DataCell(Text(session.userName)),
                    ],
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab({required this.memberships});

  final List<AdminMembershipSummary> memberships;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Funcionarios',
        subtitle: 'Acesso remoto e papeis vinculados a empresa.',
        child: memberships.isEmpty
            ? const _EmptyState(message: 'Nenhum funcionario vinculado.')
            : Column(
                children: memberships
                    .map((membership) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(membership.userName),
                        subtitle: Text(membership.userEmail),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                AdminFormatters.formatMembershipRole(
                                  membership.role,
                                ),
                              ),
                            ),
                            if (membership.isDefault)
                              const Chip(label: Text('Padrao')),
                          ],
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
      ),
    );
  }
}

class _AuditPlaceholder extends StatelessWidget {
  const _AuditPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: AdminSurface(
        title: 'Auditoria',
        subtitle: 'Historico administrativo por empresa.',
        child: _EmptyState(
          message:
              'Use a tela Auditoria para consultar eventos globais. A trilha por empresa sera consolidada aqui em fase posterior.',
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Text(message),
    );
  }
}

String _clientTypeLabel(String value) {
  switch (value.toLowerCase()) {
    case 'mobile_app':
      return 'MOBILE_APP';
    case 'admin_web':
      return 'ADMIN_WEB';
    default:
      return value.toUpperCase();
  }
}

String _sessionStatusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Ativa';
    case 'revoked':
      return 'Revogada';
    case 'expired':
      return 'Expirada';
    default:
      return status;
  }
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

String _safeError(Object error) {
  final message = error.toString();
  if (message.contains('Exception:')) {
    return message.split('Exception:').last.trim();
  }
  return message;
}
