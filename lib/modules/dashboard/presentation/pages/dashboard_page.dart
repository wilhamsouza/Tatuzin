import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/constants/app_constants.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../providers/dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dashboardMetricsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardMetricsProvider);
          await ref.read(dashboardMetricsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            AppPageHeader(
              title: 'Dashboard operacional',
              subtitle:
                  'Acompanhe o dia com indicadores essenciais e poucos atalhos realmente operacionais.',
              badgeLabel: AppConstants.appName,
              badgeIcon: Icons.auto_awesome_rounded,
              emphasized: true,
              trailing: SizedBox(
                width: 154,
                child: AppButton.primary(
                  label: 'Nova venda',
                  icon: Icons.point_of_sale_rounded,
                  onPressed: () => context.pushNamed(AppRouteNames.sales),
                  compact: true,
                ),
              ),
            ),
            const SizedBox(height: 18),
            metricsAsync.when(
              data: (metrics) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                  children: [
                    AppMetricCard(
                      label: 'Vendido hoje',
                      value: AppFormatters.currencyFromCents(
                        metrics.soldTodayCents,
                      ),
                      caption: 'Total das vendas ativas do dia',
                      icon: Icons.point_of_sale_rounded,
                      accentColor: AppTheme.primary,
                      onTap: () => _openTodaySales(context, ref),
                    ),
                    AppMetricCard(
                      label: 'Caixa atual',
                      value: AppFormatters.currencyFromCents(
                        metrics.currentCashCents,
                      ),
                      caption: 'Saldo parcial da sess\u00e3o em aberto',
                      icon: Icons.account_balance_wallet_rounded,
                      accentColor: AppTheme.secondary,
                      onTap: () => context.pushNamed(AppRouteNames.cash),
                    ),
                    AppMetricCard(
                      label: 'Notas pendentes',
                      value: AppFormatters.currencyFromCents(
                        metrics.pendingFiadoCents,
                      ),
                      caption: '${metrics.pendingFiadoCount} nota(s) em aberto',
                      icon: Icons.receipt_long_rounded,
                      accentColor: AppTheme.warning,
                      onTap: () => context.pushNamed(AppRouteNames.fiado),
                    ),
                    AppMetricCard(
                      label: 'Lucro realizado',
                      value: AppFormatters.currencyFromCents(
                        metrics.realizedProfitTodayCents,
                      ),
                      caption: 'Lucro bruto reconhecido no dia',
                      icon: Icons.trending_up_rounded,
                      accentColor: AppTheme.success,
                      onTap: () => context.pushNamed(AppRouteNames.reports),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar indicadores',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(dashboardMetricsProvider),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppSectionCard(
              title: 'Atalhos r\u00e1pidos',
              subtitle:
                  'As a\u00e7\u00f5es do dia ficam aqui. Os demais m\u00f3dulos agora est\u00e3o no menu lateral.',
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.14,
                children: [
                  _QuickAction(
                    title: 'Nova venda',
                    subtitle: 'Ir para o PDV',
                    icon: Icons.point_of_sale_rounded,
                    onTap: () => context.pushNamed(AppRouteNames.sales),
                  ),
                  _QuickAction(
                    title: 'Caixa',
                    subtitle: 'Sess\u00e3o atual',
                    icon: Icons.account_balance_wallet_rounded,
                    onTap: () => context.pushNamed(AppRouteNames.cash),
                  ),
                  _QuickAction(
                    title: 'Receber nota',
                    subtitle: 'Fiado e cobran\u00e7a',
                    icon: Icons.receipt_long_rounded,
                    onTap: () => context.pushNamed(AppRouteNames.fiado),
                  ),
                  _QuickAction(
                    title: 'Nova compra',
                    subtitle: 'Registrar entrada',
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
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
