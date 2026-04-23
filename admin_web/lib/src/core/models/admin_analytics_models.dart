class AdminManagementScopeQuery {
  const AdminManagementScopeQuery({
    required this.companyId,
    required this.startDate,
    required this.endDate,
    this.topN = 10,
    this.force = false,
  });

  final String companyId;
  final String startDate;
  final String endDate;
  final int topN;
  final bool force;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'companyId': companyId,
      'startDate': startDate,
      'endDate': endDate,
      'topN': '$topN',
      if (force) 'force': 'true',
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminManagementScopeQuery &&
        other.companyId == companyId &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.topN == topN &&
        other.force == force;
  }

  @override
  int get hashCode => Object.hash(companyId, startDate, endDate, topN, force);
}

class AdminAnalyticsCompanyRef {
  const AdminAnalyticsCompanyRef({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;

  factory AdminAnalyticsCompanyRef.fromMap(Map<String, dynamic> map) {
    return AdminAnalyticsCompanyRef(
      id: _readString(map, 'id'),
      name: _readString(map, 'name'),
      slug: _readString(map, 'slug'),
    );
  }
}

class AdminAnalyticsPeriod {
  const AdminAnalyticsPeriod({
    required this.startDate,
    required this.endDate,
    required this.dayCount,
  });

  final String startDate;
  final String endDate;
  final int dayCount;

  factory AdminAnalyticsPeriod.fromMap(Map<String, dynamic> map) {
    return AdminAnalyticsPeriod(
      startDate: _readString(map, 'startDate'),
      endDate: _readString(map, 'endDate'),
      dayCount: _readOptionalInt(map, 'dayCount') ?? 0,
    );
  }
}

class AdminAnalyticsCoverage {
  const AdminAnalyticsCoverage({
    required this.companyDailyRows,
    required this.productDailyRows,
    required this.customerDailyRows,
  });

  final int companyDailyRows;
  final int productDailyRows;
  final int customerDailyRows;

  factory AdminAnalyticsCoverage.fromMap(Map<String, dynamic> map) {
    return AdminAnalyticsCoverage(
      companyDailyRows: _readOptionalInt(map, 'companyDailyRows') ?? 0,
      productDailyRows: _readOptionalInt(map, 'productDailyRows') ?? 0,
      customerDailyRows: _readOptionalInt(map, 'customerDailyRows') ?? 0,
    );
  }
}

class AdminAnalyticsMaterialization {
  const AdminAnalyticsMaterialization({
    required this.materializedAt,
    required this.coverage,
  });

  final DateTime? materializedAt;
  final AdminAnalyticsCoverage coverage;

  factory AdminAnalyticsMaterialization.fromMap(Map<String, dynamic> map) {
    return AdminAnalyticsMaterialization(
      materializedAt: _readOptionalDateTime(map, 'materializedAt'),
      coverage: AdminAnalyticsCoverage.fromMap(
        _readMap(map, 'coverage', fallback: const <String, dynamic>{}),
      ),
    );
  }
}

class AdminManagementDashboardHeadline {
  const AdminManagementDashboardHeadline({
    required this.salesAmountCents,
    required this.salesProfitCents,
    required this.cashNetCents,
    required this.purchasesAmountCents,
    required this.fiadoPaymentsAmountCents,
    required this.salesCount,
    required this.identifiedCustomersCount,
    required this.averageTicketCents,
  });

  final int salesAmountCents;
  final int salesProfitCents;
  final int cashNetCents;
  final int purchasesAmountCents;
  final int fiadoPaymentsAmountCents;
  final int salesCount;
  final int identifiedCustomersCount;
  final int averageTicketCents;

  factory AdminManagementDashboardHeadline.fromMap(Map<String, dynamic> map) {
    return AdminManagementDashboardHeadline(
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesProfitCents: _readOptionalInt(map, 'salesProfitCents') ?? 0,
      cashNetCents: _readOptionalInt(map, 'cashNetCents') ?? 0,
      purchasesAmountCents: _readOptionalInt(map, 'purchasesAmountCents') ?? 0,
      fiadoPaymentsAmountCents:
          _readOptionalInt(map, 'fiadoPaymentsAmountCents') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      identifiedCustomersCount:
          _readOptionalInt(map, 'identifiedCustomersCount') ?? 0,
      averageTicketCents: _readOptionalInt(map, 'averageTicketCents') ?? 0,
    );
  }
}

class AdminDashboardSalesSeriesPoint {
  const AdminDashboardSalesSeriesPoint({
    required this.date,
    required this.salesCount,
    required this.salesAmountCents,
    required this.salesProfitCents,
    required this.cashNetCents,
  });

  final String date;
  final int salesCount;
  final int salesAmountCents;
  final int salesProfitCents;
  final int cashNetCents;

  factory AdminDashboardSalesSeriesPoint.fromMap(Map<String, dynamic> map) {
    return AdminDashboardSalesSeriesPoint(
      date: _readString(map, 'date'),
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesProfitCents: _readOptionalInt(map, 'salesProfitCents') ?? 0,
      cashNetCents: _readOptionalInt(map, 'cashNetCents') ?? 0,
    );
  }
}

class AdminTopProductReportItem {
  const AdminTopProductReportItem({
    required this.productKey,
    required this.productId,
    required this.productName,
    required this.quantityMil,
    required this.salesCount,
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
  });

  final String productKey;
  final String? productId;
  final String productName;
  final int quantityMil;
  final int salesCount;
  final int revenueCents;
  final int costCents;
  final int profitCents;

  factory AdminTopProductReportItem.fromMap(Map<String, dynamic> map) {
    return AdminTopProductReportItem(
      productKey: _readString(map, 'productKey'),
      productId: _readOptionalString(map, 'productId'),
      productName: _readString(map, 'productName'),
      quantityMil: _readOptionalInt(map, 'quantityMil') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      revenueCents: _readOptionalInt(map, 'revenueCents') ?? 0,
      costCents: _readOptionalInt(map, 'costCents') ?? 0,
      profitCents: _readOptionalInt(map, 'profitCents') ?? 0,
    );
  }
}

class AdminTopCustomerReportItem {
  const AdminTopCustomerReportItem({
    required this.customerKey,
    required this.customerId,
    required this.customerName,
    required this.salesCount,
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
    required this.fiadoPaymentsCents,
  });

  final String customerKey;
  final String? customerId;
  final String customerName;
  final int salesCount;
  final int revenueCents;
  final int costCents;
  final int profitCents;
  final int fiadoPaymentsCents;

  factory AdminTopCustomerReportItem.fromMap(Map<String, dynamic> map) {
    return AdminTopCustomerReportItem(
      customerKey: _readString(map, 'customerKey'),
      customerId: _readOptionalString(map, 'customerId'),
      customerName: _readString(map, 'customerName'),
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      revenueCents: _readOptionalInt(map, 'revenueCents') ?? 0,
      costCents: _readOptionalInt(map, 'costCents') ?? 0,
      profitCents: _readOptionalInt(map, 'profitCents') ?? 0,
      fiadoPaymentsCents: _readOptionalInt(map, 'fiadoPaymentsCents') ?? 0,
    );
  }
}

class AdminManagementDashboardSnapshot {
  const AdminManagementDashboardSnapshot({
    required this.company,
    required this.period,
    required this.materialization,
    required this.headline,
    required this.salesSeries,
    required this.topProducts,
    required this.topCustomers,
  });

  final AdminAnalyticsCompanyRef company;
  final AdminAnalyticsPeriod period;
  final AdminAnalyticsMaterialization materialization;
  final AdminManagementDashboardHeadline headline;
  final List<AdminDashboardSalesSeriesPoint> salesSeries;
  final List<AdminTopProductReportItem> topProducts;
  final List<AdminTopCustomerReportItem> topCustomers;

  factory AdminManagementDashboardSnapshot.fromMap(Map<String, dynamic> map) {
    return AdminManagementDashboardSnapshot(
      company: AdminAnalyticsCompanyRef.fromMap(_readMap(map, 'company')),
      period: AdminAnalyticsPeriod.fromMap(_readMap(map, 'period')),
      materialization: AdminAnalyticsMaterialization.fromMap(
        _readMap(map, 'materialization'),
      ),
      headline: AdminManagementDashboardHeadline.fromMap(
        _readMap(map, 'headline'),
      ),
      salesSeries: _readList(
        map,
        'salesSeries',
      ).map(AdminDashboardSalesSeriesPoint.fromMap).toList(),
      topProducts: _readList(
        map,
        'topProducts',
      ).map(AdminTopProductReportItem.fromMap).toList(),
      topCustomers: _readList(
        map,
        'topCustomers',
      ).map(AdminTopCustomerReportItem.fromMap).toList(),
    );
  }
}

class AdminSalesByDayTotals {
  const AdminSalesByDayTotals({
    required this.salesCount,
    required this.salesAmountCents,
    required this.salesProfitCents,
  });

  final int salesCount;
  final int salesAmountCents;
  final int salesProfitCents;

  factory AdminSalesByDayTotals.fromMap(Map<String, dynamic> map) {
    return AdminSalesByDayTotals(
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesProfitCents: _readOptionalInt(map, 'salesProfitCents') ?? 0,
    );
  }
}

class AdminSalesByDaySeriesPoint {
  const AdminSalesByDaySeriesPoint({
    required this.date,
    required this.salesCount,
    required this.salesAmountCents,
    required this.salesCostCents,
    required this.salesProfitCents,
  });

  final String date;
  final int salesCount;
  final int salesAmountCents;
  final int salesCostCents;
  final int salesProfitCents;

  factory AdminSalesByDaySeriesPoint.fromMap(Map<String, dynamic> map) {
    return AdminSalesByDaySeriesPoint(
      date: _readString(map, 'date'),
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesCostCents: _readOptionalInt(map, 'salesCostCents') ?? 0,
      salesProfitCents: _readOptionalInt(map, 'salesProfitCents') ?? 0,
    );
  }
}

class AdminSalesByDayReport {
  const AdminSalesByDayReport({
    required this.company,
    required this.period,
    required this.materialization,
    required this.totals,
    required this.series,
  });

  final AdminAnalyticsCompanyRef company;
  final AdminAnalyticsPeriod period;
  final AdminAnalyticsMaterialization materialization;
  final AdminSalesByDayTotals totals;
  final List<AdminSalesByDaySeriesPoint> series;

  factory AdminSalesByDayReport.fromMap(Map<String, dynamic> map) {
    return AdminSalesByDayReport(
      company: AdminAnalyticsCompanyRef.fromMap(_readMap(map, 'company')),
      period: AdminAnalyticsPeriod.fromMap(_readMap(map, 'period')),
      materialization: AdminAnalyticsMaterialization.fromMap(
        _readMap(map, 'materialization'),
      ),
      totals: AdminSalesByDayTotals.fromMap(_readMap(map, 'totals')),
      series: _readList(
        map,
        'series',
      ).map(AdminSalesByDaySeriesPoint.fromMap).toList(),
    );
  }
}

class AdminSalesByProductTotals {
  const AdminSalesByProductTotals({
    required this.quantityMil,
    required this.salesCount,
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
  });

  final int quantityMil;
  final int salesCount;
  final int revenueCents;
  final int costCents;
  final int profitCents;

  factory AdminSalesByProductTotals.fromMap(Map<String, dynamic> map) {
    return AdminSalesByProductTotals(
      quantityMil: _readOptionalInt(map, 'quantityMil') ?? 0,
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      revenueCents: _readOptionalInt(map, 'revenueCents') ?? 0,
      costCents: _readOptionalInt(map, 'costCents') ?? 0,
      profitCents: _readOptionalInt(map, 'profitCents') ?? 0,
    );
  }
}

class AdminSalesByProductReport {
  const AdminSalesByProductReport({
    required this.company,
    required this.period,
    required this.materialization,
    required this.totals,
    required this.items,
  });

  final AdminAnalyticsCompanyRef company;
  final AdminAnalyticsPeriod period;
  final AdminAnalyticsMaterialization materialization;
  final AdminSalesByProductTotals totals;
  final List<AdminTopProductReportItem> items;

  factory AdminSalesByProductReport.fromMap(Map<String, dynamic> map) {
    return AdminSalesByProductReport(
      company: AdminAnalyticsCompanyRef.fromMap(_readMap(map, 'company')),
      period: AdminAnalyticsPeriod.fromMap(_readMap(map, 'period')),
      materialization: AdminAnalyticsMaterialization.fromMap(
        _readMap(map, 'materialization'),
      ),
      totals: AdminSalesByProductTotals.fromMap(_readMap(map, 'totals')),
      items: _readList(
        map,
        'items',
      ).map(AdminTopProductReportItem.fromMap).toList(),
    );
  }
}

class AdminSalesByCustomerTotals {
  const AdminSalesByCustomerTotals({
    required this.salesCount,
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
    required this.fiadoPaymentsCents,
  });

  final int salesCount;
  final int revenueCents;
  final int costCents;
  final int profitCents;
  final int fiadoPaymentsCents;

  factory AdminSalesByCustomerTotals.fromMap(Map<String, dynamic> map) {
    return AdminSalesByCustomerTotals(
      salesCount: _readOptionalInt(map, 'salesCount') ?? 0,
      revenueCents: _readOptionalInt(map, 'revenueCents') ?? 0,
      costCents: _readOptionalInt(map, 'costCents') ?? 0,
      profitCents: _readOptionalInt(map, 'profitCents') ?? 0,
      fiadoPaymentsCents: _readOptionalInt(map, 'fiadoPaymentsCents') ?? 0,
    );
  }
}

class AdminSalesByCustomerReport {
  const AdminSalesByCustomerReport({
    required this.company,
    required this.period,
    required this.materialization,
    required this.totals,
    required this.items,
  });

  final AdminAnalyticsCompanyRef company;
  final AdminAnalyticsPeriod period;
  final AdminAnalyticsMaterialization materialization;
  final AdminSalesByCustomerTotals totals;
  final List<AdminTopCustomerReportItem> items;

  factory AdminSalesByCustomerReport.fromMap(Map<String, dynamic> map) {
    return AdminSalesByCustomerReport(
      company: AdminAnalyticsCompanyRef.fromMap(_readMap(map, 'company')),
      period: AdminAnalyticsPeriod.fromMap(_readMap(map, 'period')),
      materialization: AdminAnalyticsMaterialization.fromMap(
        _readMap(map, 'materialization'),
      ),
      totals: AdminSalesByCustomerTotals.fromMap(_readMap(map, 'totals')),
      items: _readList(
        map,
        'items',
      ).map(AdminTopCustomerReportItem.fromMap).toList(),
    );
  }
}

class AdminCashConsolidatedTotals {
  const AdminCashConsolidatedTotals({
    required this.cashInflowCents,
    required this.cashOutflowCents,
    required this.cashNetCents,
  });

  final int cashInflowCents;
  final int cashOutflowCents;
  final int cashNetCents;

  factory AdminCashConsolidatedTotals.fromMap(Map<String, dynamic> map) {
    return AdminCashConsolidatedTotals(
      cashInflowCents: _readOptionalInt(map, 'cashInflowCents') ?? 0,
      cashOutflowCents: _readOptionalInt(map, 'cashOutflowCents') ?? 0,
      cashNetCents: _readOptionalInt(map, 'cashNetCents') ?? 0,
    );
  }
}

class AdminCashConsolidatedSeriesPoint {
  const AdminCashConsolidatedSeriesPoint({
    required this.date,
    required this.cashInflowCents,
    required this.cashOutflowCents,
    required this.cashNetCents,
  });

  final String date;
  final int cashInflowCents;
  final int cashOutflowCents;
  final int cashNetCents;

  factory AdminCashConsolidatedSeriesPoint.fromMap(Map<String, dynamic> map) {
    return AdminCashConsolidatedSeriesPoint(
      date: _readString(map, 'date'),
      cashInflowCents: _readOptionalInt(map, 'cashInflowCents') ?? 0,
      cashOutflowCents: _readOptionalInt(map, 'cashOutflowCents') ?? 0,
      cashNetCents: _readOptionalInt(map, 'cashNetCents') ?? 0,
    );
  }
}

class AdminCashConsolidatedReport {
  const AdminCashConsolidatedReport({
    required this.company,
    required this.period,
    required this.materialization,
    required this.totals,
    required this.series,
  });

  final AdminAnalyticsCompanyRef company;
  final AdminAnalyticsPeriod period;
  final AdminAnalyticsMaterialization materialization;
  final AdminCashConsolidatedTotals totals;
  final List<AdminCashConsolidatedSeriesPoint> series;

  factory AdminCashConsolidatedReport.fromMap(Map<String, dynamic> map) {
    return AdminCashConsolidatedReport(
      company: AdminAnalyticsCompanyRef.fromMap(_readMap(map, 'company')),
      period: AdminAnalyticsPeriod.fromMap(_readMap(map, 'period')),
      materialization: AdminAnalyticsMaterialization.fromMap(
        _readMap(map, 'materialization'),
      ),
      totals: AdminCashConsolidatedTotals.fromMap(_readMap(map, 'totals')),
      series: _readList(
        map,
        'series',
      ).map(AdminCashConsolidatedSeriesPoint.fromMap).toList(),
    );
  }
}

class AdminFinancialSummaryValue {
  const AdminFinancialSummaryValue({
    required this.salesAmountCents,
    required this.salesCostCents,
    required this.salesProfitCents,
    required this.purchasesAmountCents,
    required this.fiadoPaymentsAmountCents,
    required this.cashNetCents,
    required this.financialAdjustmentsCents,
    required this.operatingMarginBasisPoints,
  });

  final int salesAmountCents;
  final int salesCostCents;
  final int salesProfitCents;
  final int purchasesAmountCents;
  final int fiadoPaymentsAmountCents;
  final int cashNetCents;
  final int financialAdjustmentsCents;
  final int operatingMarginBasisPoints;

  factory AdminFinancialSummaryValue.fromMap(Map<String, dynamic> map) {
    return AdminFinancialSummaryValue(
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesCostCents: _readOptionalInt(map, 'salesCostCents') ?? 0,
      salesProfitCents: _readOptionalInt(map, 'salesProfitCents') ?? 0,
      purchasesAmountCents: _readOptionalInt(map, 'purchasesAmountCents') ?? 0,
      fiadoPaymentsAmountCents:
          _readOptionalInt(map, 'fiadoPaymentsAmountCents') ?? 0,
      cashNetCents: _readOptionalInt(map, 'cashNetCents') ?? 0,
      financialAdjustmentsCents:
          _readOptionalInt(map, 'financialAdjustmentsCents') ?? 0,
      operatingMarginBasisPoints:
          _readOptionalInt(map, 'operatingMarginBasisPoints') ?? 0,
    );
  }
}

class AdminFinancialSummarySeriesPoint {
  const AdminFinancialSummarySeriesPoint({
    required this.date,
    required this.salesAmountCents,
    required this.salesProfitCents,
    required this.purchasesAmountCents,
    required this.fiadoPaymentsAmountCents,
    required this.cashNetCents,
    required this.financialAdjustmentsCents,
  });

  final String date;
  final int salesAmountCents;
  final int salesProfitCents;
  final int purchasesAmountCents;
  final int fiadoPaymentsAmountCents;
  final int cashNetCents;
  final int financialAdjustmentsCents;

  factory AdminFinancialSummarySeriesPoint.fromMap(Map<String, dynamic> map) {
    return AdminFinancialSummarySeriesPoint(
      date: _readString(map, 'date'),
      salesAmountCents: _readOptionalInt(map, 'salesAmountCents') ?? 0,
      salesProfitCents: _readOptionalInt(map, 'salesProfitCents') ?? 0,
      purchasesAmountCents: _readOptionalInt(map, 'purchasesAmountCents') ?? 0,
      fiadoPaymentsAmountCents:
          _readOptionalInt(map, 'fiadoPaymentsAmountCents') ?? 0,
      cashNetCents: _readOptionalInt(map, 'cashNetCents') ?? 0,
      financialAdjustmentsCents:
          _readOptionalInt(map, 'financialAdjustmentsCents') ?? 0,
    );
  }
}

class AdminFinancialSummaryReport {
  const AdminFinancialSummaryReport({
    required this.company,
    required this.period,
    required this.materialization,
    required this.summary,
    required this.series,
  });

  final AdminAnalyticsCompanyRef company;
  final AdminAnalyticsPeriod period;
  final AdminAnalyticsMaterialization materialization;
  final AdminFinancialSummaryValue summary;
  final List<AdminFinancialSummarySeriesPoint> series;

  factory AdminFinancialSummaryReport.fromMap(Map<String, dynamic> map) {
    return AdminFinancialSummaryReport(
      company: AdminAnalyticsCompanyRef.fromMap(_readMap(map, 'company')),
      period: AdminAnalyticsPeriod.fromMap(_readMap(map, 'period')),
      materialization: AdminAnalyticsMaterialization.fromMap(
        _readMap(map, 'materialization'),
      ),
      summary: AdminFinancialSummaryValue.fromMap(_readMap(map, 'summary')),
      series: _readList(
        map,
        'series',
      ).map(AdminFinancialSummarySeriesPoint.fromMap).toList(),
    );
  }
}

class AdminManagementReportsBundle {
  const AdminManagementReportsBundle({
    required this.salesByDay,
    required this.salesByProduct,
    required this.salesByCustomer,
    required this.cashConsolidated,
    required this.financialSummary,
  });

  final AdminSalesByDayReport salesByDay;
  final AdminSalesByProductReport salesByProduct;
  final AdminSalesByCustomerReport salesByCustomer;
  final AdminCashConsolidatedReport cashConsolidated;
  final AdminFinancialSummaryReport financialSummary;
}

Map<String, dynamic> _readMap(
  Map<String, dynamic> map,
  String key, {
  Map<String, dynamic>? fallback,
}) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (fallback != null) {
    return fallback;
  }
  throw FormatException('Campo "$key" ausente no payload de analytics.');
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

String _readString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('Campo "$key" ausente no payload de analytics.');
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

int? _readOptionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}
