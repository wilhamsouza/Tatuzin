import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_quick_action_card.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../account/presentation/providers/account_cloud_providers.dart';
import '../../../estoque/domain/services/inventory_alert_service.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../providers/dashboard_providers.dart';
import '../../domain/entities/operational_dashboard_snapshot.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(operationalDashboardSnapshotProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final inventoryItemsAsync = ref.watch(inventoryItemOptionsProvider);
    final tokens = context.appColors;
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
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
              title: 'Inicio',
              subtitle: 'Veja como esta sua loja hoje.',
              badgeLabel: 'Resumo de hoje',
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
                    label: const Text('Novo pedido'),
                  ),
                ],
              ),
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            snapshotAsync.when(
              data: (snapshot) {
                final inventorySummary = InventoryAlertService.summarize(
                  inventoryItemsAsync.valueOrNull ?? const [],
                );
                final lowStockCount = inventorySummary.belowMinimumItems;
                final pendingSendCount = accountCloud.pendingCount;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionCard(
                      title: 'Resumo de hoje',
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: layout.gridGap,
                        mainAxisSpacing: layout.gridGap,
                        childAspectRatio: 1.12,
                        children: [
                          AppMetricCard(
                            label: 'Vendas de hoje',
                            value: AppFormatters.currencyFromCents(
                              snapshot.soldTodayCents,
                            ),
                            caption: 'Total vendido no dia',
                            icon: Icons.point_of_sale_rounded,
                            accentColor: tokens.sales.base,
                            onTap: () => _openTodaySales(context, ref),
                          ),
                          AppMetricCard(
                            label: 'Caixa',
                            value: AppFormatters.currencyFromCents(
                              snapshot.currentCashCents,
                            ),
                            caption: 'Saldo da sessao em aberto',
                            icon: Icons.account_balance_wallet_rounded,
                            accentColor: tokens.cashflowPositive.base,
                            onTap: () => context.pushNamed(AppRouteNames.cash),
                          ),
                          AppMetricCard(
                            label: 'Pedidos em aberto',
                            value:
                                '${snapshot.activeOperationalOrdersCount} pedido(s)',
                            caption: 'Rascunho, preparo ou retirada',
                            icon: Icons.pending_actions_rounded,
                            accentColor: tokens.info.base,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.orders),
                          ),
                          AppMetricCard(
                            label: 'Clientes devendo',
                            value: AppFormatters.currencyFromCents(
                              snapshot.pendingFiadoCents,
                            ),
                            caption:
                                '${snapshot.pendingFiadoCount} nota(s) em aberto',
                            icon: Icons.receipt_long_rounded,
                            accentColor: tokens.warning.base,
                            onTap: () => context.pushNamed(AppRouteNames.fiado),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    AppSectionCard(
                      title: 'Acoes rapidas',
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
                            title: 'Novo pedido',
                            subtitle: 'Abrir atendimento',
                            icon: Icons.receipt_long_rounded,
                            palette: tokens.info,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.orders),
                          ),
                          AppQuickActionCard(
                            title: 'Receber fiado',
                            subtitle: 'Baixar conta',
                            icon: Icons.payments_rounded,
                            palette: tokens.warning,
                            onTap: () => context.pushNamed(AppRouteNames.fiado),
                          ),
                          AppQuickActionCard(
                            title: 'Cadastrar produto',
                            subtitle: 'Novo item',
                            icon: Icons.add_box_rounded,
                            palette: tokens.cashflowPositive,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.productForm),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    AppSectionCard(
                      title: 'Alertas',
                      child: lowStockCount == 0 && pendingSendCount == 0
                          ? const AppStateCard(
                              title: 'Nada urgente agora',
                              message:
                                  'Quando sua loja precisar de atencao, os avisos aparecem aqui.',
                              compact: true,
                            )
                          : Column(
                              children: [
                                if (lowStockCount > 0) ...[
                                  _DashboardAlertTile(
                                    title: 'Produtos com estoque baixo',
                                    subtitle:
                                        '$lowStockCount produto(s) precisam de reposicao.',
                                    icon: Icons.inventory_2_outlined,
                                    tone: AppCardTone.warning,
                                    onTap: () => context.pushNamed(
                                      AppRouteNames.inventory,
                                    ),
                                  ),
                                ],
                                if (lowStockCount > 0 && pendingSendCount > 0)
                                  SizedBox(height: layout.blockGap),
                                if (pendingSendCount > 0)
                                  _DashboardAlertTile(
                                    title: 'Vendas aguardando envio',
                                    subtitle:
                                        '$pendingSendCount registro(s) aguardando envio.',
                                    icon: Icons.schedule_send_rounded,
                                    tone: AppCardTone.info,
                                    onTap: () => context.pushNamed(
                                      AppRouteNames.accountCloud,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    AppSectionCard(
                      title: 'Movimentos recentes',
                      subtitle:
                          'Ultimos registros do caixa para apoio rapido da loja.',
                      child: snapshot.recentMovements.isEmpty
                          ? const AppStateCard(
                              title: 'Sem movimentos recentes',
                              message:
                                  'Assim que o caixa registrar entradas ou saidas, elas aparecem aqui.',
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
                  title: 'Atualizando inicio',
                  message: 'Buscando o resumo mais recente do dia.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar o inicio',
                subtitle: error.toString(),
                tone: AppCardTone.danger,
                child: AppStateCard(
                  title: 'Nao foi possivel atualizar o inicio',
                  message: 'Puxe para baixo ou tente novamente em instantes.',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(operationalDashboardSnapshotProvider),
                ),
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

class _DashboardAlertTile extends StatelessWidget {
  const _DashboardAlertTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppCardTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final colors = context.appColors;
    final palette = switch (tone) {
      AppCardTone.warning => colors.warning,
      AppCardTone.info => colors.info,
      AppCardTone.danger => colors.danger,
      AppCardTone.success => colors.success,
      _ => colors.brand,
    };

    return AppListTileCard(
      title: title,
      subtitle: subtitle,
      tone: tone,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.base.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(layout.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(layout.space4),
          child: Icon(icon, color: palette.base, size: layout.iconMd),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
