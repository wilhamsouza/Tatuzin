import '../../domain/entities/report_filter.dart';

abstract interface class AnalyticsReportsRemoteDatasource {
  Future<RemoteSalesByDayReport> fetchSalesByDay({
    required ReportFilter filter,
  });

  Future<RemoteSalesByProductReport> fetchSalesByProduct({
    required ReportFilter filter,
    int limit = 10,
  });

  Future<RemoteSalesByCustomerReport> fetchSalesByCustomer({
    required ReportFilter filter,
    int limit = 20,
  });

  Future<RemoteCashConsolidatedReport> fetchCashConsolidated({
    required ReportFilter filter,
  });

  Future<RemoteFinancialSummaryReport> fetchFinancialSummary({
    required ReportFilter filter,
  });
}

class RemoteSalesByDayReport {
  const RemoteSalesByDayReport({required this.series});

  final List<RemoteSalesByDayPoint> series;
}

class RemoteSalesByDayPoint {
  const RemoteSalesByDayPoint({
    required this.date,
    required this.salesCount,
    required this.salesAmountCents,
    required this.salesCostCents,
    required this.salesProfitCents,
  });

  final DateTime date;
  final int salesCount;
  final int salesAmountCents;
  final int salesCostCents;
  final int salesProfitCents;

  factory RemoteSalesByDayPoint.fromJson(Map<String, dynamic> json) {
    return RemoteSalesByDayPoint(
      date: DateTime.parse(json['date'] as String),
      salesCount: _readInt(json, 'salesCount'),
      salesAmountCents: _readInt(json, 'salesAmountCents'),
      salesCostCents: _readInt(json, 'salesCostCents'),
      salesProfitCents: _readInt(json, 'salesProfitCents'),
    );
  }
}

class RemoteSalesByProductReport {
  const RemoteSalesByProductReport({required this.items});

  final List<RemoteSalesByProductItem> items;
}

class RemoteSalesByProductItem {
  const RemoteSalesByProductItem({
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

  factory RemoteSalesByProductItem.fromJson(Map<String, dynamic> json) {
    return RemoteSalesByProductItem(
      productKey: _readString(json, 'productKey'),
      productId: _readNullableString(json, 'productId'),
      productName: _readString(json, 'productName', fallback: 'Produto'),
      quantityMil: _readInt(json, 'quantityMil'),
      salesCount: _readInt(json, 'salesCount'),
      revenueCents: _readInt(json, 'revenueCents'),
      costCents: _readInt(json, 'costCents'),
      profitCents: _readInt(json, 'profitCents'),
    );
  }
}

class RemoteSalesByCustomerReport {
  const RemoteSalesByCustomerReport({required this.items});

  final List<RemoteSalesByCustomerItem> items;
}

class RemoteSalesByCustomerItem {
  const RemoteSalesByCustomerItem({
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

  factory RemoteSalesByCustomerItem.fromJson(Map<String, dynamic> json) {
    return RemoteSalesByCustomerItem(
      customerKey: _readString(json, 'customerKey'),
      customerId: _readNullableString(json, 'customerId'),
      customerName: _readString(json, 'customerName', fallback: 'Cliente'),
      salesCount: _readInt(json, 'salesCount'),
      revenueCents: _readInt(json, 'revenueCents'),
      costCents: _readInt(json, 'costCents'),
      profitCents: _readInt(json, 'profitCents'),
      fiadoPaymentsCents: _readInt(json, 'fiadoPaymentsCents'),
    );
  }
}

class RemoteCashConsolidatedReport {
  const RemoteCashConsolidatedReport({
    required this.totalInflowCents,
    required this.totalOutflowCents,
    required this.totalNetCents,
    required this.series,
  });

  final int totalInflowCents;
  final int totalOutflowCents;
  final int totalNetCents;
  final List<RemoteCashConsolidatedPoint> series;
}

class RemoteCashConsolidatedPoint {
  const RemoteCashConsolidatedPoint({
    required this.date,
    required this.cashInflowCents,
    required this.cashOutflowCents,
    required this.cashNetCents,
  });

  final DateTime date;
  final int cashInflowCents;
  final int cashOutflowCents;
  final int cashNetCents;

  factory RemoteCashConsolidatedPoint.fromJson(Map<String, dynamic> json) {
    return RemoteCashConsolidatedPoint(
      date: DateTime.parse(json['date'] as String),
      cashInflowCents: _readInt(json, 'cashInflowCents'),
      cashOutflowCents: _readInt(json, 'cashOutflowCents'),
      cashNetCents: _readInt(json, 'cashNetCents'),
    );
  }
}

class RemoteFinancialSummaryReport {
  const RemoteFinancialSummaryReport({
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
}

int _readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value') ?? 0;
}

String _readString(
  Map<String, dynamic> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String? _readNullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}
