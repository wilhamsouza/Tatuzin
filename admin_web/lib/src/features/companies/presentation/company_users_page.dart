import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_access_models.dart';
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
                  _UsersTab(users: access.users),
                  _EmployeesTab(employees: access.employees),
                  _PermissionsTab(access: access),
                  _DevicesTab(devices: access.devices),
                  _AuditTab(events: access.audit),
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
  const _UsersTab({required this.users});

  final List<AdminCompanyAccessUser> users;

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
                                onPressed: () =>
                                    _showUserDetails(context, user),
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
  const _EmployeesTab({required this.employees});

  final List<AdminCompanyAccessEmployee> employees;

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
                                onPressed: () =>
                                    _showEmployeeDetails(context, employee),
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

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.events});

  final List<AdminCompanyAccessAuditEvent> events;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminSurface(
        title: 'Auditoria',
        subtitle: events.isEmpty
            ? 'Historico de acoes administrativas de usuarios sera exibido aqui.'
            : 'Eventos administrativos e de sessao relacionados a acessos.',
        child: events.isEmpty
            ? const _EmptyState(
                message:
                    'Historico de acoes administrativas de usuarios sera exibido aqui.',
              )
            : Column(
                children: events
                    .map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.fact_check_rounded),
                        title: Text(event.action),
                        subtitle: Text(
                          '${event.actorName ?? 'Sistema'} - ${AdminFormatters.formatDateTime(event.createdAt)}',
                        ),
                        trailing: Text(event.source),
                      ),
                    )
                    .toList(growable: false),
              ),
      ),
    );
  }
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

void _showUserDetails(BuildContext context, AdminCompanyAccessUser user) {
  _showDetails(
    context,
    title: user.name,
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
  );
}

void _showEmployeeDetails(
  BuildContext context,
  AdminCompanyAccessEmployee employee,
) {
  _showDetails(
    context,
    title: employee.name,
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
  );
}

void _showDetails(
  BuildContext context, {
  required String title,
  required List<_DetailLine> rows,
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
              const Text(_futureActionMessage),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PlaceholderButton('Resetar senha'),
                  _PlaceholderButton('Bloquear acesso'),
                  _PlaceholderButton('Reativar acesso'),
                  _PlaceholderButton('Alterar papel'),
                  _PlaceholderButton('Alterar permissoes'),
                  _PlaceholderButton('Reenviar convite'),
                  _PlaceholderButton('Remover funcionario'),
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
