import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_access_models.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_surface.dart';

const _futureActionMessage =
    'Acao administrativa sera implementada em fase posterior com dry-run, confirmacao explicita e auditoria.';

class CompanyUsersPage extends ConsumerWidget {
  const CompanyUsersPage({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(adminCompanyAccessSummaryProvider(companyId));
    return accessAsync.when(
      data: (access) => DefaultTabController(
        length: 6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(access: access),
            const SizedBox(height: 16),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Resumo'),
                Tab(icon: Icon(Icons.people_alt_rounded), text: 'Usuarios'),
                Tab(icon: Icon(Icons.badge_rounded), text: 'Funcionarios'),
                Tab(
                  icon: Icon(Icons.verified_user_rounded),
                  text: 'Permissoes',
                ),
                Tab(icon: Icon(Icons.devices_rounded), text: 'Dispositivos'),
                Tab(icon: Icon(Icons.fact_check_rounded), text: 'Auditoria'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _SummaryTab(access: access),
                  _UsersTab(
                    companyId: access.company.id,
                    users: access.users,
                    auditEvents: access.audit,
                  ),
                  _EmployeesTab(
                    companyId: access.company.id,
                    employees: access.employees,
                    auditEvents: access.audit,
                  ),
                  _PermissionsTab(access: access),
                  _DevicesTab(devices: access.devices),
                  _AuditTab(companyId: access.company.id, events: access.audit),
                ],
              ),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar usuarios e funcionarios',
        subtitle: _safeError(error),
        trailing: FilledButton.tonalIcon(
          onPressed: () =>
              ref.invalidate(adminCompanyAccessSummaryProvider(companyId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
        child: const Text('Nenhum payload sensivel foi exibido.'),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.access});

  final AdminCompanyAccessSummary access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminSurface(
      title: access.company.name,
      subtitle:
          'Usuarios, funcionarios e permissoes read-only. CompanyId ${_maskIdentifier(access.company.id)}.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go('/companies/${access.company.id}'),
            icon: const Icon(Icons.business_rounded),
            label: const Text('Voltar para empresa'),
          ),
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(
              adminCompanyAccessSummaryProvider(access.company.id),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go(
              '/audit?companyId=${access.company.id}&category=access',
            ),
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text('Ver auditoria global filtrada'),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('Usuarios: ${access.summary.totalUsers}')),
          Chip(label: Text('Funcionarios: ${access.summary.totalEmployees}')),
          Chip(label: Text('Ativos: ${access.summary.activeEmployees}')),
          Chip(label: Text('Convidados: ${access.summary.invitedEmployees}')),
          Chip(label: Text('Desativados: ${access.summary.disabledEmployees}')),
          if ((access.company.licensePlan ?? '').toUpperCase() != 'PRO')
            const Chip(label: Text('Plano atual nao libera Funcionarios PRO')),
          if (access.company.pendingPlan?.toUpperCase() == 'PRO')
            const Chip(label: Text('pendingPlan PRO nao libera recursos')),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.access});

  final AdminCompanyAccessSummary access;

  @override
  Widget build(BuildContext context) {
    final alerts = _buildAlerts(access);
    return SingleChildScrollView(
      child: Column(
        children: [
          AdminSurface(
            title: 'Resumo de acessos',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(label: 'Dono/OWNER', value: '${access.summary.owners}'),
                _Metric(
                  label: 'Administradores',
                  value: '${access.summary.admins}',
                ),
                _Metric(
                  label: 'Operadores',
                  value: '${access.summary.operators}',
                ),
                _Metric(
                  label: 'Funcionarios ativos',
                  value: '${access.summary.activeEmployees}',
                ),
                _Metric(
                  label: 'Convites pendentes',
                  value: '${access.summary.invitedEmployees}',
                ),
                _Metric(
                  label: 'Desativados',
                  value: '${access.summary.disabledEmployees}',
                ),
                _Metric(
                  label: 'Usuarios sem perfil',
                  value: '${access.summary.usersWithoutEmployeeProfile}',
                ),
                _Metric(
                  label: 'Perfis sem conta',
                  value: '${access.summary.employeeProfilesWithoutUser}',
                ),
                _Metric(
                  label: 'Ultimo acesso',
                  value: AdminFormatters.formatDateTime(
                    access.summary.lastSeenAt,
                  ),
                ),
                _Metric(
                  label: 'Ultima alteracao de permissao',
                  value: AdminFormatters.formatDateTime(
                    access.summary.lastPermissionChangeAt,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdminSurface(
            title: 'Alertas de suporte',
            child: alerts.isEmpty
                ? const Text('Nenhum alerta de acesso encontrado.')
                : Column(
                    children: alerts
                        .map(
                          (alert) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.info_outline_rounded),
                            title: Text(alert),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab({
    required this.companyId,
    required this.users,
    required this.auditEvents,
  });

  final String companyId;
  final List<AdminCompanyAccessUser> users;
  final List<AdminCompanyAccessAuditEvent> auditEvents;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String _filter = 'all';
  late final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.users.where(_matches).toList(growable: false);
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Usuarios',
        subtitle: 'Contas e memberships read-only.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UserFilters(
              searchController: _searchController,
              filter: _filter,
              onChanged: (value) => setState(() => _filter = value),
              onSearch: () => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (users.isEmpty)
              const _EmptyState(message: 'Nenhum usuario encontrado.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Nome')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Papel')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Ultimo acesso')),
                    DataColumn(label: Text('Dispositivos')),
                    DataColumn(label: Text('Criado em')),
                    DataColumn(label: Text('Acao')),
                  ],
                  rows: users
                      .map(
                        (user) => DataRow(
                          cells: [
                            DataCell(_NameWithOwnerBadge(user)),
                            DataCell(Text(user.email)),
                            DataCell(Text(_roleLabel(user.membershipRole))),
                            DataCell(Text(_statusLabel(user.accountStatus))),
                            DataCell(
                              Text(
                                AdminFormatters.formatDateTime(user.lastSeenAt),
                              ),
                            ),
                            DataCell(Text('${user.devices.length}')),
                            DataCell(
                              Text(AdminFormatters.formatDate(user.createdAt)),
                            ),
                            DataCell(
                              TextButton.icon(
                                onPressed: () => _showUserDetails(
                                  context,
                                  companyId: widget.companyId,
                                  user: user,
                                  auditEvents: widget.auditEvents,
                                ),
                                icon: const Icon(Icons.visibility_rounded),
                                label: const Text('Detalhes'),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _matches(AdminCompanyAccessUser user) {
    final search = _searchController.text.trim().toLowerCase();
    final matchesSearch =
        search.isEmpty ||
        user.name.toLowerCase().contains(search) ||
        user.email.toLowerCase().contains(search);
    final matchesFilter = switch (_filter) {
      'owners' => user.isOwner,
      'admins' => user.membershipRole == 'ADMIN',
      'operators' => user.membershipRole == 'OPERATOR',
      'active' => user.accountStatus == 'ACTIVE',
      'inactive' => user.accountStatus != 'ACTIVE',
      'invited' => user.invitationStatus != null,
      'withoutEmployee' => !user.hasEmployeeProfile,
      _ => true,
    };
    return matchesSearch && matchesFilter;
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab({
    required this.companyId,
    required this.employees,
    required this.auditEvents,
  });

  final String companyId;
  final List<AdminCompanyAccessEmployee> employees;
  final List<AdminCompanyAccessAuditEvent> auditEvents;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Funcionarios',
        subtitle: 'Perfis, convites e permissoes efetivas em leitura.',
        child: employees.isEmpty
            ? const _EmptyState(message: 'Nenhum funcionario encontrado.')
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Nome')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Telefone')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Permissoes efetivas')),
                    DataColumn(label: Text('Conta')),
                    DataColumn(label: Text('Convite')),
                    DataColumn(label: Text('Criado em')),
                    DataColumn(label: Text('Atualizado em')),
                    DataColumn(label: Text('Acao')),
                  ],
                  rows: employees
                      .map(
                        (employee) => DataRow(
                          cells: [
                            DataCell(_EmployeeName(employee: employee)),
                            DataCell(Text(employee.email ?? 'Nao informado')),
                            DataCell(Text(employee.phone ?? 'Nao informado')),
                            DataCell(
                              Text(_employeeRoleLabel(employee.employeeRole)),
                            ),
                            DataCell(Text(_statusLabel(employee.status))),
                            DataCell(
                              Text(
                                employee.status == 'DISABLED'
                                    ? 'Bloqueadas'
                                    : '${employee.effectivePermissions.length}',
                              ),
                            ),
                            DataCell(
                              Text(
                                employee.hasUserAccount
                                    ? 'Conta vinculada'
                                    : 'Sem conta',
                              ),
                            ),
                            DataCell(
                              Text(employee.invitationStatus ?? 'Sem convite'),
                            ),
                            DataCell(
                              Text(
                                AdminFormatters.formatDate(employee.createdAt),
                              ),
                            ),
                            DataCell(
                              Text(
                                AdminFormatters.formatDate(employee.updatedAt),
                              ),
                            ),
                            DataCell(
                              TextButton.icon(
                                onPressed: () => _showEmployeeDetails(
                                  context,
                                  companyId: companyId,
                                  employee: employee,
                                  auditEvents: auditEvents,
                                ),
                                icon: const Icon(Icons.visibility_rounded),
                                label: const Text('Detalhes'),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      ),
    );
  }
}

class _PermissionsTab extends StatelessWidget {
  const _PermissionsTab({required this.access});

  final AdminCompanyAccessSummary access;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Permissoes read-only',
        subtitle:
            'OWNER tem todas as permissoes por regra. DISABLED nao possui permissoes efetivas.',
        child: access.permissionsCatalog.isEmpty
            ? const _EmptyState(message: 'Nenhuma permissao retornada.')
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Permissao')),
                    DataColumn(label: Text('OWNER')),
                    DataColumn(label: Text('ADMIN')),
                    DataColumn(label: Text('OPERATOR')),
                    DataColumn(label: Text('Descricao')),
                  ],
                  rows: access.permissionsCatalog
                      .map(
                        (permission) => DataRow(
                          cells: [
                            DataCell(Text(permission.key)),
                            DataCell(_permissionIcon(permission.owner)),
                            DataCell(_permissionIcon(permission.admin)),
                            DataCell(_permissionIcon(permission.operator)),
                            DataCell(
                              Text(
                                permission.description.isEmpty
                                    ? 'Nao reconhecida'
                                    : permission.description,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      ),
    );
  }
}

class _DevicesTab extends StatelessWidget {
  const _DevicesTab({required this.devices});

  final List<AdminCompanyAccessDevice> devices;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Dispositivos por usuario',
        child: devices.isEmpty
            ? const _EmptyState(
                message:
                    'Nao ha dispositivos vinculados a usuarios nesta versao.',
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Dispositivo')),
                    DataColumn(label: Text('Tipo')),
                    DataColumn(label: Text('Plataforma')),
                    DataColumn(label: Text('Versao')),
                    DataColumn(label: Text('Usuario')),
                    DataColumn(label: Text('Client instance')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Ultimo acesso')),
                  ],
                  rows: devices
                      .map(
                        (device) => DataRow(
                          cells: [
                            DataCell(Text(device.deviceLabel ?? 'Sem label')),
                            DataCell(Text(_clientTypeLabel(device.clientType))),
                            DataCell(Text(device.platform ?? 'Nao informado')),
                            DataCell(
                              Text(device.appVersion ?? 'Nao informado'),
                            ),
                            DataCell(Text(device.userName)),
                            DataCell(
                              Text(_maskIdentifier(device.clientInstanceId)),
                            ),
                            DataCell(Text(_statusLabel(device.status))),
                            DataCell(
                              Text(
                                AdminFormatters.formatDateTime(
                                  device.lastSeenAt,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      ),
    );
  }
}

class _AuditTab extends ConsumerWidget {
  const _AuditTab({required this.companyId, required this.events});

  final String companyId;
  final List<AdminCompanyAccessAuditEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Historico administrativo',
        subtitle: events.isEmpty
            ? 'Nenhuma acao administrativa de acesso registrada.'
            : 'Acoes feitas por platform admin sobre usuarios, funcionarios e acessos.',
        trailing: OutlinedButton.icon(
          onPressed: () =>
              ref.invalidate(adminCompanyAccessSummaryProvider(companyId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Atualizar'),
        ),
        child: events.isEmpty
            ? const _EmptyState(
                message: 'Nenhuma acao administrativa de acesso registrada.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: events
                    .map(
                      (event) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.fact_check_rounded),
                          title: Text(_accessAuditActionLabel(event.action)),
                          subtitle: Text(
                            [
                              'Alvo: ${event.target ?? 'Nao informado'}',
                              'Ator: ${event.actorName ?? 'Sistema'}',
                              'Motivo: ${event.reason ?? 'Nao informado'}',
                              AdminFormatters.formatDateTime(event.createdAt),
                            ].join(' | '),
                          ),
                          trailing: TextButton.icon(
                            onPressed: () =>
                                _showAccessAuditDetails(context, event),
                            icon: const Icon(Icons.visibility_rounded),
                            label: const Text('Detalhes'),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
      ),
    );
  }
}

void _showAccessAuditDetails(
  BuildContext context,
  AdminCompanyAccessAuditEvent event,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_accessAuditActionLabel(event.action)),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailLineWidget(
                label: 'Data/hora',
                value: AdminFormatters.formatDateTime(event.createdAt),
              ),
              _DetailLineWidget(
                label: 'Ator',
                value: event.actorName ?? event.actorEmail ?? 'Sistema',
              ),
              _DetailLineWidget(
                label: 'Alvo',
                value: event.target ?? event.targetEmail ?? 'Nao informado',
              ),
              _DetailLineWidget(
                label: 'Motivo',
                value: event.reason ?? 'Nao informado',
              ),
              const SizedBox(height: 12),
              const Text('Dados sensiveis sao omitidos por seguranca.'),
              const SizedBox(height: 12),
              _JsonPreview(title: 'Antes', value: event.before),
              _JsonPreview(title: 'Depois', value: event.after),
              _JsonPreview(title: 'Metadata', value: event.metadata),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

class _UserFilters extends StatelessWidget {
  const _UserFilters({
    required this.searchController,
    required this.filter,
    required this.onChanged,
    required this.onSearch,
  });

  final TextEditingController searchController;
  final String filter;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Buscar por nome/e-mail',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        DropdownButton<String>(
          value: filter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Todos')),
            DropdownMenuItem(value: 'owners', child: Text('Owners')),
            DropdownMenuItem(value: 'admins', child: Text('Admins')),
            DropdownMenuItem(value: 'operators', child: Text('Operadores')),
            DropdownMenuItem(value: 'active', child: Text('Ativos')),
            DropdownMenuItem(
              value: 'inactive',
              child: Text('Inativos/desativados'),
            ),
            DropdownMenuItem(value: 'invited', child: Text('Convidados')),
            DropdownMenuItem(
              value: 'withoutEmployee',
              child: Text('Sem perfil de funcionario'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
        FilledButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _NameWithOwnerBadge extends StatelessWidget {
  const _NameWithOwnerBadge(this.user);

  final AdminCompanyAccessUser user;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(user.name),
        if (user.isProtectedOwner) ...[
          const SizedBox(width: 8),
          const Chip(label: Text('Protegido')),
        ],
      ],
    );
  }
}

class _EmployeeName extends StatelessWidget {
  const _EmployeeName({required this.employee});

  final AdminCompanyAccessEmployee employee;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(employee.name),
        if (employee.isProtectedOwner) ...[
          const SizedBox(width: 8),
          const Chip(label: Text('Protegido')),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}

Widget _permissionIcon(bool allowed) {
  return Icon(
    allowed ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
    color: allowed ? Colors.green.shade700 : Colors.grey.shade500,
  );
}

List<String> _buildAlerts(AdminCompanyAccessSummary access) {
  final alerts = <String>[];
  if (access.summary.owners == 0) {
    alerts.add('Empresa sem OWNER identificado');
  }
  if (access.summary.invitedEmployees > 0) {
    alerts.add('Funcionario convidado sem conta ativa');
  }
  if (access.users.any((user) => user.isProtectedOwner)) {
    alerts.add('Usuario com perfil protegido');
  }
  if (access.employees.any(_permissionsDiffer)) {
    alerts.add('Permissoes efetivas diferentes do papel salvo');
  }
  if ((access.company.licensePlan ?? '').toUpperCase() != 'PRO') {
    alerts.add('Plano atual nao libera Funcionarios PRO');
  }
  return alerts;
}

bool _permissionsDiffer(AdminCompanyAccessEmployee employee) {
  if (employee.status == 'DISABLED') {
    return employee.effectivePermissions.isNotEmpty;
  }
  if (employee.savedPermissions.isEmpty) {
    return false;
  }
  return employee.savedPermissions.length !=
      employee.effectivePermissions.length;
}

void _showUserDetails(
  BuildContext context, {
  required String companyId,
  required AdminCompanyAccessUser user,
  required List<AdminCompanyAccessAuditEvent> auditEvents,
}) {
  _showDetails(
    context,
    companyId: companyId,
    title: user.name,
    target: _AccessActionTarget(
      targetId: user.employeeProfileId ?? user.membershipId,
      targetType: user.employeeProfileId == null ? 'MEMBERSHIP' : 'EMPLOYEE',
      status: user.status,
      isProtectedOwner: user.isProtectedOwner,
      canUseAccessActions: user.employeeProfileId != null,
      unavailableReason: user.employeeProfileId == null
          ? 'Este usuario ainda nao tem EmployeeProfile vinculado; nao ha campo seguro por empresa para bloquear nesta fase.'
          : null,
    ),
    rows: [
      _DetailLine('UserId', _maskIdentifier(user.userId)),
      _DetailLine('Membership', _maskIdentifier(user.membershipId)),
      _DetailLine('Papel', _roleLabel(user.membershipRole)),
      _DetailLine('Status', _statusLabel(user.accountStatus)),
      _DetailLine(
        'Ultimo acesso',
        AdminFormatters.formatDateTime(user.lastSeenAt),
      ),
      _DetailLine('Dispositivos', '${user.devices.length}'),
      _DetailLine('Permissoes efetivas', user.effectivePermissions.join(', ')),
    ],
    auditEvents: _latestAuditForAccess(
      auditEvents,
      userId: user.userId,
      employeeProfileId: user.employeeProfileId,
      membershipId: user.membershipId,
    ),
  );
}

void _showEmployeeDetails(
  BuildContext context, {
  required String companyId,
  required AdminCompanyAccessEmployee employee,
  required List<AdminCompanyAccessAuditEvent> auditEvents,
}) {
  _showDetails(
    context,
    companyId: companyId,
    title: employee.name,
    target: _AccessActionTarget(
      targetId: employee.employeeProfileId,
      targetType: 'EMPLOYEE',
      status: employee.status,
      isProtectedOwner: employee.isProtectedOwner,
      canUseAccessActions: true,
    ),
    rows: [
      _DetailLine('Perfil', _maskIdentifier(employee.employeeProfileId)),
      _DetailLine('Role', _employeeRoleLabel(employee.employeeRole)),
      _DetailLine('Status', _statusLabel(employee.status)),
      _DetailLine('Conta', employee.hasUserAccount ? 'Vinculada' : 'Sem conta'),
      _DetailLine('Permissoes salvas', employee.savedPermissions.join(', ')),
      _DetailLine(
        'Permissoes efetivas',
        employee.status == 'DISABLED'
            ? 'Bloqueadas'
            : employee.effectivePermissions.join(', '),
      ),
    ],
    auditEvents: _latestAuditForAccess(
      auditEvents,
      userId: employee.userId,
      employeeProfileId: employee.employeeProfileId,
      membershipId: employee.membershipId,
    ),
  );
}

void _showDetails(
  BuildContext context, {
  required String companyId,
  required String title,
  required _AccessActionTarget target,
  required List<_DetailLine> rows,
  required List<AdminCompanyAccessAuditEvent> auditEvents,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...rows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('${row.label}: ${row.value}'),
                ),
              ),
              const Divider(),
              _LatestAccessAudit(events: auditEvents),
              const Divider(),
              const Text(
                'Esta acao bloqueia ou reativa o acesso operacional desta empresa. Nao apaga dados, nao altera senha, nao remove o usuario e nao revoga sessoes nesta fase.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _PlaceholderButton('Resetar senha'),
                  ..._accessActionButtons(
                    context,
                    companyId: companyId,
                    target: target,
                  ),
                  const _PlaceholderButton('Alterar papel'),
                  const _PlaceholderButton('Alterar permissoes'),
                  const _PlaceholderButton('Reenviar convite'),
                  const _PlaceholderButton('Remover funcionario'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

List<Widget> _accessActionButtons(
  BuildContext context, {
  required String companyId,
  required _AccessActionTarget target,
}) {
  if (target.isProtectedOwner) {
    return const [
      _BlockedAccessButton(
        label: 'Bloquear acesso operacional',
        reason: 'OWNER protegido nao pode ser bloqueado por esta acao.',
      ),
    ];
  }
  if (!target.canUseAccessActions) {
    return [
      _BlockedAccessButton(
        label: 'Bloquear acesso operacional',
        reason: target.unavailableReason ?? 'Acao indisponivel nesta fase.',
      ),
    ];
  }
  if (target.status.toUpperCase() == 'DISABLED') {
    return [
      _AccessActionButton(
        label: 'Reativar acesso operacional',
        companyId: companyId,
        target: target,
        spec: _AccessActionSpec.reactivate,
      ),
    ];
  }
  return [
    _AccessActionButton(
      label: 'Bloquear acesso operacional',
      companyId: companyId,
      target: target,
      spec: _AccessActionSpec.block,
    ),
  ];
}

class _AccessActionButton extends StatelessWidget {
  const _AccessActionButton({
    required this.label,
    required this.companyId,
    required this.target,
    required this.spec,
  });

  final String label;
  final String companyId;
  final _AccessActionTarget target;
  final _AccessActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: () => _showAccessActionDialog(
        context,
        companyId: companyId,
        target: target,
        spec: spec,
      ),
      child: Text(label),
    );
  }
}

class _BlockedAccessButton extends StatelessWidget {
  const _BlockedAccessButton({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: OutlinedButton(onPressed: null, child: Text('$label bloqueado')),
    );
  }
}

void _showAccessActionDialog(
  BuildContext context, {
  required String companyId,
  required _AccessActionTarget target,
  required _AccessActionSpec spec,
}) {
  final apiService = ProviderScope.containerOf(
    context,
  ).read(adminApiServiceProvider);
  final reasonController = TextEditingController();
  final noteController = TextEditingController();
  final confirmationController = TextEditingController();
  AdminAccessActionDryRun? dryRun;
  bool loadingDryRun = false;
  bool submitting = false;
  String? errorMessage;

  Future<void> executeDryRun(StateSetter setState) async {
    setState(() {
      loadingDryRun = true;
      errorMessage = null;
      dryRun = null;
    });
    try {
      final result = spec == _AccessActionSpec.block
          ? await apiService.dryRunAccessBlock(
              companyId: companyId,
              targetId: target.targetId,
              targetType: target.targetType,
              reason: reasonController.text,
              note: noteController.text,
            )
          : await apiService.dryRunAccessReactivate(
              companyId: companyId,
              targetId: target.targetId,
              targetType: target.targetType,
              reason: reasonController.text,
              note: noteController.text,
            );
      setState(() => dryRun = result);
    } catch (error) {
      setState(() => errorMessage = _safeError(error));
    } finally {
      setState(() => loadingDryRun = false);
    }
  }

  Future<void> submit(StateSetter setState, BuildContext dialogContext) async {
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    var closed = false;
    try {
      final result = spec == _AccessActionSpec.block
          ? await apiService.applyAccessBlock(
              companyId: companyId,
              targetId: target.targetId,
              targetType: target.targetType,
              reason: reasonController.text,
              note: noteController.text,
              confirmationText: confirmationController.text,
            )
          : await apiService.applyAccessReactivate(
              companyId: companyId,
              targetId: target.targetId,
              targetType: target.targetType,
              reason: reasonController.text,
              note: noteController.text,
              confirmationText: confirmationController.text,
            );
      if (!dialogContext.mounted || !context.mounted) {
        return;
      }
      ProviderScope.containerOf(
        dialogContext,
      ).invalidate(adminCompanyAccessSummaryProvider(companyId));
      closed = true;
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Acao administrativa concluida.'),
        ),
      );
    } catch (error) {
      setState(() => errorMessage = _safeError(error));
    } finally {
      if (!closed) {
        setState(() => submitting = false);
      }
    }
  }

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final reasonFilled = reasonController.text.trim().isNotEmpty;
        final confirmationExpected =
            dryRun?.expectedConfirmationText ?? spec.confirmationText;
        final confirmationOk =
            confirmationController.text.trim() == confirmationExpected;
        final canSubmit =
            dryRun?.allowed == true &&
            reasonFilled &&
            confirmationOk &&
            !submitting &&
            !loadingDryRun;
        return AlertDialog(
          title: Text(spec.title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Esta acao bloqueia ou reativa o acesso operacional desta empresa. Nao apaga dados, nao altera senha, nao remove o usuario e nao revoga sessoes nesta fase.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Motivo obrigatorio',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Nota opcional',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: reasonFilled && !loadingDryRun
                        ? () => executeDryRun(setState)
                        : null,
                    icon: loadingDryRun
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_rounded),
                    label: const Text('Executar dry-run'),
                  ),
                  if (!reasonFilled)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Informe o motivo antes do dry-run.'),
                    ),
                  if (dryRun != null) ...[
                    const Divider(),
                    Text(dryRun!.summary),
                    const SizedBox(height: 8),
                    Text('Confirmacao esperada: $confirmationExpected'),
                    if (dryRun!.risks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Riscos'),
                      ...dryRun!.risks.map((risk) => Text('- $risk')),
                    ],
                    if (dryRun!.blockers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Bloqueios'),
                      ...dryRun!.blockers.map((blocker) => Text('- $blocker')),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmationController,
                      decoration: const InputDecoration(
                        labelText: 'Texto de confirmacao',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (!confirmationOk)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Digite $confirmationExpected para liberar a confirmacao.',
                        ),
                      ),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: canSubmit
                  ? () => submit(setState, dialogContext)
                  : null,
              child: Text(submitting ? 'Enviando...' : 'Confirmar'),
            ),
          ],
        );
      },
    ),
  );
}

class _PlaceholderButton extends StatelessWidget {
  const _PlaceholderButton(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _futureActionMessage,
      child: OutlinedButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(_futureActionMessage)));
        },
        child: Text('$label (placeholder)'),
      ),
    );
  }
}

class _DetailLine {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;
}

class _DetailLineWidget extends StatelessWidget {
  const _DetailLineWidget({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }
}

class _JsonPreview extends StatelessWidget {
  const _JsonPreview({required this.title, required this.value});

  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(formatSanitizedAdminJson(value ?? const {})),
          ),
        ],
      ),
    );
  }
}

class _LatestAccessAudit extends StatelessWidget {
  const _LatestAccessAudit({required this.events});

  final List<AdminCompanyAccessAuditEvent> events;

  @override
  Widget build(BuildContext context) {
    final latest = events.isEmpty ? null : events.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ultimas acoes administrativas',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (latest == null)
          const Text('Sem acoes administrativas registradas para este acesso.')
        else ...[
          Text(_accessAuditActionLabel(latest.action)),
          Text(
            '${AdminFormatters.formatDateTime(latest.createdAt)} - ${latest.actorName ?? 'Sistema'}',
          ),
          Text('Motivo: ${latest.reason ?? 'Nao informado'}'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showAccessAuditDetails(context, latest),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('Ver detalhes'),
            ),
          ),
        ],
      ],
    );
  }
}

List<AdminCompanyAccessAuditEvent> _latestAuditForAccess(
  List<AdminCompanyAccessAuditEvent> events, {
  required String? userId,
  required String? employeeProfileId,
  required String? membershipId,
}) {
  return events
      .where(
        (event) =>
            _sameId(event.targetEmployeeId, employeeProfileId) ||
            _sameId(event.targetUserId, userId) ||
            _sameId(event.membershipId, membershipId),
      )
      .toList(growable: false);
}

bool _sameId(String? left, String? right) {
  return left != null && right != null && left == right;
}

String _accessAuditActionLabel(String action) {
  switch (action) {
    case 'access.block':
    case 'admin.access.block':
      return 'Bloqueio de acesso operacional';
    case 'access.reactivate':
    case 'admin.access.reactivate':
      return 'Reativacao de acesso operacional';
    default:
      return action;
  }
}

class _AccessActionTarget {
  const _AccessActionTarget({
    required this.targetId,
    required this.targetType,
    required this.status,
    required this.isProtectedOwner,
    required this.canUseAccessActions,
    this.unavailableReason,
  });

