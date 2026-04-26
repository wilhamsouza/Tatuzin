import '../../data/support/report_filter_preset_support.dart';

enum ReportDataSourceStrategy {
  pdvOperationalLocalFirst,
  erpManagementServerFirst,
  crmManagementServerFirst,
  systemSupport,
}

extension ReportDataSourceStrategyX on ReportDataSourceStrategy {
  String get label {
    switch (this) {
      case ReportDataSourceStrategy.pdvOperationalLocalFirst:
        return 'PDV operacional local-first';
      case ReportDataSourceStrategy.erpManagementServerFirst:
        return 'ERP gerencial server-first';
      case ReportDataSourceStrategy.crmManagementServerFirst:
        return 'CRM gerencial server-first';
      case ReportDataSourceStrategy.systemSupport:
        return 'Sistema/suporte';
    }
  }
}

ReportDataSourceStrategy reportStrategyForPage(ReportPageKey page) {
  switch (page) {
    case ReportPageKey.customers:
      return ReportDataSourceStrategy.crmManagementServerFirst;
    case ReportPageKey.overview:
    case ReportPageKey.sales:
    case ReportPageKey.inventory:
    case ReportPageKey.purchases:
    case ReportPageKey.profitability:
      return ReportDataSourceStrategy.erpManagementServerFirst;
    case ReportPageKey.cash:
      return ReportDataSourceStrategy.pdvOperationalLocalFirst;
  }
}
