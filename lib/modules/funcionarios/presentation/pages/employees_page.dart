import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/employee_models.dart';
import '../providers/employees_providers.dart';

class EmployeesPage extends ConsumerStatefulWidget {
  const EmployeesPage({super.key});

  @override
  ConsumerState<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends ConsumerState<EmployeesPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(employeeSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final canManage = ref.watch(canManageEmployeesProvider);
    final currentEmployeeDisabled = ref.watch(currentEmployeeDisabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Funcionários')),
      drawer: const AppMainDrawer(),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: ref.watch(employeeActionControllerProvider).isLoading
                  ? null
                  : () => _openEmployeeForm(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Novo funcionário'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space4,
              layout.pagePadding,
              layout.space3,
            ),
            child: const AppPageHeader(
              title: 'Funcionários',
              subtitle:
                  'Gerencie acessos de caixas, vendedores e gerentes sem misturar com o dono da empresa.',
              badgeLabel: 'Plano PRO',
              badgeIcon: Icons.badge_outlined,
            ),
          ),
          if (!canManage)
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(layout.pagePadding),
                  child: AppStateCard(
                    title: currentEmployeeDisabled
                        ? 'Acesso desativado'
                        : 'Sem permissão',
                    message: currentEmployeeDisabled
                        ? 'Seu perfil de funcionário está desativado. Fale com o dono da empresa.'
                        : 'Você não tem permissão para gerenciar funcionários.',
                    icon: Icons.lock_outline_rounded,
                    tone: AppStateTone.warning,
                    compact: true,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: _EmployeesContent(searchController: _searchController),
            ),
        ],
      ),
    );
  }

  Future<void> _openEmployeeForm(
    BuildContext context, {
    EmployeeProfile? employee,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EmployeeFormSheet(employee: employee),
    );
  }
}

class _EmployeesContent extends ConsumerWidget {
  const _EmployeesContent({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final employeesAsync = ref.watch(employeesListProvider);
    final page = employeesAsync.valueOrNull;
    final canViewActivity = ref.watch(canViewEmployeeActivityProvider);
    final canViewCommissions = ref.watch(canViewEmployeeCommissionsProvider);

    return Column(
      children: [
        if (canViewActivity)
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space3,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.pushNamed(AppRouteNames.employeeActivity),
                icon: const Icon(Icons.manage_search_rounded),
                label: const Text('Ver atividade da equipe'),
              ),
            ),
          ),
        if (canViewCommissions)
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space3,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.pushNamed(AppRouteNames.employeeCommissions),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Ver comissões'),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            0,
            layout.pagePadding,
            layout.space3,
          ),
          child: AppInput(
            controller: searchController,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Buscar por nome, e-mail ou telefone',
            onChanged: (value) {
              ref.read(employeeSearchQueryProvider.notifier).state = value;
              ref.read(employeesPageNumberProvider.notifier).state = 1;
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            0,
            layout.pagePadding,
            layout.space3,
          ),
          child: _EmployeeFilters(),
        ),
        if (page != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space3,
            ),
            child: _EmployeeSummary(page: page),
          ),
        Expanded(
          child: employeesAsync.when(
            data: (page) {
              if (page.items.isEmpty) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    layout.pagePadding,
                    layout.space4,
                    layout.pagePadding,
                    92,
                  ),
                  child: AppStateCard(
                    title: 'Nenhum funcionário encontrado',
                    message:
                        'Cadastre o primeiro funcionário para controlar acessos no plano PRO.',
                    icon: Icons.badge_outlined,
                    actionLabel: 'Novo funcionário',
                    onAction: () => _openEmployeeForm(context),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(employeesListProvider);
                  await ref.read(employeesListProvider.future);
                },
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    layout.pagePadding,
                    0,
                    layout.pagePadding,
                    96,
                  ),
                  itemCount: page.items.length,
                  separatorBuilder: (_, __) => SizedBox(height: layout.space4),
                  itemBuilder: (context, index) {
                    return _EmployeeTile(employee: page.items[index]);
                  },
                ),
              );
            },
            loading: () => const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Não foi possível carregar funcionários',
                  message: '$error',
                  tone: AppStateTone.error,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(employeesListProvider),
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openEmployeeForm(
    BuildContext context, {
    EmployeeProfile? employee,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EmployeeFormSheet(employee: employee),
    );
  }
}

