import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
import '../../../core/models/owner_models.dart';
import '../../../core/widgets/owner_async_view.dart';
import '../../../core/widgets/owner_formatters.dart';
import '../../../core/widgets/owner_management_widgets.dart';

class OwnerDashboardPage extends ConsumerWidget {
  const OwnerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(ownerDashboardProvider);
    return OwnerAsyncView(
      value: dashboard,
      onRetry: () => ref.invalidate(ownerDashboardProvider),
      builder: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OwnerPageIntro(
              title: 'Dashboard da empresa',
              subtitle:
                  'Visão gerencial de vendas, clientes, estoque, equipe e alertas do negócio.',
              icon: Icons.space_dashboard_rounded,
              trailing: Chip(label: Text(_periodLabel(data.period))),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                OwnerMetricCard(
                  title: 'Vendas hoje',
                  value: _moneyOrUnavailable(data.sales.todayAmountCents),
                  detail: _salesDetail(data.sales.todayCount, 'hoje'),
                  icon: Icons.point_of_sale_rounded,
                  isAvailable: data.sales.todayAmountCents != null,
                ),
                OwnerMetricCard(
                  title: 'Faturamento do mês',
                  value: _moneyOrUnavailable(data.sales.monthAmountCents),
                  detail: _salesDetail(data.sales.monthCount, 'no mês'),
                  icon: Icons.payments_outlined,
                  isAvailable: data.sales.monthAmountCents != null,
                ),
                OwnerMetricCard(
                  title: 'Ticket médio',
                  value: _moneyOrUnavailable(data.sales.averageTicketCents),
                  detail: 'Valor médio por venda no mês.',
                  icon: Icons.trending_up_rounded,
                  isAvailable: data.sales.averageTicketCents != null,
                ),
                OwnerMetricCard(
                  title: 'Contas a receber',
                  value: _moneyOrUnavailable(data.receivables.openAmountCents),
                  detail:
                      '${data.receivables.openCount ?? 0} contas em aberto.',
                  icon: Icons.request_quote_outlined,
                  isAvailable: data.receivables.openAmountCents != null,
                ),
                OwnerMetricCard(
                  title: 'Clientes ativos',
                  value: _numberOrUnavailable(data.customers.active),
                  detail: '${data.customers.total ?? 0} clientes no cadastro.',
                  icon: Icons.people_alt_outlined,
                  isAvailable: data.customers.active != null,
                ),
                OwnerMetricCard(
                  title: 'Estoque baixo',
                  value: _numberOrUnavailable(data.products.lowStock),
                  detail: '${data.products.outOfStock ?? 0} produtos zerados.',
                  icon: Icons.inventory_outlined,
                  isAvailable: data.products.lowStock != null,
                ),
                OwnerMetricCard(
                  title: 'Produtos zerados',
                  value: _numberOrUnavailable(data.products.outOfStock),
                  detail: '${data.products.total ?? 0} produtos monitorados.',
                  icon: Icons.remove_shopping_cart_outlined,
                  isAvailable: data.products.outOfStock != null,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Top produtos',
                    subtitle: 'Produtos com maior venda no período.',
                    child: _ProductRanking(items: data.products.topSelling),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Top clientes',
                    subtitle: 'Clientes com maior valor comprado.',
                    child: _CustomerRanking(items: data.customers.topCustomers),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Vendas por funcionário',
                    subtitle: 'Desempenho de atendimento e operação.',
                    child: _EmployeeRanking(employees: data.employees),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Alertas da empresa',
                    subtitle: 'Pontos que merecem atenção do gestor.',
                    child: _BusinessAlerts(alerts: data.alerts),
                  ),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.productName),
            subtitle: Text(
              '${item.salesCount} vendas - ${OwnerFormatters.quantityFromMil(item.quantityMil)} un.',
            ),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text('${item.purchasesCount} compras'),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text('${item.salesCount} vendas'),
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