  final String targetId;
  final String targetType;
  final String status;
  final bool isProtectedOwner;
  final bool canUseAccessActions;
  final String? unavailableReason;
}

enum _AccessActionSpec {
  block,
  reactivate;

  String get title => switch (this) {
    _AccessActionSpec.block => 'Bloquear acesso operacional',
    _AccessActionSpec.reactivate => 'Reativar acesso operacional',
  };

  String get confirmationText => switch (this) {
    _AccessActionSpec.block => 'BLOQUEAR',
    _AccessActionSpec.reactivate => 'REATIVAR',
  };
}

String _roleLabel(String role) {
  switch (role.toUpperCase()) {
    case 'OWNER':
      return 'Owner';
    case 'ADMIN':
      return 'Admin';
    case 'OPERATOR':
      return 'Operador';
    default:
      return role;
  }
}

String _employeeRoleLabel(String role) {
  switch (role.toUpperCase()) {
    case 'OWNER':
      return 'Owner';
    case 'MANAGER':
      return 'Administrador';
    case 'CASHIER':
      return 'Caixa';
    case 'SELLER':
      return 'Vendedor';
    case 'STOCK_OPERATOR':
      return 'Estoque';
    case 'READ_ONLY':
      return 'Somente leitura';
    default:
      return 'Nao reconhecida: $role';
  }
}

String _statusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
      return 'Ativo';
    case 'INVITED':
      return 'Convidado';
    case 'DISABLED':
      return 'Desativado';
    case 'REVOKED':
      return 'Revogado';
    default:
      return status;
  }
}

String _clientTypeLabel(String type) {
  switch (type.toUpperCase()) {
    case 'MOBILE_APP':
      return 'MOBILE_APP';
    case 'ADMIN_WEB':
      return 'ADMIN_WEB';
    case 'OWNER_WEB':
      return 'OWNER_WEB';
    default:
      return 'UNKNOWN';
  }
}

String _maskIdentifier(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return 'Nao informado';
  }
  if (text.length <= 12 || text.contains('...')) {
    return text;
  }
  return '${text.substring(0, 4)}...${text.substring(text.length - 4)}';
}

String _safeError(Object error) {
  final text = error.toString();
  if (text.contains('Exception:')) {
    return text.split('Exception:').last.trim();
  }
  return text.length > 180 ? '${text.substring(0, 180)}...' : text;
}
