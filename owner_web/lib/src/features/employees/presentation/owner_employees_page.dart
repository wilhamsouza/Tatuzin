import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_auth_controller.dart';
import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

const _roles = <String>[
  'MANAGER',
  'CASHIER',
  'SELLER',
  'STOCK_OPERATOR',
  'READ_ONLY',
];

const _statuses = <String>['ACTIVE', 'INVITED', 'DISABLED'];

const _permissions = <String>[
  'sales.create',
  'sales.cancel',
  'sales.discount',
  'cash.open',
  'cash.close',
  'cash.withdraw',
  'products.read',
  'products.write',
  'stock.adjust',
  'customers.read',
  'customers.write',
  'fiado.read',
  'fiado.receive',
  'reports.basic',
  'reports.advanced',
  'employees.manage',
  'devices.manage',
  'subscription.manage',
];

class OwnerEmployeesPage extends ConsumerWidget {
  const OwnerEmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(ownerEmployeesProvider);
    final commissions = ref.watch(ownerCommissionsProvider);
    final performance = ref.watch(ownerEmployeeReportsProvider);
    return OwnerAsyncView(
      value: employees,
      onRetry: () => _refresh(ref),
      builder: (data) {
        final commissionData = commissions.valueOrNull;
        final summary = data.summary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OwnerPageIntro(
              title: 'Funcionarios',
              subtitle:
                  'Gerencie equipe, acessos, permissoes e regras de comissao.',
              icon: Icons.badge_outlined,
              trailing: data.canManage
                  ? FilledButton.icon(
                      onPressed: () => _openEmployeeDialog(context, ref),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Novo funcionario'),
                    )
                  : null,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                OwnerMetricCard(
                  title: 'Funcionarios',
                  value: '${summary.total}',
                  detail:
                      '${summary.active} ativos, ${summary.disabled} desativados.',
                  icon: Icons.groups_outlined,
                  isAvailable: data.available,
                ),
                OwnerMetricCard(
                  title: 'Acesso ativo',
                  value: '${summary.withActiveAccess}',
                  detail:
                      '${summary.temporaryPasswordPending} com senha temporaria pendente.',
                  icon: Icons.verified_user_outlined,
                  isAvailable: data.available,
                ),
                OwnerMetricCard(
                  title: 'Comissao ativa',
                  value: '${summary.commissionEnabled}',
                  detail: 'Funcionarios com regra de comissao habilitada.',
                  icon: Icons.payments_outlined,
                  isAvailable: data.available,
                ),
                OwnerMetricCard(
                  title: 'Comissao estimada',
                  value: OwnerFormatters.moneyFromCents(
                    commissionData?.totals.totalCommissionCents ?? 0,
                  ),
                  detail:
                      '${commissionData?.totals.totalSalesCount ?? 0} vendas no periodo.',
                  icon: Icons.price_check_rounded,
                  isAvailable: commissionData != null,
                ),
              ],
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Equipe',
              subtitle: data.canManage
                  ? 'Acoes de acesso, cadastro e permissao.'
                  : 'Consulta da equipe. Voce nao tem permissao para alterar.',
              child: _EmployeesList(employees: data),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Comissoes',
              subtitle: 'Relatorio estimado por funcionario no periodo.',
              child: commissions.when(
                data: (value) => _CommissionList(summary: value),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) =>
                    Text('Nao foi possivel carregar comissoes: $error'),
              ),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Vendas por funcionario',
              subtitle: 'Ranking gerencial reaproveitando o relatorio atual.',
              child: performance.when(
                data: (value) => _PerformanceList(report: value),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) =>
                    Text('Nao foi possivel carregar atividade: $error'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmployeesList extends ConsumerWidget {
  const _EmployeesList({required this.employees});

  final OwnerEmployeesOverview employees;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (employees.items.isEmpty) {
      return OwnerEmptyState(
        title: 'Nenhum funcionario cadastrado',
        message: employees.canManage
            ? 'Use Novo funcionario para liberar acesso a equipe.'
            : 'Nenhum cadastro apareceu para consulta.',
        icon: Icons.badge_outlined,
      );
    }
    return Column(
      children: [
        for (final item in employees.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_statusIcon(item.accessStatus)),
            title: Text(item.name),
            subtitle: Text(
              '${_roleLabel(item.role)} - ${_statusLabel(item.status)} - ${_accessLabel(item.accessStatus)}\n'
              '${item.email ?? 'Sem e-mail'} - Permissoes: ${item.permissionsCount}',
            ),
            isThreeLine: true,
            trailing: employees.canManage
                ? Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Editar funcionario',
                        onPressed: item.role == 'OWNER'
                            ? null
                            : () =>
                                  _openEmployeeDialog(context, ref, item: item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Gerar senha temporaria',
                        onPressed: item.role == 'OWNER'
                            ? null
                            : () => _generatePassword(context, ref, item),
                        icon: const Icon(Icons.password_rounded),
                      ),
                      IconButton(
                        tooltip: 'Configurar comissao',
                        onPressed: item.role == 'OWNER'
                            ? null
                            : () => _openCommissionDialog(context, ref, item),
                        icon: const Icon(Icons.price_check_rounded),
                      ),
                      IconButton(
                        tooltip: item.status == 'DISABLED'
                            ? 'Reativar funcionario'
                            : 'Desativar funcionario',
                        onPressed: item.role == 'OWNER'
                            ? null
                            : () => _toggleEmployee(context, ref, item),
                        icon: Icon(
                          item.status == 'DISABLED'
                              ? Icons.check_circle_outline_rounded
                              : Icons.block_outlined,
                        ),
                      ),
                    ],
                  )
                : const Chip(label: Text('Somente leitura')),
          ),
      ],
    );
  }
}