class _EmployeeFilters extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(employeeStatusFilterProvider);
    final role = ref.watch(employeeRoleFilterProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: status == null && role == null,
            onSelected: (_) {
              ref.read(employeeStatusFilterProvider.notifier).state = null;
              ref.read(employeeRoleFilterProvider.notifier).state = null;
              ref.read(employeesPageNumberProvider.notifier).state = 1;
            },
          ),
          const SizedBox(width: 8),
          for (final item in EmployeeStatus.editableStatuses) ...[
            ChoiceChip(
              label: Text(item.label),
              selected: status == item,
              onSelected: (_) {
                ref.read(employeeStatusFilterProvider.notifier).state =
                    status == item ? null : item;
                ref.read(employeesPageNumberProvider.notifier).state = 1;
              },
            ),
            const SizedBox(width: 8),
          ],
          for (final item in EmployeeRole.editableRoles.take(3)) ...[
            ChoiceChip(
              label: Text(item.label),
              selected: role == item,
              onSelected: (_) {
                ref.read(employeeRoleFilterProvider.notifier).state =
                    role == item ? null : item;
                ref.read(employeesPageNumberProvider.notifier).state = 1;
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _EmployeeSummary extends StatelessWidget {
  const _EmployeeSummary({required this.page});

  final EmployeesPageResult page;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final active = page.items
        .where((item) => item.status == EmployeeStatus.active)
        .length;
    final invited = page.items
        .where((item) => item.status == EmployeeStatus.invited)
        .length;
    final disabled = page.items
        .where((item) => item.status == EmployeeStatus.disabled)
        .length;

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(label: 'Total', value: '${page.total}'),
          ),
          Expanded(
            child: _SummaryMetric(label: 'Ativos', value: '$active'),
          ),
          Expanded(
            child: _SummaryMetric(label: 'Convites', value: '$invited'),
          ),
          Expanded(
            child: _SummaryMetric(label: 'Desativados', value: '$disabled'),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmployeeTile extends ConsumerWidget {
  const _EmployeeTile({required this.employee});

  final EmployeeProfile employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final isBusy = ref.watch(employeeActionControllerProvider).isLoading;
    final canViewActivity = ref.watch(canViewEmployeeActivityProvider);
    final canManage = ref.watch(canManageEmployeesProvider);

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                child: Icon(
                  employee.isOwner
                      ? Icons.workspace_premium_outlined
                      : Icons.person_outline_rounded,
                ),
              ),
              SizedBox(width: layout.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        employee.email,
                        employee.phone,
                      ].whereType<String>().join(' - '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!employee.isOwner)
                PopupMenuButton<String>(
                  enabled: !isBusy,
                  tooltip: 'Ações',
                  onSelected: (value) => _handleAction(context, ref, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    if (canManage)
                      const PopupMenuItem(
                        value: 'commission',
                        child: Text('Configurar comissão'),
                      ),
                    if (employee.accessStatus == EmployeeAccessStatus.noAccess)
                      const PopupMenuItem(
                        value: 'generate-temporary-password',
                        child: Text('Gerar senha temporária'),
                      )
                    else if (employee.accessStatus !=
                        EmployeeAccessStatus.disabled)
                      const PopupMenuItem(
                        value: 'generate-temporary-password',
                        child: Text('Redefinir senha'),
                      ),
                    if (employee.status == EmployeeStatus.disabled)
                      const PopupMenuItem(
                        value: 'enable',
                        child: Text('Habilitar'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'disable',
                        child: Text('Desativar'),
                      ),
                  ],
                ),
            ],
          ),
          SizedBox(height: layout.space3),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              AppStatusBadge(
                label: employee.role.label,
                icon: Icons.badge_outlined,
              ),
              AppStatusBadge(
                label: employee.status.label,
                tone: _statusTone(employee.status),
                icon: _statusIcon(employee.status),
              ),
              AppStatusBadge(
                label: employee.accessStatus.label,
                tone: _accessTone(employee.accessStatus),
                icon: _accessIcon(employee.accessStatus),
              ),
              if (employee.isOwner)
                const AppStatusBadge(
                  label: 'Protegido',
                  tone: AppStatusTone.info,
                  icon: Icons.lock_outline_rounded,
                ),
              AppStatusBadge(
                label: _commissionBadgeLabel(employee),
                tone: employee.commissionEnabled
                    ? AppStatusTone.success
                    : AppStatusTone.neutral,
                icon: Icons.payments_outlined,
              ),
            ],
          ),
          if (canViewActivity) ...[
            SizedBox(height: layout.space2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.employeeActivityDetail,
                  pathParameters: {'employeeId': employee.id},
                ),
                icon: const Icon(Icons.manage_search_rounded),
                label: const Text('Ver atividade'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    switch (action) {
      case 'edit':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _EmployeeFormSheet(employee: employee),
        );
        return;
      case 'commission':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => EmployeeCommissionSettingsSheet(employee: employee),
        );
        return;
      case 'generate-temporary-password':
        await _generateTemporaryPassword(context, ref);
        return;
      case 'invite':
        await _runAction(
          context,
          ref,
          () async => ref
              .read(employeeActionControllerProvider.notifier)
              .invite(employee.id),
          successMessage:
              'Convite gerado. O envio automático de e-mail será implementado em etapa futura.',
        );
        return;
      case 'enable':
        await _runAction(
          context,
          ref,
          () async => ref
              .read(employeeActionControllerProvider.notifier)
              .enable(employee.id),
          successMessage: 'Funcionário habilitado.',
        );
        return;
      case 'disable':
        final confirmed = await _confirmDisable(context, employee.name);
        if (confirmed != true) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        await _runAction(
          context,
          ref,
          () async => ref
              .read(employeeActionControllerProvider.notifier)
              .disable(employee.id),
          successMessage: 'Acesso desativado sem apagar histórico.',
        );
        return;
    }
  }

  Future<void> _generateTemporaryPassword(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final result = await ref
          .read(employeeActionControllerProvider.notifier)
          .generateTemporaryPassword(employee.id);
      if (!context.mounted) {
        return;
      }
      await _showEmployeeAccessSheet(context, result);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Senha temporária gerada.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível gerar a senha: ${_errorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Future<Object?> Function() action, {
    required String successMessage,
  }) async {
    try {
      final result = await action();
      if (!context.mounted) {
        return;
      }
      final message = result is EmployeeActionResult
          ? result.message ?? successMessage
          : successMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível concluir a ação: ${_errorMessage(error)}',
          ),
        ),
      );
    }
  }
}

