import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerEmployeesPage extends ConsumerWidget {
  const OwnerEmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(ownerEmployeesProvider);
    final commissions = ref.watch(ownerCommissionsProvider);
    final performance = ref.watch(ownerEmployeeReportsProvider);
    return OwnerAsyncView(
      value: employees,
      onRetry: () {
        ref.invalidate(ownerEmployeesProvider);
        ref.invalidate(ownerCommissionsProvider);
        ref.invalidate(ownerEmployeeReportsProvider);
      },
      builder: (data) {
        final commissionData = commissions.valueOrNull;
        final performanceData = performance.valueOrNull;
        final summary = data.summary;
        final totalCommissions =
            commissionData?.totals.totalCommissionCents ?? 0;
        final eligibleSales = commissionData?.totals.totalSalesCount ?? 0;
        final missingCost =
            commissionData?.totals.salesWithoutReliableCostCount ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OwnerPageIntro(
              title: 'Funcionarios',
              subtitle:
                  'Acompanhe acessos, permissoes, atividade e comissoes da equipe em modo consulta.',
              icon: Icons.badge_outlined,
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
                  value: OwnerFormatters.moneyFromCents(totalCommissions),
                  detail: '$eligibleSales vendas no periodo selecionado.',
                  icon: Icons.price_check_rounded,
                  isAvailable: commissionData != null,
                ),
              ],
            ),
            if (missingCost > 0) ...[
              const SizedBox(height: 12),
              OwnerSectionCard(
                title: 'Atencao em comissoes',
                subtitle:
                    '$missingCost vendas com comissao sobre lucro ficaram com custo parcial ou ausente.',
                child: const Text(
                  'Revise o cadastro de custo dos produtos para melhorar a precisao dos proximos calculos.',
                ),
              ),
            ],
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Equipe',
              subtitle: 'Acesso, status, permissoes resumidas e comissao.',
              child: _EmployeesList(employees: data),
            ),
            const SizedBox(height: 18),
            OwnerSectionCard(
              title: 'Comissoes',
              subtitle: 'Estimativa por funcionario no periodo selecionado.',
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
            if (performanceData == null && performance.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        );
      },
    );
  }
}

class _EmployeesList extends StatelessWidget {
  const _EmployeesList({required this.employees});

  final OwnerEmployeesOverview employees;

  @override
  Widget build(BuildContext context) {
    if (employees.items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhum funcionario cadastrado',
        message: 'Quando a equipe for cadastrada, ela aparecera aqui.',
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
              'Permissoes: ${item.permissionsCount}',
            ),
            isThreeLine: true,
            trailing: Text(
              _commissionLabel(
                item.commissionEnabled,
                item.commissionType,
                item.commissionBase,
                item.commissionRateBps,
                item.commissionFixedCents,
              ),
              textAlign: TextAlign.end,
            ),
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
        message:
            'Funcionarios sem regra ativa aparecem apenas na lista da equipe.',
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
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(OwnerFormatters.moneyFromCents(row.commissionAmountCents)),
                Text(
                  _commissionRuleLabel(
                    row.commissionType,
                    row.commissionRateBps,
                    row.commissionFixedCents,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
    if (!report.available) {
      return const OwnerEmptyState(
        title: 'Indicador em preparacao',
        message:
            'Este indicador sera liberado quando houver dados suficientes.',
        icon: Icons.insights_rounded,
      );
    }
    if (report.topEmployees.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhuma venda por funcionario no periodo',
        message:
            'Quando houver vendas vinculadas aos usuarios, elas aparecerao aqui.',
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
    case 'MANAGER':
      return 'Gerente';
    case 'CASHIER':
      return 'Caixa';
    case 'SELLER':
      return 'Vendedor';
    case 'STOCK':
      return 'Estoque';
    default:
      return 'Leitura';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'ACTIVE':
      return 'ativo';
    case 'DISABLED':
      return 'desativado';
    case 'INVITED':
      return 'convidado';
    default:
      return status.toLowerCase();
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

String _commissionLabel(
  bool enabled,
  String type,
  String base,
  int? rateBps,
  int? fixedCents,
) {
  if (!enabled || type == 'NONE') {
    return 'Comissao desativada';
  }
  if (type == 'FIXED_PER_SALE') {
    return '${OwnerFormatters.moneyFromCents(fixedCents ?? 0)} por venda';
  }
  return '${_percentageFromBps(rateBps ?? 0)}% sobre ${_baseLabel(base)}';
}

String _commissionRuleLabel(String type, int? rateBps, int? fixedCents) {
  if (type == 'FIXED_PER_SALE') {
    return '${OwnerFormatters.moneyFromCents(fixedCents ?? 0)} por venda';
  }
  return '${_percentageFromBps(rateBps ?? 0)}%';
}

String _percentageFromBps(int bps) {
  final value = bps / 100;
  if (value == value.truncateToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}
