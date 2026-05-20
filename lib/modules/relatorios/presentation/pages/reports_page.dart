import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_overview_summary.dart';
import '../providers/report_providers.dart';
import '../support/report_kpi_delta_support.dart';
import '../widgets/report_data_origin_banner.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';
import '../widgets/report_shortcut_card.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final overviewAsync = ref.watch(reportOverviewProvider);
    final previousOverviewAsync = ref.watch(reportPreviousOverviewProvider);
    final layout = context.appLayout;
    final controller = ref.read(reportFilterProvider.notifier);

    void openRoute(String routeName) {
      try {
        context.pushNamed(routeName);
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao foi possivel abrir este relatorio agora. Tente novamente em instantes.',
            ),
          ),
        );
      }
    }

    void openDrilldown({
      required ReportPageKey page,
      required String routeName,
      required ReportFilter nextFilter,
      required String sourceLabel,
      required String message,
      bool isFocusOnly = false,
    }) {
      controller.applyDrilldown(
        page: page,
        nextFilter: nextFilter,
        sourcePage: ReportPageKey.overview,
        sourceLabel: sourceLabel,
        message: message,
        isFocusOnly: isFocusOnly,
      );
      try {
        context.pushNamed(routeName);
      } catch (_) {
        controller.clearDrilldown(page);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao foi possivel abrir este relatorio agora. Tente novamente em instantes.',
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorios')),
      drawer: const AppMainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(appDataRefreshProvider.notifier).state++;
          await ref.read(reportOverviewProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space5,
            layout.pagePadding,
            layout.pagePadding,
          ),
          children: [
            const ReportFilterToolbar(page: ReportPageKey.overview),
            const SizedBox(height: 8),
            const ReportDataOriginBanner(page: ReportPageKey.overview),
            SizedBox(height: layout.sectionGap),
            overviewAsync.when(
              data: (overview) => _ReportsHubContent(
                overview: overview,
                previousOverview: previousOverviewAsync.asData?.value,
                filter: filter,
                onOpenRoute: openRoute,
                onOpenDrilldown: openDrilldown,
              ),
              loading: () => const AppStateCard(
                title: 'Atualizando hub',
                message: 'Organizando os principais indicadores do periodo.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar o hub',
                message: '$error',
                tone: AppStateTone.error,
                compact: true,
                actionLabel: 'Tentar novamente',
                onAction: () =>
                    ref.read(appDataRefreshProvider.notifier).state++,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsHubContent extends StatelessWidget {
  const _ReportsHubContent({
    required this.overview,
    required this.previousOverview,
    required this.filter,
    required this.onOpenRoute,
    required this.onOpenDrilldown,
  });

  final ReportOverviewSummary overview;
  final ReportOverviewSummary? previousOverview;
  final ReportFilter filter;
  final ValueChanged<String> onOpenRoute;
  final void Function({
    required ReportPageKey page,
    required String routeName,
    required ReportFilter nextFilter,
    required String sourceLabel,
    required String message,
    bool isFocusOnly,
  })
  onOpenDrilldown;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportKpiGrid(
          items: [
            ReportKpiItem(
              label: 'Vendas brutas',
              value: AppFormatters.currencyFromCents(overview.grossSalesCents),
              caption: '${overview.salesCount} venda(s) no periodo',
              delta: ReportKpiDeltaSupport.money(
                currentCents: overview.grossSalesCents,
                previousCents: previousOverview?.grossSalesCents,
              ),
              icon: Icons.sell_outlined,
              accentColor: context.appColors.sales.base,
              onTap: () => onOpenDrilldown(
                page: ReportPageKey.sales,
                routeName: AppRouteNames.salesReports,
                nextFilter: filter.copyWith(
                  clearFocus: true,
                  onlyCanceled: false,
                ),
                sourceLabel: 'KPI Vendas brutas',
                message:
                    'O relatorio de vendas abriu com o mesmo periodo do hub.',
              ),
            ),
            ReportKpiItem(
              label: 'Recebido',
              value: AppFormatters.currencyFromCents(
                overview.totalReceivedCents,
              ),
              caption: 'Entradas liquidas registradas',
              delta: ReportKpiDeltaSupport.money(
                currentCents: overview.totalReceivedCents,
                previousCents: previousOverview?.totalReceivedCents,
              ),
              icon: Icons.account_balance_wallet_rounded,
              accentColor: context.appColors.cashflowPositive.base,
              onTap: () => onOpenDrilldown(
                page: ReportPageKey.cash,
                routeName: AppRouteNames.cashReports,
                nextFilter: filter.copyWith(
                  focus: ReportFocus.cashEntries,
                  clearPaymentMethod: true,
                  onlyCanceled: false,
                ),
                sourceLabel: 'KPI Recebido',
                message: 'O relatorio de caixa abriu com foco nas entradas.',
                isFocusOnly: true,
              ),
            ),
            ReportKpiItem(
              label: 'Lucro liquido',
              value: overview.isRealizedProfitAvailable
                  ? AppFormatters.currencyFromCents(
                      overview.realizedProfitCents,
                    )
                  : 'Nao informado',
              caption:
                  overview.realizedProfitUnavailableReason ??
                  'Lucro reconhecido no periodo',
              delta:
                  overview.isRealizedProfitAvailable &&
                      (previousOverview?.isRealizedProfitAvailable ?? false)
                  ? ReportKpiDeltaSupport.money(
                      currentCents: overview.realizedProfitCents,
                      previousCents: previousOverview?.realizedProfitCents,
                    )
                  : null,
              icon: Icons.trending_up_rounded,
              accentColor: context.appColors.success.base,
              onTap: () => onOpenDrilldown(
                page: ReportPageKey.profitability,
                routeName: AppRouteNames.profitabilityReports,
                nextFilter: filter.copyWith(
                  grouping: ReportGrouping.product,
                  focus: ReportFocus.profitabilityTop,
                  onlyCanceled: false,
                ),
                sourceLabel: 'KPI Lucro liquido',
                message:
                    'A lucratividade abriu destacando os itens com maior lucro.',
                isFocusOnly: true,
              ),
            ),
            ReportKpiItem(
              label: 'Fiado aberto',
              value: AppFormatters.currencyFromCents(
                overview.pendingFiadoCents,
              ),
              caption: '${overview.pendingFiadoCount} nota(s) em aberto',
              delta: ReportKpiDeltaSupport.money(
                currentCents: overview.pendingFiadoCents,
                previousCents: previousOverview?.pendingFiadoCents,
                increaseIsPositive: false,
              ),
              icon: Icons.receipt_long_rounded,
              accentColor: context.appColors.warning.base,
              onTap: () => onOpenDrilldown(
                page: ReportPageKey.customers,
                routeName: AppRouteNames.customerReports,
                nextFilter: filter.copyWith(
                  focus: ReportFocus.customersPending,
                  onlyCanceled: false,
                ),
                sourceLabel: 'KPI Fiado aberto',
                message:
                    'A leitura de clientes abriu priorizando pendencias em aberto.',
                isFocusOnly: true,
              ),
            ),
          ],
        ),
        SizedBox(height: layout.sectionGap),
        AppSectionCard(
          title: 'Atalhos por tema',
          subtitle: 'Escolha o relatorio sem perder o periodo selecionado.',
          padding: const EdgeInsets.all(12),
          child: _ShortcutGrid(onOpenRoute: onOpenRoute),
        ),
        SizedBox(height: layout.sectionGap),
        _SalesDetailCta(
          onPressed: () => onOpenRoute(AppRouteNames.salesReports),
        ),
      ],
    );
  }
}

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({required this.onOpenRoute});

  final ValueChanged<String> onOpenRoute;

  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      _ShortcutConfig(
        title: 'Vendas',
        subtitle: 'Faturamento e itens.',
        icon: Icons.shopping_bag_outlined,
        palette: context.appColors.sales,
        routeName: AppRouteNames.salesReports,
      ),
      _ShortcutConfig(
        title: 'Caixa',
        subtitle: 'Entradas e fluxo.',
        icon: Icons.payments_outlined,
        palette: context.appColors.cashflowPositive,
        routeName: AppRouteNames.cashReports,
      ),
      _ShortcutConfig(
        title: 'Estoque',
        subtitle: 'Saude e alertas.',
        icon: Icons.inventory_2_outlined,
        palette: context.appColors.stockLow,
        routeName: AppRouteNames.inventoryReports,
      ),
      _ShortcutConfig(
        title: 'Clientes',
        subtitle: 'Ranking e fiado.',
        icon: Icons.people_alt_outlined,
        palette: context.appColors.info,
        routeName: AppRouteNames.customerReports,
      ),
      _ShortcutConfig(
        title: 'Compras',
        subtitle: 'Fornecedores e itens.',
        icon: Icons.local_shipping_outlined,
        palette: context.appColors.interactive,
        routeName: AppRouteNames.purchaseReports,
      ),
      _ShortcutConfig(
        title: 'Lucratividade',
        subtitle: 'Margem e lucro.',
        icon: Icons.show_chart_rounded,
        palette: context.appColors.success,
        routeName: AppRouteNames.profitabilityReports,
      ),
      _ShortcutConfig(
        title: 'Funcionários',
        subtitle: 'Atividade da equipe.',
        icon: Icons.groups_2_outlined,
        palette: context.appColors.info,
        routeName: AppRouteNames.employeeActivity,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 340;
        final gap = context.appLayout.gridGap;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final shortcut in shortcuts)
              SizedBox(
                width: itemWidth,
                child: ReportShortcutCard(
                  title: shortcut.title,
                  subtitle: shortcut.subtitle,
                  icon: shortcut.icon,
                  palette: shortcut.palette,
                  onTap: () => onOpenRoute(shortcut.routeName),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SalesDetailCta extends StatelessWidget {
  const _SalesDetailCta({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final layout = context.appLayout;

    return AppCard(
      borderRadius: layout.radiusLg,
      padding: EdgeInsets.all(layout.compactCardPadding),
      color: colors.sales.surface,
      borderColor: colors.sales.border,
      child: Row(
        children: [
          Icon(Icons.query_stats_rounded, color: colors.sales.base),
          SizedBox(width: layout.space4),
          Expanded(
            child: Text(
              'Ver analise detalhada de vendas',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(width: layout.space4),
          AppButton.primary(
            label: 'Abrir',
            icon: Icons.arrow_forward_rounded,
            compact: true,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _ShortcutConfig {
  const _ShortcutConfig({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.palette,
    required this.routeName,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppTonePalette palette;
  final String routeName;
}