class EmployeeCommissionSettingsSheet extends ConsumerStatefulWidget {
  const EmployeeCommissionSettingsSheet({required this.employee, super.key});

  final EmployeeProfile employee;

  @override
  ConsumerState<EmployeeCommissionSettingsSheet> createState() =>
      _EmployeeCommissionSettingsSheetState();
}

class _EmployeeCommissionSettingsSheetState
    extends ConsumerState<EmployeeCommissionSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled;
  late EmployeeCommissionType _type;
  late EmployeeCommissionBase _base;
  late final TextEditingController _rateController;
  late final TextEditingController _fixedController;

  @override
  void initState() {
    super.initState();
    final settings = EmployeeCommissionSettings.fromEmployee(widget.employee);
    _enabled = settings.commissionEnabled;
    _type = settings.commissionType == EmployeeCommissionType.none
        ? EmployeeCommissionType.percentage
        : settings.commissionType;
    _base = settings.commissionBase;
    _rateController = TextEditingController(
      text: _percentageInputFromBps(settings.commissionRateBps ?? 0),
    );
    _fixedController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(
        settings.commissionFixedCents ?? 0,
      ),
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    _fixedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final isBusy = ref.watch(employeeActionControllerProvider).isLoading;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Comissão do funcionário',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: layout.space2),
              Text(
                'A comissão é calculada apenas sobre vendas finalizadas atribuídas a este funcionário.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: layout.space5),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: isBusy
                    ? null
                    : (value) => setState(() => _enabled = value),
                title: const Text('Ativar comissão'),
              ),
              SizedBox(height: layout.space3),
              DropdownButtonFormField<EmployeeCommissionType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(
                    value: EmployeeCommissionType.percentage,
                    child: Text('Percentual'),
                  ),
                  DropdownMenuItem(
                    value: EmployeeCommissionType.fixedPerSale,
                    child: Text('Valor fixo por venda'),
                  ),
                ],
                onChanged: !_enabled || isBusy
                    ? null
                    : (value) => setState(() {
                        _type = value ?? _type;
                        if (_type == EmployeeCommissionType.fixedPerSale) {
                          _base = EmployeeCommissionBase.netSales;
                        }
                      }),
              ),
              SizedBox(height: layout.space4),
              DropdownButtonFormField<EmployeeCommissionBase>(
                initialValue: _base,
                decoration: const InputDecoration(labelText: 'Base de cálculo'),
                items: EmployeeCommissionBase.values
                    .map(
                      (base) => DropdownMenuItem(
                        value: base,
                        child: Text(base.label),
                      ),
                    )
                    .toList(),
                onChanged:
                    !_enabled ||
                        isBusy ||
                        _type == EmployeeCommissionType.fixedPerSale
                    ? null
                    : (value) => setState(() => _base = value ?? _base),
              ),
              if (_base == EmployeeCommissionBase.grossProfit) ...[
                SizedBox(height: layout.space3),
                Text(
                  'Comissão sobre lucro usa o preço vendido menos o custo cadastrado do produto. Vendas sem custo cadastrado podem ficar fora do cálculo.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              SizedBox(height: layout.space4),
              if (_type == EmployeeCommissionType.percentage)
                TextFormField(
                  controller: _rateController,
                  enabled: _enabled && !isBusy,
                  decoration: const InputDecoration(
                    labelText: 'Percentual',
                    suffixText: '%',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (!_enabled) {
                      return null;
                    }
                    final bps = _tryParseBps(value ?? '');
                    if (bps == null) {
                      return 'Informe um percentual válido';
                    }
                    if (bps <= 0 || bps > 10000) {
                      return 'Informe um percentual entre 0,01% e 100%';
                    }
                    return null;
                  },
                )
              else
                TextFormField(
                  controller: _fixedController,
                  enabled: _enabled && !isBusy,
                  decoration: const InputDecoration(labelText: 'Valor fixo'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (!_enabled) {
                      return null;
                    }
                    final cents = _tryParseFixedCents(value ?? '');
                    if (cents == null || cents < 0) {
                      return 'Informe um valor válido';
                    }
                    return null;
                  },
                ),
              SizedBox(height: layout.space6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  SizedBox(width: layout.space4),
                  Expanded(
                    child: FilledButton(
                      onPressed: isBusy ? null : _save,
                      child: const Text('Salvar alterações'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final settings = EmployeeCommissionSettings(
      commissionEnabled: _enabled,
      commissionType: _enabled ? _type : EmployeeCommissionType.none,
      commissionBase: _type == EmployeeCommissionType.fixedPerSale
          ? EmployeeCommissionBase.netSales
          : _base,
      commissionRateBps: _type == EmployeeCommissionType.percentage
          ? _parseBps(_rateController.text)
          : null,
      commissionFixedCents: _type == EmployeeCommissionType.fixedPerSale
          ? (_tryParseFixedCents(_fixedController.text) ?? 0)
          : null,
    );

    try {
      await ref
          .read(employeeActionControllerProvider.notifier)
          .updateCommissionSettings(widget.employee.id, settings);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comissão atualizada.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível salvar comissão: ${_errorMessage(error)}',
          ),
        ),
      );
    }
  }
}

class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({this.employee});

  final EmployeeProfile? employee;

  @override
  ConsumerState<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late EmployeeRole _role;
  late EmployeeStatus _status;
  late Set<EmployeePermission> _permissions;

  bool get _isEditing => widget.employee != null;

  bool get _isOwner => widget.employee?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _nameController = TextEditingController(text: employee?.name ?? '');
    _emailController = TextEditingController(text: employee?.email ?? '');
    _phoneController = TextEditingController(text: employee?.phone ?? '');
    _role = employee?.role ?? EmployeeRole.cashier;
    _status = employee?.status == EmployeeStatus.unknown
        ? EmployeeStatus.active
        : employee?.status ?? EmployeeStatus.active;
    _permissions = employee?.permissions.isNotEmpty == true
        ? employee!.permissions
        : defaultPermissionsForRole(_role);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final isBusy = ref.watch(employeeActionControllerProvider).isLoading;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isOwner
                    ? 'Dono da empresa'
                    : _isEditing
                    ? 'Editar funcionário'
                    : 'Novo funcionário',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: layout.space2),
              Text(
                _isOwner
                    ? 'O dono é protegido e não pode ser alterado por esta tela.'
                    : 'Configure cargo, status e permissões efetivas.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: layout.space6),
              TextFormField(
                controller: _nameController,
                enabled: !_isOwner && !isBusy,
                decoration: const InputDecoration(labelText: 'Nome'),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o nome do funcionário';
                  }
                  return null;
                },
              ),
              SizedBox(height: layout.space4),
              TextFormField(
                controller: _emailController,
                enabled: !_isOwner && !isBusy,
                decoration: const InputDecoration(labelText: 'E-mail'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (_status == EmployeeStatus.invited && email.isEmpty) {
                    return 'Informe o e-mail para convidar';
                  }
                  if (email.isNotEmpty && !email.contains('@')) {
                    return 'Informe um e-mail válido';
                  }
                  return null;
                },
              ),
              SizedBox(height: layout.space4),
              TextFormField(
                controller: _phoneController,
                enabled: !_isOwner && !isBusy,
                decoration: const InputDecoration(labelText: 'Telefone'),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: layout.space4),
              if (_isOwner) ...[
                TextFormField(
                  initialValue: _role.label,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'Cargo'),
                ),
                SizedBox(height: layout.space4),
                TextFormField(
                  initialValue: _status.label,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
              ] else ...[
                DropdownButtonFormField<EmployeeRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Cargo'),
                  items: EmployeeRole.editableRoles
                      .map(
                        (role) => DropdownMenuItem<EmployeeRole>(
                          value: role,
                          child: Text(role.label),
                        ),
                      )
                      .toList(),
                  onChanged: isBusy
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _role = value;
                            _permissions = defaultPermissionsForRole(value);
                          });
                        },
                ),
                SizedBox(height: layout.space4),
                DropdownButtonFormField<EmployeeStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: EmployeeStatus.editableStatuses
                      .map(
                        (status) => DropdownMenuItem<EmployeeStatus>(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: isBusy
                      ? null
                      : (value) => setState(() => _status = value ?? _status),
                ),
              ],
              SizedBox(height: layout.space6),
              Text(
                'Permissões',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: layout.space2),
              for (final group in _permissionGroups().entries)
                _PermissionGroup(
                  group: group,
                  selected: _permissions,
                  enabled: !_isOwner && !isBusy,
                  onChanged: (permission, selected) {
                    setState(() {
                      if (selected) {
                        _permissions = {..._permissions, permission};
                      } else {
                        _permissions = {..._permissions}..remove(permission);
                      }
                    });
                  },
                ),
              SizedBox(height: layout.space6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  SizedBox(width: layout.space4),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isOwner || isBusy ? null : _save,
                      child: Text(_isEditing ? 'Salvar' : 'Criar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<EmployeePermission>> _permissionGroups() {
    final groups = <String, List<EmployeePermission>>{};
    for (final permission in EmployeePermission.values) {
      groups
          .putIfAbsent(permission.group, () => <EmployeePermission>[])
          .add(permission);
    }
    return groups;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final input = EmployeeMutationInput(
      name: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      role: _role,
      status: _status,
      permissions: _permissions,
    );

    try {
      final controller = ref.read(employeeActionControllerProvider.notifier);
      EmployeeProfile? createdEmployee;
      if (_isEditing) {
        await controller.updateEmployee(widget.employee!.id, input);
      } else {
        createdEmployee = await controller.create(input);
      }
      if (!mounted) {
        return;
      }
      if (!_isEditing &&
          createdEmployee != null &&
          (createdEmployee.email?.trim().isNotEmpty ?? false)) {
        await _askGenerateTemporaryPassword(context, createdEmployee);
        if (!mounted) {
          return;
        }
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Funcionário atualizado.' : 'Funcionário criado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível salvar funcionário: ${_errorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _askGenerateTemporaryPassword(
    BuildContext context,
    EmployeeProfile employee,
  ) async {
    final generate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar senha temporária agora?'),
        content: const Text(
          'Mostre essa senha ao funcionário. Ele deverá trocar no primeiro acesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gerar senha'),
          ),
        ],
      ),
    );
    if (generate != true || !context.mounted) {
      return;
    }

    try {
      final result = await ref
          .read(employeeActionControllerProvider.notifier)
          .generateTemporaryPassword(employee.id);
      if (!context.mounted) {
        return;
      }
      await _showEmployeeAccessSheet(context, result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível gerar a senha: ${_errorMessage(error)}',
          ),
        ),
      );
    }
  }
}