class _CommissionList extends StatelessWidget {
  const _CommissionList({required this.summary});

  final OwnerCommissionsSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = summary.rows.where((row) => row.commissionEnabled).toList();
    if (rows.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma comissao ativa',
        message: 'Use Configurar comissao na lista de funcionarios.',
        icon: Icons.payments_outlined,
      );
    }
    return Column(
      children: [
        for (final row in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.price_check_rounded),
            title: Text(row.employeeName),
            subtitle: Text(
              '${row.eligibleSalesCount} vendas elegiveis - ${_baseLabel(row.commissionBase)}',
            ),
            trailing: Text(
              OwnerFormatters.moneyFromCents(row.commissionAmountCents),
            ),
          ),
      ],
    );
  }
}

class _PerformanceList extends StatelessWidget {
  const _PerformanceList({required this.report});

  final OwnerEmployeeReports report;

  @override
  Widget build(BuildContext context) {
    if (!report.available || report.topEmployees.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma venda por funcionario no periodo',
        message:
            'Quando houver vendas vinculadas aos usuarios, elas aparecem aqui.',
        icon: Icons.badge_outlined,
      );
    }
    return Column(
      children: [
        for (final item in report.topEmployees)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.point_of_sale_rounded),
            title: Text(item.name),
            subtitle: Text(
              '${item.salesCount} vendas - Ultima venda ${OwnerFormatters.date(item.lastSaleAt)}',
            ),
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.salesAmountCents),
            ),
          ),
      ],
    );
  }
}

Future<void> _openEmployeeDialog(
  BuildContext context,
  WidgetRef ref, {
  OwnerEmployeeItem? item,
}) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _EmployeeDialog(item: item),
  );
  if (result == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  await _runAction(context, ref, () async {
    if (item == null) {
      await ref.read(ownerApiServiceProvider).createEmployee(body: result);
    } else {
      await ref
          .read(ownerApiServiceProvider)
          .updateEmployee(employeeId: item.id, body: result);
    }
  });
}

Future<void> _openCommissionDialog(
  BuildContext context,
  WidgetRef ref,
  OwnerEmployeeItem item,
) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _CommissionDialog(item: item),
  );
  if (result == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  await _runAction(context, ref, () async {
    await ref
        .read(ownerApiServiceProvider)
        .updateCommissionSettings(employeeId: item.id, body: result);
  });
}

Future<void> _generatePassword(
  BuildContext context,
  WidgetRef ref,
  OwnerEmployeeItem item,
) async {
  final confirmed = await _confirmAction(
    context,
    title: 'Gerar senha temporaria?',
    message:
        'A senha atual sera substituida. A nova senha aparece apenas uma vez.',
    confirmLabel: 'Gerar senha',
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runAction(context, ref, () async {
    final result = await ref
        .read(ownerApiServiceProvider)
        .generateTemporaryPassword(employeeId: item.id);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Senha temporaria gerada'),
        content: SelectableText(
          'Login: ${result.login}\nSenha temporaria: ${result.temporaryPassword}\n\nEssa senha aparece apenas agora.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text:
                      'Login: ${result.login}\nSenha temporaria: ${result.temporaryPassword}',
                ),
              );
              Navigator.of(context).pop();
            },
            child: const Text('Copiar dados'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  });
}

