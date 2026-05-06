import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_empty_state.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../account/presentation/providers/account_cloud_providers.dart';
import '../../../estoque/domain/services/inventory_alert_service.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../domain/entities/operational_dashboard_snapshot.dart';
import '../providers/dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(operationalDashboardSnapshotProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final inventoryItemsAsync = ref.watch(inventoryItemOptionsProvider);
    final authStatus = ref.watch(authStatusProvider);
    final tokens = context.appColors;
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _DashboardAppBarTitle(
          title: 'Inicio',
          subtitle:
              '${_greeting(DateTime.now())} - Dashboard comercial - ${_dateLabel(DateTime.now())}',
        ),
        actions: [
          IconButton(
            tooltip: 'Status da conta e sincronizacao',
            onPressed: () => context.pushNamed(AppRouteNames.accountCloud),
            icon: Badge(
              isLabelVisible: accountCloud.pendingCount > 0,
              label: Text('${accountCloud.pendingCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: layout.space6),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: tokens.brand.surface,
              foregroundColor: tokens.brand.base,
              child: Text(
                _initial(authStatus.userLabel),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tokens.brand.base,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
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
            snapshotAsync.when(
              data: (snapshot) {
                final inventorySummary = InventoryAlertService.summarize(
                  inventoryItemsAsync.valueOrNull ?? const [],
                );
                final lowStockCount = inventorySummary.belowMinimumItems;
                final pendingSendCount = accountCloud.pendingCount;
                final recentSalesCount = snapshot.recentMovements
                    .where((movement) => movement.label == 'Venda recebida')
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FaturamentoHeroCard(
                      value: AppFormatters.currencyFromCents(
                        snapshot.soldTodayCents,
                      ),
                      caption: 'Resumo operacional do dispositivo',
                      onTap: () => _openTodaySales(context, ref),
                    ),
                    SizedBox(height: layout.sectionGap),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: layout.gridGap,
                      mainAxisSpacing: layout.gridGap,
                      childAspectRatio: 1.08,
                      children: [
                        AppMetricCard(
                          label: 'Vendas',
                          value: '$recentSalesCount',
                          caption: 'Nas movimentacoes recentes',
                          icon: Icons.point_of_sale_rounded,
                          accentColor: tokens.sales.base,
                          onTap: () => _openTodaySales(context, ref),
                        ),
                        AppMetricCard(
                          label: 'Fiado',
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
                          label: 'Clientes',
                          value: '-',
                          caption: 'Cadastro em Clientes',
                          icon: Icons.people_alt_rounded,
                          accentColor: tokens.info.base,
                          onTap: () => context.pushNamed(AppRouteNames.clients),
                        ),
                        AppMetricCard(
                          label: 'Ticket medio',
                          value: '-',
                          caption: 'Disponivel nos relatorios',
                          icon: Icons.trending_up_rounded,
                          accentColor: tokens.success.base,
                          onTap: () => context.pushNamed(AppRouteNames.reports),
                        ),
                      ],
                    ),
                    SizedBox(height: layout.sectionGap),
                    AppSectionCard(
                      title: 'Acesso rapido',
                      child: GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: layout.gridGap,
                        mainAxisSpacing: layout.gridGap,
                        childAspectRatio: 0.78,
                        children: [
                          _QuickAccessItem(
                            label: 'Nova venda',
                            icon: Icons.point_of_sale_rounded,
                            palette: tokens.sales,
                            onTap: () => context.pushNamed(AppRouteNames.sales),
                          ),
                          _QuickAccessItem(
                            label: 'Cliente',
                            icon: Icons.person_add_alt_1_rounded,
                            palette: tokens.info,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.clientForm),
                          ),
                          _QuickAccessItem(
                            label: 'Caixa',
                            icon: Icons.account_balance_wallet_rounded,
                            palette: tokens.cashflowPositive,
                            onTap: () => context.pushNamed(AppRouteNames.cash),
                          ),
                          _QuickAccessItem(
                            label: 'Relatorio',
                            icon: Icons.insights_rounded,
                            palette: tokens.success,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.reports),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    AppSectionCard(
                      title: 'Ultimas vendas',
                      subtitle: 'Transacoes reais recentes do caixa local.',
                      child: snapshot.recentMovements.isEmpty
                          ? const AppEmptyState(
                              title: 'Sem transacoes recentes',
                              message:
                                  'Quando uma venda ou movimento de caixa acontecer, ela aparece aqui.',
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
                    SizedBox(height: layout.sectionGap),
                    _DashboardSyncCard(accountCloud: accountCloud),
                    if (lowStockCount > 0 || pendingSendCount > 0) ...[
                      SizedBox(height: layout.sectionGap),
                      AppSectionCard(
                        title: 'Alertas',
                        child: Column(
                          children: [
                            if (lowStockCount > 0)
                              _DashboardAlertTile(
                                title: 'Produtos com estoque baixo',
                                subtitle:
                                    '$lowStockCount produto(s) precisam de reposicao.',
                                icon: Icons.inventory_2_outlined,
                                tone: AppCardTone.warning,
                                onTap: () =>
                                    context.pushNamed(AppRouteNames.inventory),
                              ),
                            if (lowStockCount > 0 && pendingSendCount > 0)
                              SizedBox(height: layout.blockGap),
                            if (pendingSendCount > 0)
                              _DashboardAlertTile(
                                title: 'Vendas aguardando envio',
                                subtitle:
                                    '$pendingSendCount registro(s) aguardando sincronizacao.',
                                icon: Icons.schedule_send_rounded,
                                tone: AppCardTone.info,
                                onTap: () => context.pushNamed(
                                  AppRouteNames.accountCloud,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: AppStateCard(
                  title: 'Atualizando dashboard',
                  message: 'Buscando o resumo mais recente do dia.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar o dashboard',
                subtitle: error.toString(),
                tone: AppCardTone.danger,
                child: AppStateCard(
                  title: 'Nao foi possivel atualizar o dashboard',
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

class _DashboardAppBarTitle extends StatelessWidget {
  const _DashboardAppBarTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FaturamentoHeroCard extends StatelessWidget {
  const _FaturamentoHeroCard({
    required this.value,
    required this.caption,
    required this.onTap,
  });

  final String value;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(layout.space10),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F7B5C), Color(0xFF17A878)],
      ),
      borderColor: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.payments_rounded,
                      color: Colors.white.withValues(alpha: 0.82),
                      size: layout.iconLg,
                    ),
                    SizedBox(width: layout.space4),
                    Text(
                      'Faturamento hoje',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: layout.space3),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: layout.space3,
                        vertical: layout.space2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(layout.radiusSm),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Vendas de hoje',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: layout.space6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: layout.space3),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: layout.space8),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(layout.radiusLg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessItem extends StatelessWidget {
  const _QuickAccessItem({
    required this.label,
    required this.icon,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final AppTonePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return InkWell(
      borderRadius: BorderRadius.circular(layout.radiusLg),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(layout.radiusLg),
              border: Border.all(color: palette.border),
            ),
            child: Icon(icon, color: palette.base, size: 24),
          ),
          SizedBox(height: layout.space5),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.appColors.interactive.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardSyncCard extends StatelessWidget {
  const _DashboardSyncCard({required this.accountCloud});

  final AccountCloudStatusSnapshot accountCloud;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final colors = context.appColors;

    return AppCard(
      padding: EdgeInsets.all(layout.cardPadding),
      color: colors.cardBackground,
      borderColor: colors.outlineSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: EdgeInsets.only(top: layout.space3),
            decoration: BoxDecoration(
              color: _syncDotColor(accountCloud.tone, colors),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: layout.space5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Status de sync',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AppStatusBadge(
                      label: accountCloud.statusLabel,
                      tone: accountCloud.tone,
                      icon: accountCloud.icon,
                    ),
                  ],
                ),
                SizedBox(height: layout.space4),
                Text(
                  accountCloud.statusMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (accountCloud.pendingCount > 0 ||
                    accountCloud.conflictCount > 0 ||
                    accountCloud.errorCount > 0) ...[
                  SizedBox(height: layout.space5),
                  Wrap(
                    spacing: layout.space3,
                    runSpacing: layout.space3,
                    children: [
                      if (accountCloud.pendingCount > 0)
                        AppStatusBadge(
                          label: '${accountCloud.pendingCount} pendente(s)',
                          tone: AppStatusTone.info,
                        ),
                      if (accountCloud.conflictCount > 0)
                        AppStatusBadge(
                          label: '${accountCloud.conflictCount} conflito(s)',
                          tone: AppStatusTone.warning,
                        ),
                      if (accountCloud.errorCount > 0)
                        AppStatusBadge(
                          label: '${accountCloud.errorCount} erro(s)',
                          tone: AppStatusTone.danger,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _syncDotColor(AppStatusTone tone, AppColorTokens colors) {
    return switch (tone) {
      AppStatusTone.success => colors.success.base,
      AppStatusTone.warning => colors.warning.base,
      AppStatusTone.danger => colors.danger.base,
      AppStatusTone.info => colors.info.base,
      AppStatusTone.neutral => colors.interactive.onSurface,
    };
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

String _greeting(DateTime now) {
  if (now.hour < 12) {
    return 'Bom dia';
  }
  if (now.hour < 18) {
    return 'Boa tarde';
  }
  return 'Boa noite';
}

String _dateLabel(DateTime now) {
  final day = now.day.toString().padLeft(2, '0');
  final month = now.month.toString().padLeft(2, '0');
  return 'Hoje, $day/$month/${now.year}';
}

String _initial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'T';
  }
  return trimmed.substring(0, 1).toUpperCase();
}
