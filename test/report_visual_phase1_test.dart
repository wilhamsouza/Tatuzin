import 'package:tatuzin/app/core/widgets/app_metric_card.dart';
import 'package:tatuzin/app/theme/app_theme.dart';
import 'package:tatuzin/modules/relatorios/data/support/report_export_mapper.dart';
import 'package:tatuzin/modules/relatorios/data/support/report_filter_preset_support.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_filter.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_period.dart';
import 'package:tatuzin/modules/relatorios/domain/entities/report_sales_trend_point.dart';
import 'package:tatuzin/modules/relatorios/presentation/providers/report_providers.dart';
import 'package:tatuzin/modules/relatorios/presentation/widgets/report_filter_toolbar.dart';
import 'package:tatuzin/modules/relatorios/presentation/widgets/report_kpi_grid.dart';
import 'package:tatuzin/modules/relatorios/presentation/widgets/sales_trend_chart_card.dart';
import 'package:tatuzin/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact toolbar renders period and export action', (
    tester,
  ) async {
    _prepareSurface(tester, const Size(360, 720));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(reportFilterProvider.notifier)
        .replace(
          ReportFilter.fromPeriod(
            ReportPeriod.monthly,
            reference: DateTime(2026, 4, 18),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ReportFilterToolbar(
              page: ReportPageKey.sales,
              onExportPdf: (ReportExportMode mode) async {},
              onExportCsv: (ReportExportMode mode) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Mensal'), findsOneWidget);
    expect(find.byTooltip('Ajustar filtros'), findsOneWidget);
    expect(find.byTooltip('Exportar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact toolbar shows active filter count chip', (tester) async {
    _prepareSurface(tester, const Size(360, 720));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(reportFilterProvider.notifier)
        .replace(
          ReportFilter.fromPeriod(
            ReportPeriod.monthly,
            reference: DateTime(2026, 4, 18),
          ).copyWith(paymentMethod: PaymentMethod.pix),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ReportFilterToolbar(
              page: ReportPageKey.sales,
              onExportPdf: (ReportExportMode mode) async {},
              onExportCsv: (ReportExportMode mode) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('1 filtro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KPI grid uses one readable column at 360px', (tester) async {
    _prepareSurface(tester, const Size(360, 760));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ReportKpiGrid(
              items: [
                ReportKpiItem(
                  label: 'Vendas liquidas',
                  value: 'R\$ 123.456,78',
                  caption: '12 venda(s) no periodo',
                  icon: Icons.point_of_sale_rounded,
                ),
                ReportKpiItem(
                  label: 'Ticket medio',
                  value: 'R\$ 10.288,06',
                  caption: 'Media por venda ativa',
                  icon: Icons.shopping_cart_checkout_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final cards = find.byType(AppMetricCard);
    expect(cards, findsNWidgets(2));
    expect(tester.getSize(cards.first).width, greaterThan(300));
    expect(
      tester.getTopLeft(cards.at(0)).dx,
      tester.getTopLeft(cards.at(1)).dx,
    );
    expect(
      tester.getTopLeft(cards.at(1)).dy,
      greaterThan(tester.getTopLeft(cards.at(0)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sales trend chart keeps the visual plot compact', (
    tester,
  ) async {
    _prepareSurface(tester, const Size(390, 760));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SalesTrendChartCard(
              points: [
                ReportSalesTrendPoint(
                  bucketStart: DateTime(2026, 4, 1),
                  bucketEndExclusive: DateTime(2026, 4, 2),
                  label: '01/04',
                  salesCount: 2,
                  grossSalesCents: 25000,
                  netSalesCents: 22000,
                ),
                ReportSalesTrendPoint(
                  bucketStart: DateTime(2026, 4, 2),
                  bucketEndExclusive: DateTime(2026, 4, 3),
                  label: '02/04',
                  salesCount: 4,
                  grossSalesCents: 42000,
                  netSalesCents: 40000,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final chartArea = tester.getSize(
      find.byKey(const ValueKey('sales_trend_chart_area')),
    );
    expect(chartArea.height, lessThanOrEqualTo(72));
    expect(tester.takeException(), isNull);
  });
}

void _prepareSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
