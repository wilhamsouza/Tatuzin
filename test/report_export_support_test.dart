import 'package:erp_pdv_app/modules/relatorios/data/support/report_export_csv_support.dart';
import 'package:erp_pdv_app/modules/relatorios/data/support/report_export_mapper.dart';
import 'package:erp_pdv_app/modules/relatorios/data/support/report_export_pdf_support.dart';
import 'package:erp_pdv_app/modules/relatorios/data/support/report_filter_preset_support.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_overview_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_payment_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_profitability_row.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sales_trend_point.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_sold_product_summary.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_variant_summary.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Report export support', () {
    const labels = ReportFilterOptionLabels(
      categories: {10: 'Bebidas'},
      products: {1: 'Cafe Especial'},
      variants: {11: 'Cafe Especial - Preta / P'},
    );
    final salesFilter = ReportFilter(
      start: DateTime(2026, 4, 1),
      endExclusive: DateTime(2026, 5, 1),
      categoryId: 10,
      paymentMethod: PaymentMethod.pix,
      grouping: ReportGrouping.day,
    );

    test('csv export includes period, filters and visible sales data', () {
      final document = ReportExportMapper.sales(
        businessName: 'Tatuzin',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.summary,
        filter: salesFilter,
        labels: labels,
        overview: _overview(salesFilter),
        trend: _salesTrend(),
        topProducts: _topProducts(),
        topVariants: _topVariants(),
      );

      final csv = ReportExportCsvSupport().buildCsv(document);

      expect(csv, contains('Relatorio de vendas'));
      expect(csv, contains('Resumo'));
      expect(csv, contains('01/04/2026 ate 30/04/2026'));
      expect(csv, contains('Forma: Pix'));
      expect(csv, contains('Categoria: Bebidas'));
      expect(csv, contains('Cafe Especial'));
    });

    test('clearing filters changes subsequent export metadata', () {
      final filteredDocument = ReportExportMapper.sales(
        businessName: 'Tatuzin',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.summary,
        filter: salesFilter,
        labels: labels,
        overview: _overview(salesFilter),
        trend: _salesTrend(),
        topProducts: _topProducts(),
        topVariants: _topVariants(),
      );
      final clearedFilter = ReportFilterPresetSupport.clearForPage(
        ReportPageKey.sales,
        salesFilter,
      );
      final clearedDocument = ReportExportMapper.sales(
        businessName: 'Tatuzin',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.summary,
        filter: clearedFilter,
        labels: labels,
        overview: _overview(clearedFilter),
        trend: _salesTrend(),
        topProducts: _topProducts(),
        topVariants: _topVariants(),
      );

      final filteredCsv = ReportExportCsvSupport().buildCsv(filteredDocument);
      final clearedCsv = ReportExportCsvSupport().buildCsv(clearedDocument);

      expect(filteredCsv, contains('Forma: Pix'));
      expect(clearedCsv, isNot(contains('Forma: Pix')));
      expect(clearedCsv, contains('Sem filtros adicionais.'));
    });

    test('summary and detailed exports keep the same filtered context', () {
      final summaryDocument = ReportExportMapper.sales(
        businessName: 'Tatuzin',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.summary,
        filter: salesFilter,
        labels: labels,
        overview: _overview(salesFilter),
        trend: _salesTrend(),
        topProducts: _topProducts(),
        topVariants: _topVariants(),
      );
      final detailedDocument = ReportExportMapper.sales(
        businessName: 'Tatuzin',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.detailed,
        filter: salesFilter,
        labels: labels,
        overview: _overview(salesFilter),
        trend: _salesTrend(),
        topProducts: _topProducts(),
        topVariants: _topVariants(),
      );

      final summaryCsv = ReportExportCsvSupport().buildCsv(summaryDocument);
      final detailedCsv = ReportExportCsvSupport().buildCsv(detailedDocument);

      expect(summaryCsv, contains('Forma: Pix'));
      expect(detailedCsv, contains('Forma: Pix'));
      expect(summaryCsv, isNot(contains('Forma de pagamento')));
      expect(detailedCsv, contains('Forma de pagamento'));
      expect(summaryDocument.mode, ReportExportMode.summary);
      expect(detailedDocument.mode, ReportExportMode.detailed);
    });

    test('export metadata keeps the active drill-down context', () {
      final document = ReportExportMapper.sales(
        businessName: 'Tatuzin',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.summary,
        filter: salesFilter,
        labels: labels,
        overview: _overview(salesFilter),
        trend: _salesTrend(),
        topProducts: _topProducts(),
        topVariants: _topVariants(),
        navigationSummary: 'Drill-down: Vendas -> Cafe Especial',
      );

      final csv = ReportExportCsvSupport().buildCsv(document);

      expect(document.navigationSummary, 'Drill-down: Vendas -> Cafe Especial');
      expect(csv, contains('Drill-down'));
      expect(csv, contains('Cafe Especial'));
    });

    test('pdf export builds bytes with unicode font support', () async {
      final filter = ReportFilter(
        start: DateTime(2026, 4, 1),
        endExclusive: DateTime(2026, 5, 1),
        grouping: ReportGrouping.category,
      );
      final document = ReportExportMapper.profitability(
        businessName: 'Tatuzin São João',
        generatedAt: DateTime(2026, 4, 18, 10, 30),
        mode: ReportExportMode.detailed,
        filter: filter,
        labels: labels,
        rows: const [
          ReportProfitabilityRow(
            grouping: ReportGrouping.category,
            label: 'Bebidas e cafés',
            description: 'Café especial com açúcar',
            quantityMil: 5000,
            revenueCents: 45000,
            costCents: 20000,
            profitCents: 25000,
            marginBasisPoints: 5556,
            categoryId: 10,
            productId: null,
            variantId: null,
          ),
        ],
      );

      final pdfBytes = await ReportExportPdfSupport().buildPdfBytes(document);

      expect(document.periodLabel, '01/04/2026 ate 30/04/2026');
      expect(document.tables.first.rows.first.first, 'Bebidas e cafés');
      expect(document.filterSummary, contains('Agrupamento: Categoria'));
      expect(pdfBytes.length, greaterThan(1000));
      expect(String.fromCharCodes(pdfBytes), isNot(contains('Helvetica')));
    });
  });
}