Future<void> _toggleEmployee(
  BuildContext context,
  WidgetRef ref,
  OwnerEmployeeItem item,
) async {
  final enabling = item.status == 'DISABLED';
  final confirmed = await _confirmAction(
    context,
    title: enabling ? 'Reativar funcionario?' : 'Desativar funcionario?',
    message: enabling
        ? 'O funcionario voltara a contar como ativo no painel.'
        : 'O funcionario perdera acesso operacional ate ser reativado.',
    confirmLabel: enabling ? 'Reativar' : 'Desativar',
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runAction(context, ref, () async {
    await ref
        .read(ownerApiServiceProvider)
        .setEmployeeEnabled(
          employeeId: item.id,
          enabled: item.status == 'DISABLED',
        );
  });
}

Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

Future<void> _runAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  try {
    await action();
    _refresh(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alteracao salva com sucesso.')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeOwnerError(error))));
    }
  }
}

void _refresh(WidgetRef ref) {
  ref.invalidate(ownerEmployeesProvider);
  ref.invalidate(ownerCommissionsProvider);
  ref.invalidate(ownerEmployeeReportsProvider);
  ref.read(ownerRefreshTickProvider.notifier).state++;
}

class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({this.item});

  final OwnerEmployeeItem? item;

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late String _role;
  late String _status;
  late final Set<String> _selectedPermissions;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _email = TextEditingController(text: item?.email ?? '');
    _phone = TextEditingController(text: item?.phone ?? '');
    _role = _roles.contains(item?.role) ? item!.role : 'SELLER';
    _status = _statuses.contains(item?.status) ? item!.status : 'ACTIVE';
    _selectedPermissions = {...?item?.permissions};
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.item == null ? 'Novo funcionario' : 'Editar funcionario',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Cargo'),
                items: [
                  for (final role in _roles)
                    DropdownMenuItem(
                      value: role,
                      child: Text(_roleLabel(role)),
                    ),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final status in _statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Permissoes basicas',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final permission in _permissions)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_permissionLabel(permission)),
                  value: _selectedPermissions.contains(permission),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedPermissions.add(permission);
                      } else {
                        _selectedPermissions.remove(permission);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final validationError = _validateEmployeeForm();
            if (validationError != null) {
              setState(() => _error = validationError);
              return;
            }
            Navigator.of(context).pop(<String, dynamic>{
              'name': _name.text.trim(),
              'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
              'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              'role': _role,
              'status': _status,
              'permissions': _selectedPermissions.toList()..sort(),
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  String? _validateEmployeeForm() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) {
      return 'Informe o nome do funcionario.';
    }
    if (email.isEmpty || !email.contains('@')) {
      return 'Informe um e-mail valido.';
    }
    final hasAdminPermission = _selectedPermissions.any(
      (permission) =>
          permission == 'employees.manage' ||
          permission == 'subscription.manage' ||
          permission == 'devices.manage',
    );
    if (_role != 'MANAGER' && hasAdminPermission) {
      return 'Permissoes administrativas exigem cargo de gerente.';
    }
    return null;
  }
}

class _CommissionDialog extends StatefulWidget {
  const _CommissionDialog({required this.item});

  final OwnerEmployeeItem item;

  @override
  State<_CommissionDialog> createState() => _CommissionDialogState();
}