class _PermissionGroup extends StatelessWidget {
  const _PermissionGroup({
    required this.group,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final MapEntry<String, List<EmployeePermission>> group;
  final Set<EmployeePermission> selected;
  final bool enabled;
  final void Function(EmployeePermission permission, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(group.key),
      initiallyExpanded: group.key == 'Vendas' || group.key == 'Caixa',
      children: [
        for (final permission in group.value)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: selected.contains(permission),
            onChanged: enabled
                ? (value) => onChanged(permission, value ?? false)
                : null,
            title: Text(permission.label),
            controlAffinity: ListTileControlAffinity.leading,
          ),
      ],
    );
  }
}

Future<bool?> _confirmDisable(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Desativar funcionário'),
      content: Text(
        'Remover o acesso de "$name" não apaga histórico nem dados relacionados.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Desativar'),
        ),
      ],
    ),
  );
}

Future<void> _showEmployeeAccessSheet(
  BuildContext context,
  EmployeeTemporaryPasswordResult result,
) {
  final accessText =
      'Funcionário: ${result.employee.name}\n'
      'Login: ${result.login}\n'
      'Senha temporária: ${result.temporaryPassword}';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final layout = context.appLayout;
      return Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Acesso do funcionário',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: layout.space4),
            _AccessRow(label: 'Nome', value: result.employee.name),
            _AccessRow(label: 'Login', value: result.login),
            _AccessRow(
              label: 'Senha temporária',
              value: result.temporaryPassword,
            ),
            SizedBox(height: layout.space3),
            Text(
              'Essa senha aparece apenas agora. O funcionário deverá trocar no primeiro acesso.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: layout.space6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: accessText));
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dados de acesso copiados.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar dados'),
                  ),
                ),
                SizedBox(width: layout.space4),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _AccessRow extends StatelessWidget {
  const _AccessRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

AppStatusTone _statusTone(EmployeeStatus status) {
  switch (status) {
    case EmployeeStatus.active:
      return AppStatusTone.success;
    case EmployeeStatus.invited:
      return AppStatusTone.warning;
    case EmployeeStatus.disabled:
      return AppStatusTone.danger;
    case EmployeeStatus.unknown:
      return AppStatusTone.neutral;
  }
}

AppStatusTone _accessTone(EmployeeAccessStatus status) {
  switch (status) {
    case EmployeeAccessStatus.active:
      return AppStatusTone.success;
    case EmployeeAccessStatus.temporaryPasswordPending:
      return AppStatusTone.warning;
    case EmployeeAccessStatus.disabled:
      return AppStatusTone.danger;
    case EmployeeAccessStatus.noAccess:
    case EmployeeAccessStatus.unknown:
      return AppStatusTone.neutral;
  }
}

IconData _accessIcon(EmployeeAccessStatus status) {
  switch (status) {
    case EmployeeAccessStatus.active:
      return Icons.verified_user_outlined;
    case EmployeeAccessStatus.temporaryPasswordPending:
      return Icons.password_rounded;
    case EmployeeAccessStatus.disabled:
      return Icons.block_rounded;
    case EmployeeAccessStatus.noAccess:
      return Icons.lock_open_rounded;
    case EmployeeAccessStatus.unknown:
      return Icons.info_outline_rounded;
  }
}

IconData _statusIcon(EmployeeStatus status) {
  switch (status) {
    case EmployeeStatus.active:
      return Icons.check_circle_outline_rounded;
    case EmployeeStatus.invited:
      return Icons.mail_outline_rounded;
    case EmployeeStatus.disabled:
      return Icons.block_rounded;
    case EmployeeStatus.unknown:
      return Icons.info_outline_rounded;
  }
}

String _commissionBadgeLabel(EmployeeProfile employee) {
  if (!employee.commissionEnabled ||
      employee.commissionType == EmployeeCommissionType.none) {
    return 'Comissão desativada';
  }
  if (employee.commissionType == EmployeeCommissionType.fixedPerSale) {
    return 'Comissão: ${AppFormatters.currencyFromCents(employee.commissionFixedCents ?? 0)} por venda';
  }
  return 'Comissão: ${_percentageInputFromBps(employee.commissionRateBps ?? 0)}% sobre ${_baseShortLabel(employee.commissionBase)}';
}

String _baseShortLabel(EmployeeCommissionBase base) {
  switch (base) {
    case EmployeeCommissionBase.grossSales:
      return 'venda bruta';
    case EmployeeCommissionBase.netSales:
      return 'venda líquida';
    case EmployeeCommissionBase.grossProfit:
      return 'lucro';
  }
}

String _percentageInputFromBps(int bps) {
  final whole = bps ~/ 100;
  final decimal = bps % 100;
  if (decimal == 0) {
    return '$whole';
  }
  return '$whole,${decimal.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}

int _parseBps(String raw) {
  return _tryParseBps(raw) ?? -1;
}

int? _tryParseBps(String raw) {
  final sanitized = raw.trim().replaceAll('%', '').trim().replaceAll(',', '.');
  if (sanitized.isEmpty || sanitized.startsWith('-')) {
    return null;
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(sanitized)) {
    return null;
  }
  final parts = sanitized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) {
    return null;
  }
  final decimalRaw = parts.length == 2 ? parts[1] : '';
  final decimal = int.tryParse('$decimalRaw${'00'}'.substring(0, 2)) ?? 0;
  return (whole * 100) + decimal;
}

int? _tryParseFixedCents(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 0;
  }
  if (!RegExp(r'\d').hasMatch(trimmed)) {
    return null;
  }
  final withoutCurrency = trimmed
      .replaceAll(RegExp(r'[Rr]\$?'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^-?[0-9.,]+$').hasMatch(withoutCurrency)) {
    return null;
  }
  return MoneyParser.parseToCents(trimmed);
}

String _errorMessage(Object error) {
  if (error is AppException) {
    return error.message;
  }
  return '$error';
}
