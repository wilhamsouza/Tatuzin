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
import '../../domain/entities/managerial_dashboard_readiness.dart';
import '../providers/dashboard_providers.dart';
import '../../domain/entities/operational_dashboard_snapshot.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(operationalDashboardSnapshotProvider);
    final managerialReadiness = ref.watch(managerialDashboardReadinessProvider);
    final tokens = context.appColors;
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard operacional')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(operationalDashboardSnapshotProvider);
          await ref.read(operationalDashboardSnapshotProvider.future);
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
              title: 'Dashboard operacional',
              subtitle:
                  'Venda, caixa, pedidos, fiado e movimentos locais da base atual. Esta home nao representa consolidacao oficial multiusuario.',
              badgeLabel: 'Operacao local',
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
            snapshotAsync.when(
              data: (snapshot) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionCard(
                      title: 'Indicadores operacionais locais',
                      subtitle:
                          'Leitura rapida da sessao e da fila local de trabalho. Nada aqui deve ser tratado como relatorio gerencial consolidado.',
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
                              snapshot.soldTodayCents,
                            ),
                            caption: 'Vendas ativas conhecidas nesta base',
                            icon: Icons.point_of_sale_rounded,
                            accentColor: tokens.sales.base,
                            onTap: () => _openTodaySales(context, ref),
                          ),
                          AppMetricCard(
                            label: 'Caixa atual',
                            value: AppFormatters.currencyFromCents(
                              snapshot.currentCashCents,
                            ),
                            caption: 'Saldo local da sessao em aberto',
                            icon: Icons.account_balance_wallet_rounded,
                            accentColor: tokens.cashflowPositive.base,
                            onTap: () => context.pushNamed(AppRouteNames.cash),
                          ),
                          AppMetricCard(
                            label: 'Fiado operacional',
                            value: AppFormatters.currencyFromCents(
                              snapshot.pendingFiadoCents,
                            ),
                            caption:
                                '${snapshot.pendingFiadoCount} nota(s) em aberto',
                            icon: Icons.receipt_long_rounded,
                            accentColor: tokens.warning.base,
                            onTap: () => context.pushNamed(AppRouteNames.fiado),
                          ),
                          AppMetricCard(
                            label: 'Pendencias operacionais',
                            value:
                                '${snapshot.activeOperationalOrdersCount} pedido(s)',
                            caption: 'Pedidos em rascunho, fila ou preparo',
                            icon: Icons.pending_actions_rounded,
                            accentColor: tokens.info.base,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.orders),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    AppSectionCard(
                      title: 'Movimentos recentes',
                      subtitle:
                          'Ultimos registros do caixa local para apoio rapido da operacao.',
                      child: snapshot.recentMovements.isEmpty
                          ? const AppStateCard(
                              title: 'Sem movimentos recentes',
                              message:
                                  'Assim que o caixa registrar entradas ou saidas locais, elas aparecem aqui.',
                              compact: true,
                            )
                          : Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < snapshot.recentMovements.length;
                                  index++
                                ) ...[
                                  _RecentMovementTile(
                                    movement: snapshot.recentMovements[index],
                                  ),
                                  if (index <
                                      snapshot.recentMovements.length - 1)
                                    SizedBox(height: layout.blockGap),
                                ],
                              ],
                            ),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: AppStateCard(
                  title: 'Atualizando painel operacional',
                  message: 'Buscando a leitura local mais recente do dia.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar o dashboard operacional',
                subtitle: error.toString(),
                tone: AppCardTone.danger,
                child: AppStateCard(
                  title: 'Nao foi possivel atualizar a home operacional',
                  message: 'Puxe para baixo ou tente novamente em instantes.',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(operationalDashboardSnapshotProvider),
                ),
              ),
            ),
            SizedBox(height: layout.sectionGap),
            AppSectionCard(
              title: managerialReadiness.title,
              subtitle: managerialReadiness.message,
              tone: AppCardTone.muted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.space4,
                      vertical: layout.space3,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.info.base.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(layout.radiusMd),
                    ),
                    child: Text(
                      managerialReadiness.sourceLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tokens.info.base,
                      ),
                    ),
                  ),
                  SizedBox(height: layout.blockGap),
                  for (final indicator in managerialReadiness.plannedIndicators)
                    Padding(
                      padding: EdgeInsets.only(bottom: layout.blockGap),
                      child: _ManagerialIndicatorTile(indicator: indicator),
                    ),
                ],
              ),
            ),
            SizedBox(height: layout.sectionGap),
            AppSectionCard(
              title: 'Acoes rapidas',
              subtitle:
                  'Atalhos diretos da operacao local, com a mesma linguagem visual do restante do app.',
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

class _RecentMovementTile extends StatelessWidget {
  const _RecentMovementTile({required this.movement});

  final OperationalDashboardRecentMovement movement;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final colors = context.appColors;
    final amountColor = switch (movement.direction) {
      OperationalDashboardMovementDirection.inflow =>
        colors.cashflowPositive.base,
      OperationalDashboardMovementDirection.outflow => colors.danger.base,
      OperationalDashboardMovementDirection.neutral => colors.info.base,
    };
    final icon = switch (movement.direction) {
      OperationalDashboardMovementDirection.inflow => Icons.south_west_rounded,
      OperationalDashboardMovementDirection.outflow => Icons.north_east_rounded,
      OperationalDashboardMovementDirection.neutral => Icons.sync_alt_rounded,
    };

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(layout.radiusMd),
            ),
            child: Padding(
              padding: EdgeInsets.all(layout.space4),
              child: Icon(icon, color: amountColor, size: layout.iconMd),
            ),
          ),
          SizedBox(width: layout.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: layout.space2),
                Text(
                  movement.description?.trim().isNotEmpty == true
                      ? movement.description!
                      : AppFormatters.shortDateTime(movement.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: layout.space4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppFormatters.currencyFromCents(movement.amountCents),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              SizedBox(height: layout.space2),
              Text(
                AppFormatters.shortDateTime(movement.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManagerialIndicatorTile extends StatelessWidget {
  const _ManagerialIndicatorTile({required this.indicator});

  final ManagerialDashboardPlannedIndicator indicator;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return AppCard(
      padding: EdgeInsets.all(layout.compactCardPadding),
      tone: AppCardTone.muted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            indicator.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: layout.space2),
          Text(
            indicator.reason,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
