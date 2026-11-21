import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';
import '../../../core/widgets/owner_responsive_layout.dart';
import '../../../core/widgets/owner_sales_chart.dart';
import '../../employees/presentation/owner_employees_page.dart';

class OwnerDashboardPage extends ConsumerWidget {
  const OwnerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(ownerDashboardProvider);
    final employees = ref.watch(ownerEmployeesProvider);
    final sales = ref.watch(ownerDashboardSalesProvider);
    final receivables = ref.watch(ownerDashboardReceivablesProvider);
    final busy = ref.watch(ownerEmployeeBusyProvider);
    return OwnerAsyncView(
      value: dashboard,
      onRetry: () => ref.invalidate(ownerDashboardProvider),
      builder: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (dashboard.isRefreshing)
              const LinearProgressIndicator(
                semanticsLabel: 'Atualizando painel',
              ),
            OwnerPageIntro(
              title: 'Visão geral da empresa',
              subtitle:
                  'Vendas, equipe, estoque e contas a receber. Dados sincronizados da sua empresa.',
              icon: Icons.space_dashboard_outlined,
              trailing: OutlinedButton.icon(
                onPressed: () =>
                    ref.read(ownerRefreshTickProvider.notifier).state++,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar painel'),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Mês atual • ${_periodLabel(data.period)} • ${data.period.timezone}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OwnerGrid(
              minWidth: 180,
              children: [
                OwnerMetricCard(
                  width: null,
                  title: 'Vendas hoje',
                  value: _moneyOrUnavailable(data.sales.todayAmountCents),
                  detail: _salesDetail(data.sales.todayCount, 'hoje'),
                  icon: Icons.shopping_cart_outlined,
                  accent: const Color(0xFF167440),
                  isAvailable: data.sales.todayAmountCents != null,
                  onTap: () => context.go('/sales'),
                ),
                OwnerMetricCard(
                  width: null,
                  title: 'Faturamento do mês',
                  value: _moneyOrUnavailable(data.sales.monthAmountCents),
                  detail: _salesDetail(data.sales.monthCount, 'no mês'),
                  icon: Icons.payments_outlined,
                  accent: const Color(0xFF2563C9),
                  isAvailable: data.sales.monthAmountCents != null,
                  onTap: () => context.go('/sales'),
                ),
                OwnerMetricCard(
                  width: null,
                  title: 'Contas a receber',
                  value: _moneyOrUnavailable(data.receivables.openAmountCents),
                  detail: data.receivables.openCount == null
                      ? 'Consulta indisponível'
                      : '${data.receivables.openCount} contas em aberto.',
                  icon: Icons.request_quote_outlined,
                  accent: const Color(0xFFA85B00),
                  isAvailable: data.receivables.openAmountCents != null,
                  onTap: () => context.go('/finance'),
                ),
                OwnerMetricCard(
                  width: null,
                  title: 'Ticket médio',
                  value: _moneyOrUnavailable(data.sales.averageTicketCents),
                  detail: 'Valor médio por venda no mês.',
                  icon: Icons.insights_outlined,
                  isAvailable: data.sales.averageTicketCents != null,
                  onTap: () => context.go('/reports'),
                ),
                OwnerMetricCard(
                  width: null,
                  title: 'Estoque baixo',
                  value: _numberOrUnavailable(data.products.lowStock),
                  detail: data.products.outOfStock == null
                      ? 'Consulta indisponível'
                      : '${data.products.outOfStock} produtos zerados.',
                  icon: Icons.inventory_2_outlined,
                  accent: const Color(0xFFB43D4D),
                  isAvailable: data.products.lowStock != null,
                  onTap: () => context.go('/products'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            OwnerSplitLayout(
              primary: OwnerSectionCard(
                title: 'Resumo de vendas',
                subtitle: 'Evolução das vendas sincronizadas no período.',
                trailing: DropdownButton<int>(
                  value: ref.watch(ownerDashboardDaysProvider),
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(ownerDashboardDaysProvider.notifier).state =
                          value;
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('Últimos 7 dias')),
                    DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
                  ],
                ),
                child: OwnerAsyncView(
                  value: sales,
                  onRetry: () => ref.invalidate(ownerDashboardSalesProvider),
                  builder: (value) => OwnerSalesChart(points: value.series),
                ),
              ),
              secondary: OwnerSectionCard(
                title: 'Funcionários',
                subtitle: 'Equipe e situação dos acessos.',
                trailing: TextButton(
                  onPressed: () => context.go('/employees'),
                  child: const Text('Ver todos'),
                ),
                child: OwnerAsyncView(
                  value: employees,
                  onRetry: () => ref.invalidate(ownerEmployeesProvider),
                  builder: (team) => !team.available
                      ? const OwnerEmptyState(
                          title: 'Equipe indisponível',
                          message:
                              'Atualize os dados ou consulte a página de funcionários.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (team.items.isEmpty)
                              const OwnerEmptyState(
                                title: 'Nenhum funcionário cadastrado',
                                message:
                                    'Cadastre sua equipe para gerenciar os acessos.',
                              ),
                            for (final person in team.items.take(4))
                              OwnerInfoRow(
                                title: person.name,
                                subtitle:
                                    '${ownerEmployeeRoleLabel(person.role)} • ${ownerEmployeeAccessLabel(person.accessStatus)}',
                                leading: CircleAvatar(
                                  child: Text(
                                    person.name.isEmpty
                                        ? '?'
                                        : person.name
                                              .substring(0, 1)
                                              .toUpperCase(),
                                  ),
                                ),
                                trailing: Chip(
                                  label: Text(
                                    person.status == 'DISABLED'
                                        ? 'Inativo'
                                        : person.status == 'INVITED'
                                        ? 'Convidado'
                                        : 'Ativo',
                                  ),
                                ),
                              ),
                            if (team.canManage)
                              FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => openOwnerEmployeeCreation(
                                        context,
                                        ref,
                                      ),
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(),
                                      )
                                    : const Icon(Icons.add),
                                label: const Text('Adicionar funcionário'),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            OwnerSplitLayout(
              primary: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OwnerSectionCard(
                    title: 'Atalhos rápidos',
                    subtitle: 'Acesse a operação e os cadastros existentes.',
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.go('/sales'),
                          icon: const Icon(Icons.shopping_cart_outlined),
                          label: const Text('Consultar vendas'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/reports/cash'),
                          icon: const Icon(Icons.point_of_sale_outlined),
                          label: const Text('Conferir caixas'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/products'),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Produtos e estoque'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/employees'),
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Gerenciar acessos'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OwnerSectionCard(
                    title: 'Contas a receber',
                    subtitle: 'Até cinco contas em aberto.',
                    trailing: TextButton(
                      onPressed: () => context.go('/finance'),
                      child: const Text('Ver todas'),
                    ),
                    child: OwnerAsyncView(
                      value: receivables,
                      onRetry: () =>
                          ref.invalidate(ownerDashboardReceivablesProvider),
                      builder: (value) => value.items.items.isEmpty
                          ? const OwnerEmptyState(
                              title: 'Nenhuma conta em aberto',
                              message:
                                  'As pendências de fiado aparecerão aqui.',
                            )
                          : Column(
                              children: [
                                for (final item in value.items.items)
                                  OwnerInfoRow(
                                    title: item.customerName,
                                    subtitle:
                                        '${item.dueDate == null ? 'Sem vencimento informado' : 'Vencimento: ${item.dueDate}'} • ${item.overdueAmountCents > 0 ? 'Em atraso' : 'Em aberto'}',
                                    trailing: Text(
                                      OwnerFormatters.moneyFromCents(
                                        item.openAmountCents,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              secondary: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OwnerSectionCard(
                    title: 'Alertas da empresa',
                    child: _BusinessAlerts(alerts: data.alerts),
                  ),
                  const SizedBox(height: 16),
                  OwnerSectionCard(
                    title: 'Últimas atividades',
                    subtitle: 'Vendas registradas no período selecionado.',
                    trailing: TextButton(
                      onPressed: () => context.go('/sales'),
                      child: const Text('Ver vendas'),
                    ),
                    child: OwnerAsyncView(
                      value: sales,
                      onRetry: () =>
                          ref.invalidate(ownerDashboardSalesProvider),
                      builder: (value) => value.recentSales.items.isEmpty
                          ? const OwnerEmptyState(
                              title: 'Nenhuma venda no período',
                              message:
                                  'As vendas sincronizadas aparecerão aqui.',
                            )
                          : Column(
                              children: [
                                for (final sale in value.recentSales.items.take(
                                  5,
                                ))
                                  OwnerInfoRow(
                                    title: sale.title,
                                    subtitle:
                                        '${sale.customerName ?? 'Sem cliente vinculado'} • ${sale.status == 'cancelled' || sale.status == 'canceled' ? 'Cancelada' : 'Registrada'}\n${sale.soldAt ?? 'Data não informada'}',
                                    trailing: Text(
                                      OwnerFormatters.moneyFromCents(
                                        sale.totalAmountCents,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            OwnerGrid(
              minWidth: 300,
              children: [
                OwnerSectionCard(
                  title: 'Top produtos',
                  child: _ProductRanking(items: data.products.topSelling),
                ),
                OwnerSectionCard(
                  title: 'Top clientes',
                  child: _CustomerRanking(items: data.customers.topCustomers),
                ),
                OwnerSectionCard(
                  title: 'Vendas por funcionário',
                  child: _EmployeeRanking(employees: data.employees),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProductRanking extends StatelessWidget {
  const _ProductRanking({required this.items});

  final List<OwnerProductSalesItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem vendas de produtos no período',
        message:
            'Quando houver vendas vinculadas aos produtos, o ranking aparecerá aqui.',
      );
    }
    return Column(
      children: [
        for (final item in items)
          OwnerInfoRow(
            title: item.productName,
            subtitle:
                '${item.salesCount} vendas - ${OwnerFormatters.quantityFromMil(item.quantityMil)} un.',
            trailing: Text(OwnerFormatters.moneyFromCents(item.amountCents)),
          ),
      ],
    );
  }
}

class _CustomerRanking extends StatelessWidget {
  const _CustomerRanking({required this.items});

  final List<OwnerCrmCustomer> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem clientes para destacar',
        message:
            'Os principais clientes aparecerão quando houver compras registradas.',
      );
    }
    return Column(
      children: [
        for (final item in items)
          OwnerInfoRow(
            title: item.name,
            subtitle: '${item.purchasesCount} compras',
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.totalPurchasedCents),
            ),
          ),
      ],
    );
  }
}

class _EmployeeRanking extends StatelessWidget {
  const _EmployeeRanking({required this.employees});

  final OwnerBusinessEmployeesMetrics employees;

  @override
  Widget build(BuildContext context) {
    if (!employees.available) {
      return const OwnerEmptyState(
        title: 'Indicador em preparação',
        message:
            'Este indicador será liberado quando houver dados suficientes.',
        icon: Icons.badge_outlined,
      );
    }
    if (employees.topPerformers.isEmpty) {
      return const OwnerEmptyState(
        title: 'Sem vendas por funcionário no período',
        message:
            'Quando houver vendas vinculadas aos usuários, o ranking aparecerá aqui.',
        icon: Icons.badge_outlined,
      );
    }
    return Column(
      children: [
        for (final item in employees.topPerformers)
          OwnerInfoRow(
            title: item.name,
            subtitle: '${item.salesCount} vendas',
            trailing: Text(
              OwnerFormatters.moneyFromCents(item.salesAmountCents),
            ),
          ),
      ],
    );
  }
}

class _BusinessAlerts extends StatelessWidget {
  const _BusinessAlerts({required this.alerts});

  final List<OwnerBusinessAlert> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhum alerta importante agora',
        message:
            'Alertas de vendas, estoque e financeiro aparecerão aqui quando houver algo relevante.',
        icon: Icons.check_circle_outline_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final alert in alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _alertIcon(alert.severity),
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.count == null
                        ? '${alert.title}: ${alert.message}'
                        : '${alert.title}: ${alert.message} (${alert.count})',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _moneyOrUnavailable(int? value) {
  if (value == null) {
    return 'Sem dados';
  }
  return OwnerFormatters.moneyFromCents(value);
}

String _numberOrUnavailable(int? value) {
  if (value == null) {
    return 'Sem dados';
  }
  return OwnerFormatters.integer(value);
}

String _salesDetail(int? count, String periodLabel) {
  if (count == null) {
    return 'Este indicador ainda não está disponível.';
  }
  return '$count ${count == 1 ? 'venda' : 'vendas'} $periodLabel.';
}

String _periodLabel(OwnerReportPeriod period) {
  if (period.startDate == null || period.endDate == null) {
    return 'Período atual';
  }
  return '${period.startDate} a ${period.endDate}';
}

IconData _alertIcon(String severity) {
  switch (severity.toLowerCase()) {
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'error':
      return Icons.error_outline_rounded;
    default:
      return Icons.info_outline_rounded;
  }
}
