import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../providers/dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dashboardMetricsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardMetricsProvider);
          await ref.read(dashboardMetricsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          children: [
            AppPageHeader(
              title: 'Painel do dia',
              subtitle: 'Venda, caixa e fiado em uma leitura rápida.',
              badgeLabel: 'Operação diária',
              badgeIcon: Icons.space_dashboard_rounded,
              trailing: SizedBox(
                width: 142,
                child: FilledButton.icon(
                  icon: const Icon(Icons.point_of_sale_rounded),
                  onPressed: () => context.pushNamed(AppRouteNames.sales),
                  label: const Text('Nova venda'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            metricsAsync.when(
              data: (metrics) {
                return AppSectionCard(
                  title: 'Indicadores principais',
                  subtitle: 'O que precisa de atenção agora.',
                  padding: const EdgeInsets.all(16),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.14,
                    children: [
                      AppMetricCard(
                        label: 'Vendido hoje',
                        value: AppFormatters.currencyFromCents(
                          metrics.soldTodayCents,
                        ),
                        caption: 'Vendas ativas do dia',
                        icon: Icons.point_of_sale_rounded,
                        onTap: () => _openTodaySales(context, ref),
                      ),
                      AppMetricCard(
                        label: 'Caixa atual',
                        value: AppFormatters.currencyFromCents(
                          metrics.currentCashCents,
                        ),
                        caption: 'Sessão em aberto',
                        icon: Icons.account_balance_wallet_rounded,
                        accentColor: colorScheme.secondary,
                        onTap: () => context.pushNamed(AppRouteNames.cash),
                      ),
                      AppMetricCard(
                        label: 'Fiado pendente',
                        value: AppFormatters.currencyFromCents(
                          metrics.pendingFiadoCents,
                        ),
                        caption:
                            '${metrics.pendingFiadoCount} nota(s) em aberto',
                        icon: Icons.receipt_long_rounded,
                        accentColor: AppTheme.warning,
                        onTap: () => context.pushNamed(AppRouteNames.fiado),
                      ),
                      AppMetricCard(
                        label: 'Lucro do dia',
                        value: AppFormatters.currencyFromCents(
                          metrics.realizedProfitTodayCents,
                        ),
                        caption: 'Bruto realizado',
                        icon: Icons.trending_up_rounded,
                        accentColor: colorScheme.tertiary,
                        onTap: () => context.pushNamed(AppRouteNames.reports),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: AppStateCard(
                  title: 'Atualizando indicadores',
                  message: 'Buscando os números mais recentes do dia.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar indicadores',
                subtitle: error.toString(),
                child: AppStateCard(
                  title: 'Não foi possível atualizar o painel',
                  message: 'Puxe para baixo ou tente novamente em instantes.',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(dashboardMetricsProvider),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppSectionCard(
              title: 'Ações rápidas',
              subtitle: 'Atalhos do dia com menos ruído visual.',
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.72,
                children: [
                  _QuickAction(
                    title: 'Nova venda',
                    subtitle: 'Abrir PDV',
                    icon: Icons.point_of_sale_rounded,
                    onTap: () => context.pushNamed(AppRouteNames.sales),
                  ),
                  _QuickAction(
                    title: 'Caixa',
                    subtitle: 'Sessão atual',
                    icon: Icons.account_balance_wallet_rounded,
                    onTap: () => context.pushNamed(AppRouteNames.cash),
                  ),
                  _QuickAction(
                    title: 'Receber nota',
                    subtitle: 'Fiado',
                    icon: Icons.receipt_long_rounded,
                    onTap: () => context.pushNamed(AppRouteNames.fiado),
                  ),
                  _QuickAction(
                    title: 'Nova compra',
                    subtitle: 'Entrada',
                    icon: Icons.shopping_bag_outlined,
                    onTap: () => context.pushNamed(AppRouteNames.purchaseForm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTodaySales(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    ref.read(saleHistorySearchQueryProvider.notifier).state = '';
    ref.read(saleHistoryStatusFilterProvider.notifier).state = null;
    ref.read(saleHistoryTypeFilterProvider.notifier).state = null;
    ref.read(saleHistoryFromProvider.notifier).state = startOfDay;
    ref.read(saleHistoryToProvider.notifier).state = endOfDay;
    context.pushNamed(AppRouteNames.salesHistory);
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
