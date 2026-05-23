import 'package:tatuzin/app/core/widgets/app_metric_card.dart';
import 'package:tatuzin/app/theme/app_theme.dart';
import 'package:tatuzin/modules/relatorios/data/support/report_filter_preset_support.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_filter.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_period.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_sold_product_summary.dart';
import 'package:tatuzin/modules/relatorios/presentation/providers/report_providers.dart';
import 'package:tatuzin/modules/relatorios/presentation/support/report_kpi_delta_support.dart';
import 'package:tatuzin/modules/relatorios/presentation/widgets/product_sales_summary_widget.dart';
import 'package:tatuzin/modules/relatorios/presentation/widgets/report_drilldown_banner.dart';
import 'package:tatuzin/modules/relatorios/presentation/widgets/report_kpi_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('product ranking renders rank, quantity, amount and progress', (
    tester,
  ) async {
    _prepareSurface(tester, const Size(390, 760));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ProductSalesSummaryWidget(
              soldProducts: [
                ReportSoldProductSummary(
                  productId: 1,
                  productName: 'Cafe Especial',
                  quantityMil: 3000,
                  unitMeasure: 'un',
                  soldAmountCents: 45000,
                  totalCostCents: 20000,
                ),
                ReportSoldProductSummary(
                  productId: 2,
                  productName: 'Bolo de pote chocolate',
                  quantityMil: 1000,
                  unitMeasure: 'un',
                  soldAmountCents: 15000,
                  totalCostCents: 8000,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Top produtos'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Cafe Especial'), findsOneWidget);
    expect(find.text('3 un vendidos'), findsOneWidget);
    expect(find.text('R\$ 450,00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('product_ranking_progress_1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty product ranking shows friendly state', (tester) async {
    _prepareSurface(tester, const Size(360, 720));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ProductSalesSummaryWidget(soldProducts: []),
          ),
        ),
      ),
    );

    expect(find.text('Ainda não há vendas neste período.'), findsOneWidget);
    expect(
      find.text('Tente alterar o período ou limpar os filtros.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('drill-down banner is compact and clear keeps other filters', (
    tester,
  ) async {
    _prepareSurface(tester, const Size(360, 720));
    final baseFilter = ReportFilter.fromPeriod(
      ReportPeriod.monthly,
      reference: DateTime(2026, 4, 18),
    ).copyWith(categoryId: 7);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(reportFilterProvider.notifier).replace(baseFilter);
    container
        .read(reportFilterProvider.notifier)
        .applyDrilldown(
          page: ReportPageKey.sales,
          nextFilter: baseFilter.copyWith(productId: 1),
          sourcePage: ReportPageKey.overview,
          sourceLabel: 'Produto: Cafe Especial',
          message: 'Recorte de produto no período atual.',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: ReportDrilldownBanner(page: ReportPageKey.sales),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Drill:'), findsOneWidget);
    expect(find.text('Limpar'), findsOneWidget);

    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();

    expect(container.read(reportFilterProvider).productId, isNull);
    expect(container.read(reportFilterProvider).categoryId, 7);
    expect(find.textContaining('Drill:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delta stays safe when previous period is zero', (tester) async {
    _prepareSurface(tester, const Size(360, 760));
    final delta = ReportKpiDeltaSupport.money(
      currentCents: 12000,
      previousCents: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ReportKpiGrid(
              items: [
                ReportKpiItem(
                  label: 'Vendas brutas',
                  value: 'R\$ 120,00',
                  caption: '1 venda no período',
                  icon: Icons.sell_outlined,
                  delta: delta,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppMetricCard), findsOneWidget);
    expect(find.text('+R\$ 120,00 vs período anterior'), findsOneWidget);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'product ranking is readable at 360px without horizontal overflow',
    (tester) async {
      _prepareSurface(tester, const Size(360, 720));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: ProductSalesSummaryWidget(
                  soldProducts: [
                    ReportSoldProductSummary(
                      productId: 1,
                      productName:
                          'Produto artesanal com nome grande para teste mobile',
                      quantityMil: 12500,
                      unitMeasure: 'un',
                      soldAmountCents: 1234567,
                      totalCostCents: 500000,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('R\$ 12.345,67'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _prepareSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
