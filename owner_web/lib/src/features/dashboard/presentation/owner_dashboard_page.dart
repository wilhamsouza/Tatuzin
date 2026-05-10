import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/owner_providers.dart';
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
              trailing: Chip(
                label: Text('Plano ${ownerPlanLabel(data.billing.plan)}'),
              ),
            ),
            const SizedBox(height: 18),
            const Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                OwnerMetricCard(
                  title: 'Vendas hoje',
                  value: 'Em preparação',
                  detail:
                      'Este indicador será liberado quando os relatórios gerenciais estiverem disponíveis.',
                  icon: Icons.point_of_sale_rounded,
                ),
                OwnerMetricCard(
                  title: 'Faturamento do mês',
                  value: 'Em preparação',
                  detail: 'Resumo mensal de vendas da empresa.',
                  icon: Icons.payments_outlined,
                ),
                OwnerMetricCard(
                  title: 'Ticket médio',
                  value: 'Em preparação',
                  detail: 'Valor médio por venda no período.',
                  icon: Icons.trending_up_rounded,
                ),
                OwnerMetricCard(
                  title: 'Contas a receber',
                  value: 'Em preparação',
                  detail: 'Valores em aberto de fiado e recebíveis.',
                  icon: Icons.request_quote_outlined,
                ),
                OwnerMetricCard(
                  title: 'Clientes ativos',
                  value: 'Em preparação',
                  detail: 'Clientes com compras recentes.',
                  icon: Icons.people_alt_outlined,
                ),
                OwnerMetricCard(
                  title: 'Produtos com estoque baixo',
                  value: 'Em preparação',
                  detail: 'Alertas de reposição e ruptura.',
                  icon: Icons.inventory_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                const SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Top produtos',
                    subtitle: 'Produtos com maior venda no período.',
                    child: OwnerEmptyState(
                      title: 'Ranking em preparação',
                      message:
                          'Este indicador será liberado quando o relatório de vendas por produto estiver disponível.',
                    ),
                  ),
                ),
                const SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Top clientes',
                    subtitle: 'Clientes com maior recorrência ou valor.',
                    child: OwnerEmptyState(
                      title: 'CRM em preparação',
                      message:
                          'Os principais clientes aparecerão aqui quando os indicadores de CRM forem liberados.',
                    ),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Vendas por funcionário',
                    subtitle: 'Desempenho de atendimento e operação.',
                    child: OwnerEmptyState(
                      title: data.employees.available
                          ? 'Indicador em preparação'
                          : 'Relatórios de equipe em preparação',
                      message:
                          'As vendas por funcionário serão liberadas em uma próxima atualização.',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: OwnerSectionCard(
                    title: 'Alertas da empresa',
                    subtitle: 'Pontos que merecem atenção do gestor.',
                    child: _BusinessAlerts(
                      cancelAtPeriodEnd: data.billing.cancelAtPeriodEnd,
                      pendingPlan: data.billing.pendingPlan,
                      nextPaymentDate: data.billing.nextPaymentDate,
                    ),
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

class _BusinessAlerts extends StatelessWidget {
  const _BusinessAlerts({
    required this.cancelAtPeriodEnd,
    required this.pendingPlan,
    required this.nextPaymentDate,
  });

  final bool cancelAtPeriodEnd;
  final String? pendingPlan;
  final String? nextPaymentDate;

  @override
  Widget build(BuildContext context) {
    final alerts = <String>[
      if (cancelAtPeriodEnd)
        'A assinatura tem cancelamento programado. Confira a área de Assinatura.',
      if (pendingPlan != null)
        'Existe uma troca de plano aguardando confirmação.',
      if (nextPaymentDate != null)
        'Próxima cobrança prevista para ${OwnerFormatters.date(nextPaymentDate)}.',
    ];

    if (alerts.isEmpty) {
      return const OwnerEmptyState(
        title: 'Nenhum alerta importante agora',
        message:
            'Alertas de vendas, estoque, financeiro e assinatura aparecerão aqui quando houver algo relevante.',
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
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(alert)),
              ],
            ),
          ),
      ],
    );
  }
}