ReportOverviewSummary _overview(ReportFilter filter) {
  return ReportOverviewSummary(
    filter: filter,
    grossSalesCents: 130000,
    netSalesCents: 120000,
    totalReceivedCents: 110000,
    costOfGoodsSoldCents: 60000,
    realizedProfitCents: 50000,
    salesCount: 12,
    totalDiscountCents: 5000,
    totalSurchargeCents: 2000,
    pendingFiadoCents: 18000,
    pendingFiadoCount: 3,
    cancelledSalesCount: 1,
    cancelledSalesCents: 4000,
    totalPurchasedCents: 45000,
    totalPurchasePaymentsCents: 30000,
    totalPurchasePendingCents: 15000,
    cashSalesReceivedCents: 70000,
    fiadoReceiptsCents: 15000,
    totalCreditGeneratedCents: 0,
    totalCreditUsedCents: 0,
    totalOutstandingCreditCents: 0,
    topCreditCustomers: const [],
    paymentSummaries: const [
      ReportPaymentSummary(
        paymentMethod: PaymentMethod.pix,
        receivedCents: 60000,
        operationsCount: 8,
      ),
    ],
  );
}

List<ReportSalesTrendPoint> _salesTrend() {
  return [
    ReportSalesTrendPoint(
      bucketStart: DateTime(2026, 4, 1),
      bucketEndExclusive: DateTime(2026, 4, 2),
      label: '01/04',
      salesCount: 5,
      grossSalesCents: 40000,
      netSalesCents: 38000,
    ),
  ];
}

List<ReportSoldProductSummary> _topProducts() {
  return const [
    ReportSoldProductSummary(
      productId: 1,
      productName: 'Cafe Especial',
      quantityMil: 3000,
      unitMeasure: 'un',
      soldAmountCents: 45000,
      totalCostCents: 20000,
    ),
  ];
}

List<ReportVariantSummary> _topVariants() {
  return const [
    ReportVariantSummary(
      productId: 1,
      variantId: 11,
      modelName: 'Cafe Especial',
      variantSku: 'CAF-P',
      colorLabel: 'Preta',
      sizeLabel: 'P',
      currentStockMil: 2000,
      soldQuantityMil: 3000,
      purchasedQuantityMil: 4000,
      grossRevenueCents: 45000,
    ),
  ];
}
