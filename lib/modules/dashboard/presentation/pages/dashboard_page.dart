import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_quick_action_card.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../providers/dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dashboardMetricsProvider);
    final tokens = context.appColors;
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardMetricsProvider);
          await ref.read(dashboardMetricsProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space5,
            layout.pagePadding,
            layout.space10,
          ),
          children: [
            AppPageHeader(
              title: 'Painel do dia',
              subtitle: 'Venda, caixa e fiado em uma leitura rapida.',
              badgeLabel: 'Operacao diaria',
              badgeIcon: Icons.space_dashboard_rounded,
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.point_of_sale_rounded),
                    onPressed: () => context.pushNamed(AppRouteNames.sales),
                    label: const Text('Nova venda'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_rounded),
                    onPressed: () => context.pushNamed(AppRouteNames.orders),
                    label: const Text('Pedidos'),
                  ),
                ],
              ),
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            metricsAsync.when(
              data: (metrics) {
                return AppSectionCard(
                  title: 'Indicadores principais',
                  subtitle: 'O que precisa de atencao agora.',
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: layout.gridGap,
                    mainAxisSpacing: layout.gridGap,
                    childAspectRatio: 1.12,
                    children: [
                      AppMetricCard(
                        label: 'Vendido hoje',
                        value: AppFormatters.currencyFromCents(
                          metrics.soldTodayCents,
                        ),
                        caption: 'Vendas ativas do dia',
                        icon: Icons.point_of_sale_rounded,
                        accentColor: tokens.sales.base,
                        onTap: () => _openTodaySales(context, ref),
                      ),
                      AppMetricCard(
                        label: 'Caixa atual',
                        value: AppFormatters.currencyFromCents(
                          metrics.currentCashCents,
                        ),
                        caption: 'Sessao em aberto',
                        icon: Icons.account_balance_wallet_rounded,
                        accentColor: tokens.cashflowPositive.base,
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
                        accentColor: tokens.warning.base,
                        onTap: () => context.pushNamed(AppRouteNames.fiado),
                      ),
                      AppMetricCard(
                        label: 'Lucro do dia',
                        value: AppFormatters.currencyFromCents(
                          metrics.realizedProfitTodayCents,
                        ),
                        caption: 'Bruto realizado',
                        icon: Icons.trending_up_rounded,
                        accentColor: tokens.info.base,
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
                  message: 'Buscando os numeros mais recentes do dia.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar indicadores',
                subtitle: error.toString(),
                tone: AppCardTone.danger,
                child: AppStateCard(
                  title: 'Nao foi possivel atualizar o painel',
                  message: 'Puxe para baixo ou tente novamente em instantes.',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref.invalidate(dashboardMetricsProvider),
                ),
              ),
            ),
            SizedBox(height: layout.sectionGap),
            AppSectionCard(
              title: 'Acoes rapidas',
              subtitle:
                  'Atalhos com linguagem visual igual ao restante do app.',
              tone: AppCardTone.muted,
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: layout.gridGap,
                mainAxisSpacing: layout.gridGap,
                childAspectRatio: 1.56,
                children: [
                  AppQuickActionCard(
                    title: 'Nova venda',
                    subtitle: 'Abrir PDV',
                    icon: Icons.point_of_sale_rounded,
                    palette: tokens.sales,
                    onTap: () => context.pushNamed(AppRouteNames.sales),
                  ),
                  AppQuickActionCard(
                    title: 'Caixa',
                    subtitle: 'Sessao atual',
                    icon: Icons.account_balance_wallet_rounded,
                    palette: tokens.cashflowPositive,
                    onTap: () => context.pushNamed(AppRouteNames.cash),
                  ),
                  AppQuickActionCard(
                    title: 'Receber nota',
                    subtitle: 'Fiado',
                    icon: Icons.receipt_long_rounded,
                    palette: tokens.warning,
                    onTap: () => context.pushNamed(AppRouteNames.fiado),
                  ),
                  AppQuickActionCard(
                    title: 'Nova compra',
                    subtitle: 'Entrada de estoque',
                    icon: Icons.shopping_bag_outlined,
                    palette: tokens.info,
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
