import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/clientes/domain/entities/client.dart';
import 'package:erp_pdv_app/modules/categorias/domain/entities/category.dart';
import 'package:erp_pdv_app/modules/fornecedores/domain/entities/supplier.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/relatorios/data/support/report_filter_preset_support.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_period.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/providers/report_providers.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/widgets/active_report_filters_bar.dart';
import 'package:erp_pdv_app/modules/relatorios/presentation/widgets/report_filter_toolbar.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('advanced filter sheet updates report provider state', (
    tester,
  ) async {
    _prepareSurface(tester);
    final container = _buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const ReportFilterToolbar(page: ReportPageKey.sales)));

    await tester.tap(find.text('Ajustar filtros'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Todas as formas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pix').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Incluir canceladas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();

    final filter = container.read(reportFilterProvider);
    expect(filter.paymentMethod, PaymentMethod.pix);
    expect(filter.includeCanceled, isTrue);
  });

  testWidgets('removing a chip clears the corresponding filter', (tester) async {
    _prepareSurface(tester);
    final container = _buildContainer(
      labels: const ReportFilterOptionLabels(),
      initialFilter: ReportFilter.fromPeriod(
        ReportPeriod.daily,
      ).copyWith(paymentMethod: PaymentMethod.pix),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(container, const ActiveReportFiltersBar(page: ReportPageKey.sales)),
    );

    expect(find.text('Forma: Pix'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(container.read(reportFilterProvider).paymentMethod, isNull);
    expect(find.text('Forma: Pix'), findsNothing);
  });

  testWidgets('clear button removes optional filters and preserves the core view', (
    tester,
  ) async {
    _prepareSurface(tester);
    final initial = ReportFilter.fromPeriod(
      ReportPeriod.weekly,
    ).copyWith(
      grouping: ReportGrouping.week,
      includeCanceled: true,
      paymentMethod: PaymentMethod.pix,
      focus: ReportFocus.cashEntries,
    );
    final container = _buildContainer(
      labels: const ReportFilterOptionLabels(),
      initialFilter: initial,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const ReportFilterToolbar(page: ReportPageKey.sales)));

    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();

    final filter = container.read(reportFilterProvider);
    expect(filter.start, initial.start);
    expect(filter.endExclusive, initial.endExclusive);
    expect(filter.grouping, ReportGrouping.week);
    expect(filter.includeCanceled, isTrue);
    expect(filter.paymentMethod, isNull);
    expect(filter.focus, isNull);
  });

  testWidgets('page presets apply the expected configuration', (tester) async {
    _prepareSurface(tester);
    final container = _buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(
        container,
        const ReportFilterToolbar(page: ReportPageKey.profitability),
      ),
    );

    await tester.tap(find.text('Por categoria'));
    await tester.pumpAndSettle();

    expect(
      container.read(reportFilterProvider).grouping,
      ReportGrouping.category,
    );
  });

  test('reset support restores the page default state', () {
    final initial = ReportFilter.fromPeriod(
      ReportPeriod.weekly,
      reference: DateTime(2026, 4, 18),
    ).copyWith(
      grouping: ReportGrouping.week,
      includeCanceled: true,
      paymentMethod: PaymentMethod.pix,
      focus: ReportFocus.salesPaymentMethods,
    );

    final reset = ReportFilterPresetSupport.resetToPageDefault(
      ReportPageKey.sales,
      reference: DateTime(2026, 4, 18),
    );

    expect(reset.start, DateTime(2026, 4, 1));
    expect(reset.endExclusive, DateTime(2026, 5, 1));
    expect(reset.grouping, ReportGrouping.day);
    expect(reset.includeCanceled, isFalse);
    expect(reset.paymentMethod, isNull);
    expect(reset.focus, isNull);
    expect(reset, isNot(initial));
  });

  testWidgets('same provider container preserves context between pages', (
    tester,
  ) async {
    _prepareSurface(tester);
    final container = _buildContainer(
      labels: const ReportFilterOptionLabels(),
      initialFilter: ReportFilter.fromPeriod(
        ReportPeriod.daily,
      ).copyWith(paymentMethod: PaymentMethod.pix),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const ReportFilterToolbar(page: ReportPageKey.sales)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(container, const ReportFilterToolbar(page: ReportPageKey.cash)));
    await tester.pumpAndSettle();

    expect(container.read(reportFilterProvider).paymentMethod, PaymentMethod.pix);
    expect(find.text('Forma: Pix'), findsOneWidget);
  });
}

ProviderContainer _buildContainer({
  ReportFilterOptionLabels labels = const ReportFilterOptionLabels(),
  ReportFilter? initialFilter,
}) {
  final container = ProviderContainer(
    overrides: [
      reportClientOptionsProvider.overrideWith((ref) async => const <Client>[]),
      reportCategoryOptionsProvider.overrideWith(
        (ref) async => const <Category>[],
      ),
      reportProductOptionsProvider.overrideWith(
        (ref) async => const <Product>[],
      ),
      reportVariantOptionsProvider.overrideWith(
        (ref) async => const <ReportVariantFilterOption>[],
      ),
      reportSupplierOptionsProvider.overrideWith(
        (ref) async => const <Supplier>[],
      ),
      reportFilterOptionLabelsProvider.overrideWith((ref) async => labels),
    ],
  );

  if (initialFilter != null) {
    container.read(reportFilterProvider.notifier).replace(initialFilter);
  }
  return container;
}

Widget _wrap(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

void _prepareSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
