import '../../data/support/report_filter_preset_support.dart';

enum ReportDataOriginScope {
  overview,
  sales,
  cash,
  inventory,
  customers,
  purchases,
  profitability,
}

class ReportDataOriginNotice {
  const ReportDataOriginNotice({
    required this.scope,
    required this.title,
    required this.message,
  });

  final ReportDataOriginScope scope;
  final String title;
  final String message;
}

class ReportResult<T> {
  const ReportResult({required this.data, this.notice});

  final T data;
  final ReportDataOriginNotice? notice;
}

ReportDataOriginScope reportDataOriginScopeForPage(ReportPageKey page) {
  switch (page) {
    case ReportPageKey.overview:
      return ReportDataOriginScope.overview;
    case ReportPageKey.sales:
      return ReportDataOriginScope.sales;
    case ReportPageKey.cash:
      return ReportDataOriginScope.cash;
    case ReportPageKey.inventory:
      return ReportDataOriginScope.inventory;
    case ReportPageKey.customers:
      return ReportDataOriginScope.customers;
    case ReportPageKey.purchases:
      return ReportDataOriginScope.purchases;
    case ReportPageKey.profitability:
      return ReportDataOriginScope.profitability;
  }
}
