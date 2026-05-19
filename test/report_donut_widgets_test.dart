import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/widgets/report_donut_chart_card.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_donut_slice.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    ReportDonutChartCard card, {
    Size? surfaceSize,
  }) async {
    if (surfaceSize != null) {
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: card),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state when total is zero', (tester) async {
    await pumpCard(
      tester,
      const ReportDonutChartCard(
        title: 'Recebimentos por forma',
        slices: <ReportDonutSlice>[],
        totalLabel: 'Total',
        totalValue: 'R\$ 0,00',
        emptyTitle: 'Sem dados',
        emptyMessage: 'Nada para mostrar.',
      ),
    );

    expect(find.text('Sem dados'), findsOneWidget);
    expect(find.text('Nada para mostrar.'), findsOneWidget);
  });

  testWidgets('shows legend rows with value and percentage', (tester) async {
    await pumpCard(
      tester,
      const ReportDonutChartCard(
        title: 'Recebimentos por forma',
        slices: <ReportDonutSlice>[
          ReportDonutSlice(
            label: 'Pix',
            value: 300,
            percentage: 60,
            color: Color(0xFF166534),
            formattedValue: 'R\$ 300,00',
          ),
          ReportDonutSlice(
            label: 'Cartao',
            value: 200,
            percentage: 40,
            color: Color(0xFF7B5234),
            formattedValue: 'R\$ 200,00',
          ),
        ],
        totalLabel: 'Total',
        totalValue: 'R\$ 500,00',
        insight: 'Pix lidera os recebimentos.',
      ),
      surfaceSize: const Size(900, 1200),
    );

    expect(find.text('Pix'), findsOneWidget);
    expect(find.text('R\$ 300,00'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('Pix lidera os recebimentos.'), findsOneWidget);
  });

  testWidgets('ignores center taps on the inventory health donut', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const ReportDonutChartCard(
        title: 'Saude do estoque',
        slices: <ReportDonutSlice>[
          ReportDonutSlice(
            label: 'Saudavel',
            value: 8,
            percentage: 80,
            color: Color(0xFF166534),
            formattedValue: '8 item(ns)',
          ),
          ReportDonutSlice(
            label: 'Abaixo do minimo',
            value: 2,
            percentage: 20,
            color: Color(0xFFF59E0B),
            formattedValue: '2 item(ns)',
          ),
        ],
        totalLabel: 'Itens monitorados',
        totalValue: '10',
      ),
      surfaceSize: const Size(900, 1200),
    );

    expect(find.text('Itens monitorados'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(PieChart)));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the donut compact on wide and narrow widths', (
    tester,
  ) async {
    const card = ReportDonutChartCard(
      title: 'Saude do estoque',
      slices: <ReportDonutSlice>[
        ReportDonutSlice(
          label: 'Saudavel',
          value: 10,
          percentage: 100,
          color: Color(0xFF166534),
          formattedValue: '10 item(ns)',
        ),
      ],
      totalLabel: 'Itens monitorados',
      totalValue: '10',
    );

    await pumpCard(tester, card, surfaceSize: const Size(900, 1200));
    final wideChartSize = tester.getSize(find.byType(PieChart));
    expect(wideChartSize.width, lessThanOrEqualTo(170));
    expect(wideChartSize.height, lessThanOrEqualTo(170));
    expect(tester.takeException(), isNull);

    await pumpCard(tester, card, surfaceSize: const Size(320, 1000));
    final narrowChartSize = tester.getSize(find.byType(PieChart));
    expect(narrowChartSize.width, lessThanOrEqualTo(170));
    expect(narrowChartSize.height, lessThanOrEqualTo(170));
    expect(tester.takeException(), isNull);
  });
}
