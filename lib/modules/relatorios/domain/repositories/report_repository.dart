import '../entities/report_cashflow_summary.dart';
import '../entities/report_customer_ranking_row.dart';
import '../entities/report_filter.dart';
import '../entities/report_inventory_health_summary.dart';
import '../entities/report_overview_summary.dart';
import '../entities/report_period.dart';
import '../entities/report_profitability_row.dart';
import '../entities/report_purchase_summary.dart';
import '../entities/report_sales_trend_point.dart';
import '../entities/report_sold_product_summary.dart';
import '../entities/report_summary.dart';
import '../entities/report_variant_summary.dart';

abstract class ReportRepository {
  Future<ReportSummary> fetchSummary({
    required ReportPeriod period,
    ReportFilter? filter,
  });

  Future<ReportOverviewSummary> fetchOverview({required ReportFilter filter});

  Future<List<ReportSalesTrendPoint>> fetchSalesTrend({
    required ReportFilter filter,
  });

  Future<List<ReportSoldProductSummary>> fetchTopProducts({
    required ReportFilter filter,
    int limit = 10,
  });

  Future<List<ReportVariantSummary>> fetchTopVariants({
    required ReportFilter filter,
    int limit = 10,
  });

  Future<List<ReportProfitabilityRow>> fetchProfitability({
    required ReportFilter filter,
    int limit = 20,
  });

  Future<ReportCashflowSummary> fetchCashflow({required ReportFilter filter});

  Future<ReportInventoryHealthSummary> fetchInventoryHealth({
    required ReportFilter filter,
  });

  Future<List<ReportCustomerRankingRow>> fetchCustomerRanking({
    required ReportFilter filter,
    int limit = 20,
  });

  Future<ReportPurchaseSummary> fetchPurchaseSummary({
    required ReportFilter filter,
    int limit = 20,
  });
}
