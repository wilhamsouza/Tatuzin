import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../data/support/report_export_mapper.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../data/support/report_donut_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_donut_slice.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_payment_summary.dart';
import '../../domain/entities/report_sold_product_summary.dart';
import '../../domain/entities/report_variant_summary.dart';
import '../providers/report_providers.dart';
import '../widgets/product_sales_summary_widget.dart';
import '../widgets/report_donut_chart_card.dart';
import '../widgets/report_filter_toolbar.dart';
import '../widgets/report_kpi_grid.dart';
import '../widgets/sales_trend_chart_card.dart';
import '../widgets/variant_sales_summary_widget.dart';

class SalesReportsPage extends ConsumerWidget {
  const SalesReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final overviewAsync = ref.watch(reportOverviewProvider);
    final trendAsync = ref.watch(salesTrendProvider);
    final topProductsAsync = filter.onlyCanceled
        ? const AsyncData<List<ReportSoldProductSummary>>(
            <ReportSoldProductSummary>[],
          )
        : ref.watch(topProductsReportProvider);
    final topVariantsAsync = filter.onlyCanceled
        ? const AsyncData<List<ReportVariantSummary>>(<ReportVariantSummary>[])
        : ref.watch(topVariantsReportProvider);
    final layout = context.appLayout;
    final controller = ref.read(reportFilterProvider.notifier);