class _CommissionDialogState extends State<_CommissionDialog> {
  late bool _enabled;
  late String _type;
  late String _base;
  late final TextEditingController _rate;
  late final TextEditingController _fixed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enabled = widget.item.commissionEnabled;
    _type = widget.item.commissionType == 'FIXED_PER_SALE'
        ? 'FIXED_PER_SALE'
        : widget.item.commissionType == 'PERCENTAGE'
        ? 'PERCENTAGE'
        : 'PERCENTAGE';
    _base = widget.item.commissionBase;
    _rate = TextEditingController(
      text: widget.item.commissionRateBps == null
          ? ''
          : (widget.item.commissionRateBps! / 100).toString(),
    );
    _fixed = TextEditingController(
      text: widget.item.commissionFixedCents == null
          ? ''
          : (widget.item.commissionFixedCents! / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _rate.dispose();
    _fixed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Configurar comissao - ${widget.item.name}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Comissao ativa'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(
                  value: 'PERCENTAGE',
                  child: Text('Percentual'),
                ),
                DropdownMenuItem(
                  value: 'FIXED_PER_SALE',
                  child: Text('Fixo por venda'),
                ),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _base,
              decoration: const InputDecoration(labelText: 'Base'),
              items: const [
                DropdownMenuItem(
                  value: 'NET_SALES',
                  child: Text('Venda liquida'),
                ),
                DropdownMenuItem(
                  value: 'GROSS_SALES',
                  child: Text('Venda bruta'),
                ),
                DropdownMenuItem(
                  value: 'GROSS_PROFIT',
                  child: Text('Lucro do produto'),
                ),
              ],
              onChanged: (value) => setState(() => _base = value ?? _base),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              enabled: _enabled && _type == 'PERCENTAGE',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Percentual (%)'),
            ),
            TextField(
              controller: _fixed,
              enabled: _enabled && _type == 'FIXED_PER_SALE',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor fixo (R\$)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final rate = double.tryParse(_rate.text.replaceAll(',', '.')) ?? 0;
            final fixed =
                double.tryParse(_fixed.text.replaceAll(',', '.')) ?? 0;
            final validationError = _validateCommission(rate, fixed);
            if (validationError != null) {
              setState(() => _error = validationError);
              return;
            }
            Navigator.of(context).pop(<String, dynamic>{
              'commissionEnabled': _enabled,
              'commissionType': _enabled ? _type : 'NONE',
              'commissionBase': _base,
              'commissionRateBps': _type == 'PERCENTAGE'
                  ? (rate * 100).round()
                  : null,
              'commissionFixedCents': _type == 'FIXED_PER_SALE'
                  ? (fixed * 100).round()
                  : null,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  String? _validateCommission(double rate, double fixed) {
    if (!_enabled) {
      return null;
    }
    if (_type == 'PERCENTAGE' && (rate <= 0 || rate > 100)) {
      return 'Informe percentual maior que 0 e ate 100%.';
    }
    if (_type == 'FIXED_PER_SALE' && fixed <= 0) {
      return 'Informe valor fixo maior que zero.';
    }
    return null;
  }
}

IconData _statusIcon(String accessStatus) {
  switch (accessStatus) {
    case 'ACTIVE':
      return Icons.verified_user_outlined;
    case 'TEMPORARY_PASSWORD_PENDING':
      return Icons.lock_clock_outlined;
    case 'DISABLED':
      return Icons.block_outlined;
    default:
      return Icons.person_off_outlined;
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'OWNER':
      return 'Dono';
    case 'MANAGER':
      return 'Gerente';
    case 'CASHIER':
      return 'Caixa';
    case 'SELLER':
      return 'Vendedor';
    case 'STOCK_OPERATOR':
      return 'Estoque';
    default:
      return 'Leitura';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'ACTIVE':
      return 'Ativo';
    case 'DISABLED':
      return 'Desativado';
    case 'INVITED':
      return 'Convidado';
    default:
      return status;
  }
}

String _accessLabel(String accessStatus) {
  switch (accessStatus) {
    case 'ACTIVE':
      return 'acesso ativo';
    case 'TEMPORARY_PASSWORD_PENDING':
      return 'senha temporaria pendente';
    case 'DISABLED':
      return 'acesso bloqueado';
    default:
      return 'sem acesso';
  }
}

String _baseLabel(String base) {
  switch (base) {
    case 'GROSS_SALES':
      return 'venda bruta';
    case 'GROSS_PROFIT':
      return 'lucro do produto';
    default:
      return 'venda liquida';
  }
}

String _permissionLabel(String permission) {
  switch (permission) {
    case 'employees.manage':
      return 'Gerenciar funcionarios';
    case 'reports.advanced':
      return 'Relatorios avancados';
    case 'subscription.manage':
      return 'Gerenciar assinatura';
    case 'devices.manage':
      return 'Gerenciar dispositivos';
    default:
      return permission;
  }
}
