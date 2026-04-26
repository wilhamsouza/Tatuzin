import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../data/support/report_donut_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_donut_slice.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_inventory_health_summary.dart';
import '../../domain/entities/report_payment_summary.dart';
import '../providers/report_providers.dart';
import '../widgets/report_data_origin_banner.dart';
import '../widgets/product_sales_summary_widget.dart';
import '../widgets/report_comparison_card.dart';
import '../widgets/report_donut_chart_card.dart';
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
    final topProductsAsync = ref.watch(topProductsReportProvider);
    final inventoryAsync = ref.watch(inventoryHealthReportProvider);
    final layout = context.appLayout;
    final controller = ref.read(reportFilterProvider.notifier);

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
      context.pushNamed(routeName);
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
            const AppPageHeader(
              title: 'Hub executivo',
              subtitle:
                  'KPIs do periodo, atalhos por tema e leitura rapida para decidir o proximo passo.',
              badgeLabel: 'Relatorios',
              badgeIcon: Icons.insights_rounded,
              emphasized: true,
            ),
            const ReportFilterToolbar(page: ReportPageKey.overview),
            const ReportDataOriginBanner(page: ReportPageKey.overview),
            SizedBox(height: layout.sectionGap),
            overviewAsync.when(
              data: (overview) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReportKpiGrid(
                    items: [
                      ReportKpiItem(
                        label: 'Vendas liquidas',
                        value: AppFormatters.currencyFromCents(
                          overview.netSalesCents,
                        ),
                        caption: '${overview.salesCount} venda(s) no periodo',
                        icon: Icons.point_of_sale_rounded,
                        accentColor: context.appColors.sales.base,
                        onTap: () => openDrilldown(
                          page: ReportPageKey.sales,
                          routeName: AppRouteNames.salesReports,
                          nextFilter: filter.copyWith(
                            onlyCanceled: false,
                            clearFocus: true,
                          ),
                          sourceLabel: 'KPI Vendas liquidas',
                          message:
                              'A pagina de vendas abriu com o mesmo periodo do hub para aprofundar faturamento, tendencia e itens vendidos.',
                        ),
                      ),
                      ReportKpiItem(
                        label: 'Total recebido',
                        value: AppFormatters.currencyFromCents(
                          overview.totalReceivedCents,
                        ),
                        caption: 'Entradas liquidas do caixa',
                        icon: Icons.account_balance_wallet_rounded,
                        accentColor: context.appColors.cashflowPositive.base,
                        onTap: () => openDrilldown(
                          page: ReportPageKey.cash,
                          routeName: AppRouteNames.cashReports,
                          nextFilter: filter.copyWith(
                            focus: ReportFocus.cashEntries,
                            clearPaymentMethod: true,
                            onlyCanceled: false,
                          ),
                          sourceLabel: 'KPI Total recebido',
                          message:
                              'O relatorio de caixa abriu com foco nas entradas do periodo, sem trocar a base do caixa real.',
                          isFocusOnly: true,
                        ),
                      ),
                      ReportKpiItem(
                        label: 'Lucro realizado',
                        value: AppFormatters.currencyFromCents(
                          overview.realizedProfitCents,
                        ),
                        caption: 'Lucro reconhecido no periodo',
                        icon: Icons.trending_up_rounded,
                        accentColor: context.appColors.success.base,
                        onTap: () => openDrilldown(
                          page: ReportPageKey.profitability,
                          routeName: AppRouteNames.profitabilityReports,
                          nextFilter: filter.copyWith(
                            grouping: ReportGrouping.product,
                            focus: ReportFocus.profitabilityTop,
                            onlyCanceled: false,
                          ),
                          sourceLabel: 'KPI Lucro realizado',
                          message:
                              'A lucratividade abriu destacando os itens com maior lucro dentro da mesma semantica atual de receita, custo e margem.',
                          isFocusOnly: true,
                        ),
                      ),
                      ReportKpiItem(
                        label: 'Fiado pendente',
                        value: AppFormatters.currencyFromCents(
                          overview.pendingFiadoCents,
                        ),
                        caption:
                            '${overview.pendingFiadoCount} nota(s) em aberto',
                        icon: Icons.receipt_long_rounded,
                        accentColor: context.appColors.warning.base,
                        onTap: () => openDrilldown(
                          page: ReportPageKey.customers,
                          routeName: AppRouteNames.customerReports,
                          nextFilter: filter.copyWith(
                            focus: ReportFocus.customersPending,
                            onlyCanceled: false,
                          ),
                          sourceLabel: 'KPI Fiado pendente',
                          message:
                              'A leitura de clientes abriu priorizando pendencias em aberto para facilitar cobranca e acompanhamento.',
                          isFocusOnly: true,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: layout.sectionGap),
                  previousOverviewAsync.when(
                    data: (previous) => ReportComparisonCard(
                      title: 'Comparacao com o periodo anterior',
                      subtitle: 'Leitura rapida de vendas liquidas.',
                      currentValue: AppFormatters.currencyFromCents(
                        overview.netSalesCents,
                      ),
                      previousValue: AppFormatters.currencyFromCents(
                        previous.netSalesCents,
                      ),
                      deltaLabel: _buildDeltaLabel(
                        overview.netSalesCents - previous.netSalesCents,
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  SizedBox(height: layout.sectionGap),
                  AppSectionCard(
                    title: 'Atalhos por tema',
                    subtitle:
                        'Abra o relatorio certo sem perder o contexto do periodo.',
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 320,
                          child: ReportShortcutCard(
                            title: 'Vendas',
                            subtitle:
                                'Faturamento, tendencia e itens vendidos.',
                            icon: Icons.shopping_bag_outlined,
                            palette: context.appColors.sales,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.salesReports),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: ReportShortcutCard(
                            title: 'Caixa',
                            subtitle: 'Entradas, saidas e fluxo do caixa real.',
                            icon: Icons.payments_outlined,
                            palette: context.appColors.cashflowPositive,
                            onTap: () =>
                                context.pushNamed(AppRouteNames.cashReports),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: ReportShortcutCard(
                            title: 'Estoque',
                            subtitle: 'Saude, itens criticos e movimentacoes.',
                            icon: Icons.inventory_2_outlined,
                            palette: context.appColors.stockLow,
                            onTap: () => context.pushNamed(
                              AppRouteNames.inventoryReports,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: ReportShortcutCard(
                            title: 'Clientes',
                            subtitle: 'Ranking, fiado aberto e haver.',
                            icon: Icons.people_alt_outlined,
                            palette: context.appColors.info,
                            onTap: () => context.pushNamed(
                              AppRouteNames.customerReports,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: ReportShortcutCard(
                            title: 'Compras',
                            subtitle: 'Fornecedores, reposicao e pendencias.',
                            icon: Icons.local_shipping_outlined,
                            palette: context.appColors.interactive,
                            onTap: () => context.pushNamed(
                              AppRouteNames.purchaseReports,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: ReportShortcutCard(
                            title: 'Lucratividade',
                            subtitle: 'Receita, custo, lucro e margem.',
                            icon: Icons.show_chart_rounded,
                            palette: context.appColors.success,
                            onTap: () => context.pushNamed(
                              AppRouteNames.profitabilityReports,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: layout.sectionGap),
                  Wrap(
                    spacing: layout.space8,
                    runSpacing: layout.space8,
                    children: [
                      SizedBox(
                        width: 520,
                        child: ReportDonutChartCard(
                          title: 'Recebimentos por forma',
                          subtitle: 'Como o dinheiro entrou no periodo.',
                          slices: _buildPaymentSlices(
                            context,
                            overview.paymentSummaries,
                          ),
                          totalLabel: 'Total recebido',
                          totalValue: AppFormatters.currencyFromCents(
                            overview.totalReceivedCents,
                          ),
                          insight: _buildPaymentInsight(
                            _buildPaymentSlices(
                              context,
                              overview.paymentSummaries,
                            ),
                          ),
                          onSliceTap: (slice) {
                            final method = _paymentMethodFromLabel(slice.label);
                            if (method == null) {
                              return;
                            }
                            openDrilldown(
                              page: ReportPageKey.sales,
                              routeName: AppRouteNames.salesReports,
                              nextFilter: filter.copyWith(
                                paymentMethod: method,
                                focus: ReportFocus.salesPaymentMethods,
                                onlyCanceled: false,
                              ),
                              sourceLabel:
                                  'Recebimentos por forma: ${slice.label}',
                              message:
                                  'A pagina de vendas abriu com a forma ${slice.label} em destaque para aprofundar o recebimento ligado as vendas.',
                              isFocusOnly: true,
                            );
                          },
                          emptyTitle: 'Sem recebimentos',
                          emptyMessage:
                              'As formas de pagamento vao aparecer aqui quando houver movimento.',
                        ),
                      ),
                      SizedBox(
                        width: 520,
                        child: inventoryAsync.when(
                          data: (summary) {
                            final slices = _buildInventoryHealthSlices(
                              context,
                              summary,
                            );
                            return ReportDonutChartCard(
                              title: 'Saude do estoque',
                              subtitle:
                                  'Panorama rapido entre itens saudaveis e em alerta.',
                              slices: slices,
                              totalLabel: 'Itens monitorados',
                              totalValue: '${summary.totalItemsCount}',
                              insight: _buildInventoryInsight(summary),
                              onSliceTap: (slice) {
                                final nextFocus = _inventoryFocusFromSlice(
                                  slice.label,
                                );
                                openDrilldown(
                                  page: ReportPageKey.inventory,
                                  routeName: AppRouteNames.inventoryReports,
                                  nextFilter: nextFocus == null
                                      ? filter.copyWith(
                                          clearFocus: true,
                                          onlyCanceled: false,
                                        )
                                      : filter.copyWith(
                                          focus: nextFocus,
                                          onlyCanceled: false,
                                        ),
                                  sourceLabel:
                                      'Saude do estoque: ${slice.label}',
                                  message:
                                      'O relatorio de estoque abriu priorizando ${slice.label.toLowerCase()} para facilitar a proxima acao.',
                                  isFocusOnly: true,
                                );
                              },
                              emptyTitle: 'Sem estoque monitorado',
                              emptyMessage:
                                  'Os indicadores de estoque vao aparecer aqui quando houver itens cadastrados.',
                            );
                          },
                          loading: () => const AppStateCard(
                            title: 'Carregando saude do estoque',
                            message: 'Consolidando os alertas do periodo.',
                            tone: AppStateTone.loading,
                            compact: true,
                          ),
                          error: (error, _) => AppStateCard(
                            title: 'Falha ao carregar saude do estoque',
                            message: '$error',
                            tone: AppStateTone.error,
                            compact: true,
                            actionLabel: 'Tentar novamente',
                            onAction: () => ref
                                .read(appDataRefreshProvider.notifier)
                                .state++,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: layout.sectionGap),
                  topProductsAsync.when(
                    data: (products) => ProductSalesSummaryWidget(
                      soldProducts: products,
                      onProductTap: (product) {
                        if (product.productId == null) {
                          return;
                        }
                        openDrilldown(
                          page: ReportPageKey.sales,
                          routeName: AppRouteNames.salesReports,
                          nextFilter: filter.copyWith(
                            productId: product.productId,
                            clearVariantId: true,
                            focus: ReportFocus.salesProducts,
                            onlyCanceled: false,
                          ),
                          sourceLabel: 'Top produto: ${product.productName}',
                          message:
                              'A pagina de vendas abriu filtrada para ${product.productName}, mantendo o mesmo periodo do hub.',
                        );
                      },
                    ),
                    loading: () => const AppStateCard(
                      title: 'Carregando top produtos',
                      message: 'Consolidando os itens com mais receita.',
                      tone: AppStateTone.loading,
                      compact: true,
                    ),
                    error: (error, _) => AppStateCard(
                      title: 'Falha ao carregar top produtos',
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

  String _buildDeltaLabel(int deltaCents) {
    final signal = deltaCents > 0 ? '+' : '';
    return '$signal${AppFormatters.currencyFromCents(deltaCents)}';
  }

  List<ReportDonutSlice> _buildPaymentSlices(
    BuildContext context,
    List<ReportPaymentSummary> summaries,
  ) {
    final colors = context.appColors;
    final rawSlices = summaries.map(
      (summary) => ReportDonutSlice(
        label: summary.paymentMethod.label,
        value: summary.receivedCents.toDouble(),
        percentage: 0,
        color: _paymentColor(summary.paymentMethod, colors),
        formattedValue: '',
      ),
    );

    return ReportDonutSupport.normalize(
      rawSlices,
      formatValue: (value) => AppFormatters.currencyFromCents(value.round()),
      groupedColor: colors.disabled.base,
    );
  }

  List<ReportDonutSlice> _buildInventoryHealthSlices(
    BuildContext context,
    ReportInventoryHealthSummary summary,
  ) {
    final colors = context.appColors;
    final rawSlices = <ReportDonutSlice>[
      ReportDonutSlice(
        label: 'Saudavel',
        value: summary.healthyItemsCount.toDouble(),
        percentage: 0,
        color: colors.cashflowPositive.base,
        formattedValue: '',
      ),
      ReportDonutSlice(
        label: 'Abaixo do minimo',
        value: summary.belowMinimumOnlyItemsCount.toDouble(),
        percentage: 0,
        color: colors.stockLow.base,
        formattedValue: '',
      ),
      ReportDonutSlice(
        label: 'Zerado',
        value: summary.zeroedItemsCount.toDouble(),
        percentage: 0,
        color: colors.cashflowNegative.base,
        formattedValue: '',
      ),
    ];

    return ReportDonutSupport.normalize(
      rawSlices,
      formatValue: (value) => '${value.round()} item(ns)',
      groupedColor: colors.disabled.base,
    );
  }

  String? _buildPaymentInsight(List<ReportDonutSlice> slices) {
    return ReportDonutSupport.buildPrimaryInsight(
      slices,
      builder: (leader) {
        if (leader.label == PaymentMethod.pix.label &&
            leader.percentage >= 50) {
          return 'Pix ja representa a maior parte dos recebimentos.';
        }
        if (leader.percentage >= 50) {
          return '${leader.label} concentra a maior parte dos recebimentos.';
        }
        return '${leader.label} lidera os recebimentos do periodo.';
      },
    );
  }

  String _buildInventoryInsight(ReportInventoryHealthSummary summary) {
    if (summary.totalItemsCount <= 0) {
      return 'Ainda nao ha itens suficientes para medir a saude do estoque.';
    }

    final alertCount = summary.alertItemsCount;
    if (alertCount <= 0) {
      return 'O estoque monitorado esta saudavel neste momento.';
    }

    final alertPercentage = ReportDonutSupport.formatPercentage(
      ReportDonutSupport.percentageFromValue(
        alertCount.toDouble(),
        summary.totalItemsCount.toDouble(),
      ),
    );
    if (summary.divergenceItemsCount > 0) {
      return '$alertPercentage do estoque esta em alerta e ainda ha divergencias para revisar.';
    }
    return '$alertPercentage do estoque esta em alerta.';
  }

  Color _paymentColor(PaymentMethod paymentMethod, AppColorTokens colors) {
    switch (paymentMethod) {
      case PaymentMethod.cash:
        return colors.sales.base;
      case PaymentMethod.pix:
        return colors.cashflowPositive.base;
      case PaymentMethod.card:
        return colors.info.base;
      case PaymentMethod.fiado:
        return colors.warning.base;
    }
  }

  PaymentMethod? _paymentMethodFromLabel(String label) {
    for (final method in PaymentMethod.values) {
      if (method.label == label) {
        return method;
      }
    }
    return null;
  }

  ReportFocus? _inventoryFocusFromSlice(String label) {
    switch (label) {
      case 'Zerado':
        return ReportFocus.inventoryZeroed;
      case 'Abaixo do minimo':
        return ReportFocus.inventoryCritical;
      case 'Saudavel':
        return null;
      default:
        return ReportFocus.inventoryAlerts;
    }
  }
}