    void applyDrilldown({
      required ReportFilter nextFilter,
      required String sourceLabel,
      required String message,
      bool isFocusOnly = false,
    }) {
      controller.applyDrilldown(
        page: ReportPageKey.sales,
        nextFilter: nextFilter,
        sourcePage: ReportPageKey.sales,
        sourceLabel: sourceLabel,
        message: message,
        isFocusOnly: isFocusOnly,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Relatorio de vendas')),
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
              title: 'Vendas do periodo',
              subtitle:
                  'Faturamento, tendencia e itens que mais puxaram o resultado.',
              badgeLabel: 'Vendas',
              badgeIcon: Icons.shopping_bag_outlined,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),
            ReportFilterToolbar(
              page: ReportPageKey.sales,
              onExportPdf: (mode) => _exportPdf(ref, mode),
              onExportCsv: (mode) => _exportCsv(ref, mode),
            ),
            SizedBox(height: layout.sectionGap),
            overviewAsync.when(
              data: (overview) => ReportKpiGrid(
                items: [
                  ReportKpiItem(
                    label: 'Vendas brutas',
                    value: AppFormatters.currencyFromCents(
                      overview.grossSalesCents,
                    ),
                    caption: 'Antes de descontos e acrescimos',
                    icon: Icons.sell_outlined,
                    accentColor: context.appColors.sales.base,
                    onTap: () => applyDrilldown(
                      nextFilter: filter.copyWith(
                        clearFocus: true,
                        onlyCanceled: false,
                      ),
                      sourceLabel: 'KPI Vendas brutas',
                      message:
                          'A leitura volta para a visao geral de vendas com o mesmo periodo atual.',
                    ),
                  ),
                  ReportKpiItem(
                    label: 'Vendas liquidas',
                    value: AppFormatters.currencyFromCents(
                      overview.netSalesCents,
                    ),
                    caption: '${overview.salesCount} venda(s) ativas',
                    icon: Icons.point_of_sale_rounded,
                    accentColor: context.appColors.cashflowPositive.base,
                    onTap: () => applyDrilldown(
                      nextFilter: filter.copyWith(
                        clearFocus: true,
                        onlyCanceled: false,
                      ),
                      sourceLabel: 'KPI Vendas liquidas',
                      message:
                          'A leitura volta para a visao principal de vendas do periodo.',
                    ),
                  ),
                  ReportKpiItem(
                    label: 'Ticket medio',
                    value: AppFormatters.currencyFromCents(
                      overview.averageTicketCents,
                    ),
                    caption: 'Media por venda ativa',
                    icon: Icons.shopping_cart_checkout_rounded,
                    accentColor: context.appColors.info.base,
                    onTap: () => applyDrilldown(
                      nextFilter: filter.copyWith(
                        clearFocus: true,
                        clearProductId: true,
                        clearVariantId: true,
                        clearPaymentMethod: true,
                        onlyCanceled: false,
                      ),
                      sourceLabel: 'KPI Ticket medio',
                      message:
                          'A leitura volta para o recorte geral para comparar o ticket medio com a pagina inteira.',
                    ),
                  ),
                  ReportKpiItem(
                    label: 'Cancelamentos',
                    value: '${overview.cancelledSalesCount}',
                    caption: AppFormatters.currencyFromCents(
                      overview.cancelledSalesCents,
                    ),
                    icon: Icons.undo_rounded,
                    accentColor: context.appColors.warning.base,
                    onTap: () => applyDrilldown(
                      nextFilter: filter.copyWith(
                        includeCanceled: true,
                        onlyCanceled: true,
                        clearFocus: true,
                      ),
                      sourceLabel: 'KPI Cancelamentos',
                      message:
                          'Este atalho destaca cancelamentos sem recalcular rankings por item fora da base atual.',
                      isFocusOnly: true,
                    ),
                  ),
                  ReportKpiItem(
                    label: 'Descontos',
                    value: AppFormatters.currencyFromCents(
                      overview.totalDiscountCents,
                    ),
                    caption: 'Descontos aplicados nas vendas',
                    icon: Icons.percent_rounded,
                    accentColor: context.appColors.interactive.base,
                    onTap: () => applyDrilldown(
                      nextFilter: filter.copyWith(
                        clearFocus: true,
                        onlyCanceled: false,
                      ),
                      sourceLabel: 'KPI Descontos',
                      message:
                          'Os descontos continuam no mesmo recorte para comparacao com o restante do resultado.',
                    ),
                  ),
                ],
              ),
              loading: () => const AppStateCard(
                title: 'Carregando KPIs de vendas',
                message: 'Consolidando o resumo do periodo.',
                tone: AppStateTone.loading,
                compact: true,
              ),
              error: (error, _) => AppStateCard(
                title: 'Falha ao carregar KPIs de vendas',
                message: '$error',
                tone: AppStateTone.error,
                compact: true,
              ),
            ),
            SizedBox(height: layout.sectionGap),
            if (filter.onlyCanceled)
              const AppStateCard(
                title: 'Cancelamentos em foco',
                message:
                    'A leitura fica concentrada nos KPIs de cancelamento sem misturar rankings e tendencia de vendas ativas.',
                tone: AppStateTone.neutral,
                compact: true,
              )
            else
              trendAsync.when(
                data: (points) => SalesTrendChartCard(
                  points: points,
                  subtitle: 'Agrupado conforme o filtro atual.',
                ),
                loading: () => const AppStateCard(
                  title: 'Carregando tendencia',
                  message: 'Montando a linha de vendas do periodo.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Falha ao carregar tendencia',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                ),
              ),
            if (filter.focus == ReportFocus.salesProducts &&
                !filter.onlyCanceled) ...[
              SizedBox(height: layout.sectionGap),
              topProductsAsync.when(
                data: (products) => ProductSalesSummaryWidget(
                  soldProducts: products,
                  onProductTap: (product) {
                    if (product.productId == null) {
                      return;
                    }
                    applyDrilldown(
                      nextFilter: filter.copyWith(
                        productId: product.productId,
                        clearVariantId: true,
                        focus: ReportFocus.salesProducts,
                        onlyCanceled: false,
                      ),
                      sourceLabel: 'Produto: ${product.productName}',
                      message:
                          'A leitura foi filtrada para ${product.productName} usando a mesma base de vendas da pagina.',
                    );
                  },
                ),
                loading: () => const AppStateCard(
                  title: 'Carregando top produtos',
                  message: 'Buscando os itens com mais receita.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Falha ao carregar top produtos',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                ),
              ),
              SizedBox(height: layout.sectionGap),
              topVariantsAsync.when(
                data: (variants) => VariantSalesSummaryWidget(
                  variants: variants,
                  onVariantTap: (variant) {
                    applyDrilldown(
                      nextFilter: filter.copyWith(
                        productId: variant.productId,
                        variantId: variant.variantId,
                        focus: ReportFocus.salesProducts,
                        onlyCanceled: false,
                      ),
                      sourceLabel:
                          'Variante: ${variant.modelName} - ${variant.variantSummary}',
                      message:
                          'A leitura foi filtrada para a variante escolhida mantendo o periodo atual.',
                    );
                  },
                ),
                loading: () => const AppStateCard(
                  title: 'Carregando variantes',
                  message: 'Consolidando os detalhes por grade.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Falha ao carregar variantes',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                ),
              ),
            ],
            SizedBox(height: layout.sectionGap),
            if (!filter.onlyCanceled)
              overviewAsync.when(
                data: (overview) {
                  final paymentSlices = _buildPaymentSlices(
                    context,
                    overview.paymentSummaries,
                  );
                  return ReportDonutChartCard(
                    title: 'Vendas por forma de pagamento',
                    subtitle:
                        'Distribuicao dos recebimentos ligados as vendas. Toque na legenda para aprofundar a forma.',
                    slices: paymentSlices,
                    totalLabel: 'Total recebido',
                    totalValue: AppFormatters.currencyFromCents(
                      overview.totalReceivedCents,
                    ),
                    insight: _buildPaymentInsight(paymentSlices),
                    onSliceTap: (slice) {
                      final method = _paymentMethodFromLabel(slice.label);
                      if (method == null) {
                        return;
                      }
                      applyDrilldown(
                        nextFilter: filter.copyWith(
                          paymentMethod: method,
                          focus: ReportFocus.salesPaymentMethods,
                          onlyCanceled: false,
                        ),
                        sourceLabel: 'Forma de pagamento: ${slice.label}',
                        message:
                            'As vendas continuam no mesmo periodo, com destaque para a forma ${slice.label}.',
                        isFocusOnly: true,
                      );
                    },
                    emptyTitle: 'Sem pagamentos no periodo',
                    emptyMessage:
                        'As formas usadas nas vendas vao aparecer aqui quando houver movimento.',
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            if (filter.onlyCanceled) ...[
              SizedBox(height: layout.sectionGap),
              const AppStateCard(
                title: 'Leitura focada em cancelamentos',
                message:
                    'Os rankings por item continuam reservados para vendas ativas para preservar a semantica atual do relatorio.',
                tone: AppStateTone.neutral,
                compact: true,
              ),
            ] else if (filter.focus != ReportFocus.salesProducts) ...[
              SizedBox(height: layout.sectionGap),
              topProductsAsync.when(
                data: (products) => ProductSalesSummaryWidget(
                  soldProducts: products,
                  onProductTap: (product) {
                    if (product.productId == null) {
                      return;
                    }
                    applyDrilldown(
                      nextFilter: filter.copyWith(
                        productId: product.productId,
                        clearVariantId: true,
                        focus: ReportFocus.salesProducts,
                        onlyCanceled: false,
                      ),
                      sourceLabel: 'Produto: ${product.productName}',
                      message:
                          'A leitura foi filtrada para ${product.productName} usando a mesma base de vendas da pagina.',
                    );
                  },
                ),
                loading: () => const AppStateCard(
                  title: 'Carregando top produtos',
                  message: 'Buscando os itens com mais receita.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Falha ao carregar top produtos',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                ),
              ),
              SizedBox(height: layout.sectionGap),
              topVariantsAsync.when(
                data: (variants) => VariantSalesSummaryWidget(
                  variants: variants,
                  onVariantTap: (variant) {
                    applyDrilldown(
                      nextFilter: filter.copyWith(
                        productId: variant.productId,
                        variantId: variant.variantId,
                        focus: ReportFocus.salesProducts,
                        onlyCanceled: false,
                      ),
                      sourceLabel:
                          'Variante: ${variant.modelName} - ${variant.variantSummary}',
                      message:
                          'A leitura foi filtrada para a variante escolhida mantendo o periodo atual.',
                    );
                  },
                ),
                loading: () => const AppStateCard(
                  title: 'Carregando variantes',
                  message: 'Consolidando os detalhes por grade.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
                error: (error, _) => AppStateCard(
                  title: 'Falha ao carregar variantes',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(WidgetRef ref, ReportExportMode mode) async {
    final document = await _buildExportDocument(ref, mode);
    await ref.read(reportExportPdfSupportProvider).share(document);
  }

  Future<void> _exportCsv(WidgetRef ref, ReportExportMode mode) async {
    final document = await _buildExportDocument(ref, mode);
    await ref.read(reportExportCsvSupportProvider).share(document);
  }

  Future<ReportExportDocument> _buildExportDocument(
    WidgetRef ref,
    ReportExportMode mode,
  ) async {
    final businessName = ref.read(currentCompanyContextProvider).displayName;
    final filter = ref.read(reportFilterProvider);
    final labels = await ref.read(reportFilterOptionLabelsProvider.future);
    final overview = await ref.read(reportOverviewProvider.future);
    final trend = await ref.read(salesTrendProvider.future);
    final topProducts = filter.onlyCanceled
        ? const <ReportSoldProductSummary>[]
        : await ref.read(topProductsReportProvider.future);
    final topVariants = filter.onlyCanceled
        ? const <ReportVariantSummary>[]
        : await ref.read(topVariantsReportProvider.future);

    return ReportExportMapper.sales(
      businessName: businessName,
      generatedAt: DateTime.now(),
      mode: mode,
      filter: filter,
      labels: labels,
      overview: overview,
      trend: trend,
      topProducts: topProducts,
      topVariants: topVariants,
      navigationSummary: ref
          .read(reportPageSessionProvider)
          .drilldownFor(ReportPageKey.sales)
          ?.exportLabel,
    );
  }

  List<ReportDonutSlice> _buildPaymentSlices(
    BuildContext context,
    List<ReportPaymentSummary> summaries,
  ) {
    final colors = context.appColors;
    return ReportDonutSupport.normalize(
      summaries.map(
        (summary) => ReportDonutSlice(
          label: summary.paymentMethod.label,
          value: summary.receivedCents.toDouble(),
          percentage: 0,
          color: _paymentColor(summary.paymentMethod, colors),
          formattedValue: '',
        ),
      ),
      formatValue: (value) => AppFormatters.currencyFromCents(value.round()),
      groupedColor: colors.disabled.base,
    );
  }

  String? _buildPaymentInsight(List<ReportDonutSlice> slices) {
    return ReportDonutSupport.buildPrimaryInsight(
      slices,
      builder: (leader) {
        if (leader.label == PaymentMethod.pix.label &&
            leader.percentage >= 50) {
          return 'Pix ja representa a maior parte das vendas recebidas.';
        }
        if (leader.percentage >= 50) {
          return '${leader.label} concentra a maior parte das vendas recebidas.';
        }
        return '${leader.label} lidera as entradas de vendas no periodo.';
      },
    );
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
}
