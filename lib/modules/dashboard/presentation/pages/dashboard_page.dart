import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/sync/sync_providers.dart';
import '../../../../app/core/utils/payment_method_note_codec.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_empty_state.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/core/widgets/tatuzin_brand.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/routes/route_guards.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/theme/dashboard_theme.dart';
import '../../../account/presentation/providers/account_cloud_providers.dart';
import '../../../estoque/domain/services/inventory_alert_service.dart';
import '../../../estoque/presentation/providers/inventory_providers.dart';
import '../../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../../relatorios/presentation/widgets/sales_trend_chart_card.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/operational_dashboard_snapshot.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/dashboard_feed_widgets.dart';
import '../../../onboarding/presentation/onboarding_checklist.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) =>
      Theme(data: DashboardTheme.of(context), child: const _DashboardFeed());
}

class _DashboardFeed extends ConsumerStatefulWidget {
  const _DashboardFeed();

  @override
  ConsumerState<_DashboardFeed> createState() => _DashboardFeedState();
}

class _DashboardFeedState extends ConsumerState<_DashboardFeed> {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNextDay();
  }

  void _scheduleNextDay() {
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      ref.invalidate(dashboardDayProvider);
      _scheduleNextDay();
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    bool canOpen(String path) => canAccessNavigationPath(session, path);
    final canSell = canOpen(AppRoutePaths.sales);
    final canReadSales = canOpen(AppRoutePaths.salesHistory);
    final canCash = canOpen(AppRoutePaths.cash);
    final canInventory = canOpen(AppRoutePaths.inventory);
    final canReports = canOpen(AppRoutePaths.reports);
    final canFiado =
        session.hasFeature(FeatureKey.fiadoManagement) &&
        canOpen(AppRoutePaths.fiado);
    final snapshotAsync = ref.watch(operationalDashboardSnapshotProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final inventory = canInventory
        ? ref.watch(inventoryItemOptionsProvider)
        : null;
    final auth = ref.watch(authStatusProvider);
    final autoSync = ref.watch(autoSyncSnapshotProvider);
    final colors = context.appColors;
    final layout = context.appLayout;
    final alertCount =
        accountCloud.pendingCount +
        accountCloud.conflictCount +
        accountCloud.errorCount +
        accountCloud.blockedCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          'Tatuzin',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Status da conta e sincronização',
            onPressed: () => context.pushNamed(AppRouteNames.accountCloud),
            icon: Badge(
              isLabelVisible: alertCount > 0,
              label: Text('$alertCount'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Abrir perfil de ${auth.userLabel}',
            onPressed: () => context.pushNamed(AppRouteNames.profile),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: colors.brand.surface,
              foregroundColor: colors.brand.onSurface,
              child: Text(_initial(auth.userLabel)),
            ),
          ),
        ],
      ),
      drawer: const AppMainDrawer(),
      floatingActionButton: canSell
          ? FloatingActionButton.extended(
              heroTag: 'dashboard-new-sale',
              onPressed: () => context.pushNamed(AppRouteNames.sales),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nova venda'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardDayProvider);
          if (canInventory) ref.invalidate(inventoryItemOptionsProvider);
          try {
            await ref.read(operationalDashboardSnapshotProvider.future);
          } catch (_) {
            // The provider renders the recoverable error state below.
          }
        },
        child: ListView(
          key: const PageStorageKey('dashboard-feed'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            8,
            layout.pagePadding,
            96 * (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 2),
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TatuzinMascotBadge(size: 48),
                SizedBox(width: layout.blockGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.company.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_greeting(DateTime.now())} • ${_dateLabel(DateTime.now())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.pushNamed(AppRouteNames.accountCloud),
                icon: Icon(accountCloud.icon, size: 18),
                label: Text(accountCloud.statusLabel),
              ),
            ),
            SingleChildScrollView(
              key: const ValueKey('dashboard-shortcuts'),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canReadSales)
                    DashboardShortcut(
                      label: 'Vendas',
                      icon: Icons.bar_chart_rounded,
                      onTap: () => _openTodaySales(context, ref),
                    ),
                  if (canCash)
                    DashboardShortcut(
                      label: 'Caixa',
                      icon: Icons.point_of_sale_outlined,
                      onTap: () => context.pushNamed(AppRouteNames.cash),
                    ),
                  if (canInventory)
                    DashboardShortcut(
                      label: 'Estoque',
                      icon: Icons.inventory_2_outlined,
                      onTap: () => context.pushNamed(AppRouteNames.inventory),
                    ),
                  if (session.hasFeature(FeatureKey.employees) &&
                      canOpen(AppRoutePaths.employees))
                    DashboardShortcut(
                      label: 'Equipe',
                      icon: Icons.groups_outlined,
                      onTap: () => context.pushNamed(AppRouteNames.employees),
                    ),
                  if (canReports)
                    DashboardShortcut(
                      label: 'Relatórios',
                      icon: Icons.insights_rounded,
                      onTap: () => context.pushNamed(AppRouteNames.reports),
                    ),
                  if (canOpen(AppRoutePaths.products))
                    DashboardShortcut(
                      label: 'Produtos',
                      icon: Icons.shopping_bag_outlined,
                      onTap: () => context.pushNamed(AppRouteNames.products),
                    ),
                  if (canOpen(AppRoutePaths.clients))
                    DashboardShortcut(
                      label: 'Clientes',
                      icon: Icons.people_outline,
                      onTap: () => context.pushNamed(AppRouteNames.clients),
                    ),
                ],
              ),
            ),
            SizedBox(height: layout.sectionGap),
            const CompanyOnboardingCard(),
            snapshotAsync.when(
              data: (snapshot) {
                final lowStockCount = inventory?.hasValue == true
                    ? InventoryAlertService.summarize(
                        inventory!.requireValue,
                      ).belowMinimumItems
                    : null;
                final empty = _dashboardLooksEmpty(snapshot);
                final hydrating =
                    empty &&
                    (accountCloud.syncingNowCount > 0 ||
                        autoSync.isRunning ||
                        autoSync.isScheduled);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (empty &&
                        (alertCount > 0 ||
                            hydrating ||
                            accountCloud.statusLabel ==
                                'Dados do servidor desatualizados')) ...[
                      _DashboardDataNotice(
                        isLoading: hydrating,
                        accountCloud: accountCloud,
                      ),
                      SizedBox(height: layout.sectionGap),
                    ],
                    AppSectionCard(
                      title: 'Resumo do dia',
                      subtitle:
                          'Hoje, neste dispositivo. Valores da base local; o fiado vendido ainda pode estar a receber.',
                      tone: AppCardTone.brand,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DashboardMetricLayout(
                            children: [
                              if (canReadSales)
                                DashboardMetric(
                                  key: const ValueKey('dashboard-today-sales'),
                                  label: 'Vendas de hoje',
                                  value: AppFormatters.currencyFromCents(
                                    snapshot.soldTodayCents,
                                  ),
                                  caption:
                                      '${snapshot.todaySalesCount} venda(s) ativa(s)',
                                  icon: Icons.shopping_bag_outlined,
                                  onTap: () => _openTodaySales(context, ref),
                                ),
                              if (canCash)
                                DashboardMetric(
                                  label: 'Caixa atual',
                                  value: snapshot.hasOpenCashSession
                                      ? AppFormatters.currencyFromCents(
                                          snapshot.currentCashCents,
                                        )
                                      : 'Fechado',
                                  caption: snapshot.cashNeedsConfirmation
                                      ? 'Confirme o troco inicial'
                                      : snapshot.hasOpenCashSession
                                      ? 'Sessão aberta'
                                      : 'Abra para receber',
                                  icon: Icons.point_of_sale_outlined,
                                  accent: colors.info.base,
                                  onTap: () =>
                                      context.pushNamed(AppRouteNames.cash),
                                ),
                              if (canReports) const _DashboardProfit(),
                            ],
                          ),
                          if (!canReadSales && !canCash && !canReports)
                            const Text(
                              'Use os atalhos disponíveis para o seu acesso.',
                            ),
                          if (canInventory) ...[
                            SizedBox(height: layout.blockGap),
                            _DashboardAlertTile(
                              title: lowStockCount == null
                                  ? 'Estoque'
                                  : lowStockCount > 0
                                  ? 'Estoque baixo: $lowStockCount item(ns)'
                                  : 'Estoque em dia',
                              subtitle: inventory!.hasError
                                  ? 'Não foi possível consultar o estoque. Toque para conferir.'
                                  : lowStockCount == null
                                  ? 'Consultando disponibilidade…'
                                  : lowStockCount > 0
                                  ? 'Confira os itens que precisam de reposição.'
                                  : 'Nenhum item abaixo do mínimo cadastrado.',
                              icon: Icons.inventory_2_outlined,
                              tone: lowStockCount != null && lowStockCount > 0
                                  ? AppCardTone.warning
                                  : AppCardTone.standard,
                              onTap: () =>
                                  context.pushNamed(AppRouteNames.inventory),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    if (canReports) ...[
                      const _DashboardMovement(),
                      SizedBox(height: layout.sectionGap),
                    ],
                    AppSectionCard(
                      title: 'Pendências',
                      subtitle: 'O que precisa da sua atenção.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (canFiado && snapshot.pendingFiadoCount > 0)
                            _DashboardAlertTile(
                              title: 'Contas a receber',
                              subtitle:
                                  '${snapshot.pendingFiadoCount} nota(s) em aberto • ${AppFormatters.currencyFromCents(snapshot.pendingFiadoCents)}',
                              icon: Icons.receipt_long_outlined,
                              tone: AppCardTone.warning,
                              onTap: () =>
                                  context.pushNamed(AppRouteNames.fiado),
                            ),
                          if (canSell &&
                              snapshot.activeOperationalOrdersCount > 0)
                            _DashboardAlertTile(
                              title: 'Pedidos em andamento',
                              subtitle:
                                  '${snapshot.activeOperationalOrdersCount} pedido(s) para acompanhar.',
                              icon: Icons.assignment_outlined,
                              tone: AppCardTone.info,
                              onTap: () =>
                                  context.pushNamed(AppRouteNames.orders),
                            ),
                          if (canInventory &&
                              (lowStockCount == null || lowStockCount > 0))
                            _DashboardAlertTile(
                              title: 'Reposição de estoque',
                              subtitle: lowStockCount == null
                                  ? 'Consulta de estoque indisponível ou em andamento.'
                                  : '$lowStockCount item(ns) abaixo do mínimo.',
                              icon: Icons.inventory_2_outlined,
                              tone: AppCardTone.warning,
                              onTap: () =>
                                  context.pushNamed(AppRouteNames.inventory),
                            ),
                          if (alertCount > 0)
                            _DashboardAlertTile(
                              title: 'Sincronização',
                              subtitle:
                                  '${accountCloud.pendingCount} pendente(s), ${accountCloud.conflictCount} conflito(s), ${accountCloud.errorCount} erro(s), ${accountCloud.blockedCount} bloqueado(s).',
                              icon: Icons.sync_rounded,
                              tone: AppCardTone.info,
                              onTap: () =>
                                  context.pushNamed(AppRouteNames.accountCloud),
                            ),
                          if ((!canFiado || snapshot.pendingFiadoCount == 0) &&
                              (!canSell ||
                                  snapshot.activeOperationalOrdersCount == 0) &&
                              (!canInventory || lowStockCount == 0) &&
                              alertCount == 0)
                            const Text(
                              'Nenhuma pendência nos dados disponíveis para seu acesso.',
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                    if (canCash) ...[
                      AppSectionCard(
                        title: 'Últimas movimentações',
                        subtitle: snapshot.hasOpenCashSession
                            ? 'Até 5 movimentos do caixa aberto.'
                            : 'Até 5 movimentos de caixa registrados neste dispositivo.',
                        trailing: TextButton(
                          onPressed: () =>
                              context.pushNamed(AppRouteNames.cash),
                          child: const Text('Ver caixa'),
                        ),
                        child: snapshot.recentMovements.isEmpty
                            ? const AppEmptyState(
                                title: 'Sem transações recentes',
                                message:
                                    'As vendas recebidas e os movimentos de caixa aparecerão aqui.',
                                compact: true,
                              )
                            : Column(
                                children: [
                                  for (final movement
                                      in snapshot.recentMovements)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: layout.blockGap,
                                      ),
                                      child: _RecentMovementTile(
                                        movement: movement,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      SizedBox(height: layout.sectionGap),
                    ],
                    _DashboardSyncCard(accountCloud: accountCloud),
                  ],
                );
              },
              loading: () => const AppStateCard(
                title: 'Atualizando dashboard',
                message: 'Buscando o resumo mais recente do dia.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (_, _) => AppSectionCard(
                title: 'Falha ao carregar o dashboard',
                subtitle: 'Nao foi possivel atualizar o dashboard.',
                tone: AppCardTone.danger,
                child: AppStateCard(
                  title: 'Não foi possível atualizar o dashboard',
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
    ref.read(saleHistorySearchQueryProvider.notifier).state = '';
    ref.read(saleHistoryStatusFilterProvider.notifier).state = null;
    ref.read(saleHistoryTypeFilterProvider.notifier).state = null;
    ref.read(saleHistoryFromProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
    );
    ref.read(saleHistoryToProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    );
    context.pushNamed(AppRouteNames.salesHistory);
  }
}

class _DashboardProfit extends ConsumerWidget {
  const _DashboardProfit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dashboardDailyOverviewProvider);
    final overview = value.asData?.value;
    final available = overview != null && overview.isRealizedProfitAvailable;
    return DashboardMetric(
      label: 'Lucro realizado',
      value: available
          ? AppFormatters.currencyFromCents(overview.realizedProfitCents)
          : value.isLoading
          ? 'Consultando…'
          : 'Indisponível',
      caption: available
          ? 'Local • fiado proporcional ao recebido. Antes das despesas.'
          : value.isLoading
          ? 'Calculando com os custos registrados.'
          : overview?.realizedProfitUnavailableReason ??
                'Não foi possível consultar. Confira nos relatórios.',
      icon: Icons.insights_rounded,
      onTap: () => context.pushNamed(AppRouteNames.reports),
    );
  }
}

class _DashboardMovement extends ConsumerWidget {
  const _DashboardMovement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(dashboardSalesTrendProvider);
    final theme = Theme.of(context);
    // A contrasting feed card, using the same report widget and real series.
    const background = Color(0xFF3C2068);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB998FF),
      brightness: Brightness.dark,
    ).copyWith(surface: background);
    final colors = context.appColors.copyWith(
      cardBackground: background,
      outlineSoft: const Color(0xFF72539B),
      interactive: context.appColors.interactive.copyWith(
        onSurface: scheme.onSurfaceVariant,
      ),
      sales: context.appColors.sales.copyWith(base: const Color(0xFFD2B8FF)),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: scheme.primary),
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
        extensions: [
          ...theme.extensions.values.where((e) => e is! AppColorTokens),
          colors,
        ],
      ),
      child: trend.when(
        data: (points) => SalesTrendChartCard(
          title: 'Movimento da loja',
          emptyMessage:
              'As vendas registradas neste dispositivo nos últimos 7 dias aparecerão aqui.',
          subtitle:
              'Vendas líquidas • últimos 7 dias • base local, sem consolidar outros dispositivos.',
          points:
              points
                  .where((p) => p.salesCount > 0 || p.netSalesCents != 0)
                  .isEmpty
              ? const []
              : points,
        ),
        loading: () => const AppSectionCard(
          title: 'Movimento da loja',
          child: Text('Consultando as vendas dos últimos 7 dias…'),
        ),
        error: (_, _) => AppSectionCard(
          title: 'Movimento da loja',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Não foi possível consultar a série de vendas. O resumo do dia continua disponível.',
              ),
              TextButton(
                onPressed: () => ref.invalidate(dashboardSalesTrendProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _dashboardLooksEmpty(OperationalDashboardSnapshot snapshot) {
  return snapshot.soldTodayCents == 0 &&
      snapshot.currentCashCents == 0 &&
      snapshot.pendingFiadoCount == 0 &&
      snapshot.pendingFiadoCents == 0 &&
      snapshot.activeOperationalOrdersCount == 0 &&
      snapshot.recentMovements.isEmpty;
}

class _DashboardDataNotice extends StatelessWidget {
  const _DashboardDataNotice({
    required this.isLoading,
    required this.accountCloud,
  });

  final bool isLoading;
  final AccountCloudStatusSnapshot accountCloud;

  @override
  Widget build(BuildContext context) {
    final hasConflicts = accountCloud.conflictCount > 0;
    final hasErrors = accountCloud.errorCount > 0;
    final title = isLoading
        ? 'Carregando dados da empresa'
        : hasConflicts || hasErrors
        ? 'Sincronização precisa de revisão'
        : 'Dados do servidor desatualizados';
    final message = isLoading
        ? 'Estamos buscando os dados da nuvem para atualizar este dispositivo.'
        : hasConflicts || hasErrors
        ? 'Seus dados existem na nuvem, mas há conflitos de sincronização que precisam de revisão para atualizar este dispositivo.'
        : 'Não foi possível atualizar os dados da nuvem agora. Os dados locais preservados continuam disponíveis.';

    return AppStateCard(
      title: title,
      message: message,
      tone: isLoading ? AppStateTone.loading : AppStateTone.warning,
      compact: true,
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
                        'Seus dados',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AppStatusBadge(
                          label: accountCloud.statusLabel,
                          tone: accountCloud.tone,
                          icon: accountCloud.icon,
                        ),
                      ),
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

    return AppListTileCard(
      title: movement.label,
      subtitle: _friendlyMovementDescription(movement),
      leading: Icon(icon, color: amountColor, size: layout.iconLg),
      footer: Wrap(
        spacing: layout.space4,
        runSpacing: layout.space2,
        children: [
          Text(
            AppFormatters.currencyFromCents(movement.amountCents),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            AppFormatters.shortDateTime(movement.createdAt.toLocal()),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _friendlyMovementDescription(
  OperationalDashboardRecentMovement movement,
) {
  final rawDescription = movement.description;
  final paymentMethod = PaymentMethodNoteCodec.parse(rawDescription);
  final cleanDescription = PaymentMethodNoteCodec.clean(rawDescription);

  if (movement.label == 'Venda recebida') {
    if (paymentMethod != null) {
      return 'Pagamento em ${_paymentMethodText(paymentMethod)}.';
    }
    return 'Venda recebida no caixa.';
  }

  if (movement.label == 'Venda cancelada') {
    final reason = _extractReason(cleanDescription);
    return reason == null ? 'Devolução simples.' : 'Motivo: $reason';
  }

  final fallback = cleanDescription?.trim();
  if (fallback != null && fallback.isNotEmpty) {
    return _hideLongInternalIds(fallback);
  }
  return AppFormatters.shortDateTime(movement.createdAt);
}

String _paymentMethodText(PaymentMethod method) {
  switch (method) {
    case PaymentMethod.cash:
      return 'dinheiro';
    case PaymentMethod.pix:
      return 'Pix';
    case PaymentMethod.card:
      return 'cartão';
    case PaymentMethod.fiado:
      return 'fiado';
  }
}

String? _extractReason(String? description) {
  final value = description?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final marker = RegExp(
    r'motivo:\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(value);
  final reason = marker?.group(1)?.trim();
  if (reason == null || reason.isEmpty) {
    return null;
  }
  return _hideLongInternalIds(reason);
}

String _hideLongInternalIds(String value) {
  return value.replaceAllMapped(RegExp(r'\b\d{7,}\b'), (_) => 'registro');
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
