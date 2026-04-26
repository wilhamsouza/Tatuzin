import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../domain/entities/report_filter.dart';
import '../datasources/analytics_reports_remote_datasource.dart';

class RealAnalyticsReportsRemoteDatasource
    implements AnalyticsReportsRemoteDatasource {
  const RealAnalyticsReportsRemoteDatasource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
    required AppOperationalContext operationalContext,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage,
       _operationalContext = operationalContext;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;
  final AppOperationalContext _operationalContext;

  @override
  Future<RemoteCashConsolidatedReport> fetchCashConsolidated({
    required ReportFilter filter,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/cash-consolidated',
      options: await _authorizedOptions(filter: filter),
    );
    final totals = _readMap(response.data, 'totals');
    return RemoteCashConsolidatedReport(
      totalInflowCents: _readInt(totals, 'cashInflowCents'),
      totalOutflowCents: _readInt(totals, 'cashOutflowCents'),
      totalNetCents: _readInt(totals, 'cashNetCents'),
      series: _readList(
        response.data,
        'series',
      ).map(RemoteCashConsolidatedPoint.fromJson).toList(growable: false),
    );
  }

  @override
  Future<RemoteFinancialSummaryReport> fetchFinancialSummary({
    required ReportFilter filter,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/financial-summary',
      options: await _authorizedOptions(filter: filter),
    );
    final summary = _readMap(response.data, 'summary');
    return RemoteFinancialSummaryReport(
      salesAmountCents: _readInt(summary, 'salesAmountCents'),
      salesCostCents: _readInt(summary, 'salesCostCents'),
      salesProfitCents: _readInt(summary, 'salesProfitCents'),
      purchasesAmountCents: _readInt(summary, 'purchasesAmountCents'),
      fiadoPaymentsAmountCents: _readInt(summary, 'fiadoPaymentsAmountCents'),
      cashNetCents: _readInt(summary, 'cashNetCents'),
      financialAdjustmentsCents: _readInt(summary, 'financialAdjustmentsCents'),
      operatingMarginBasisPoints: _readInt(
        summary,
        'operatingMarginBasisPoints',
      ),
    );
  }

  @override
  Future<RemoteSalesByCustomerReport> fetchSalesByCustomer({
    required ReportFilter filter,
    int limit = 20,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/sales-by-customer',
      options: await _authorizedOptions(filter: filter, topN: limit),
    );
    return RemoteSalesByCustomerReport(
      items: _readList(
        response.data,
        'items',
      ).map(RemoteSalesByCustomerItem.fromJson).toList(growable: false),
    );
  }

  @override
  Future<RemoteSalesByDayReport> fetchSalesByDay({
    required ReportFilter filter,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/sales-by-day',
      options: await _authorizedOptions(filter: filter),
    );
    return RemoteSalesByDayReport(
      series: _readList(
        response.data,
        'series',
      ).map(RemoteSalesByDayPoint.fromJson).toList(growable: false),
    );
  }

  @override
  Future<RemoteSalesByProductReport> fetchSalesByProduct({
    required ReportFilter filter,
    int limit = 10,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/sales-by-product',
      options: await _authorizedOptions(filter: filter, topN: limit),
    );
    return RemoteSalesByProductReport(
      items: _readList(
        response.data,
        'items',
      ).map(RemoteSalesByProductItem.fromJson).toList(growable: false),
    );
  }

  Future<ApiRequestOptions> _authorizedOptions({
    required ReportFilter filter,
    int? topN,
  }) async {
    if (!_operationalContext.environment.dataMode.allowsRemoteRead ||
        !_operationalContext.hasRemoteSession) {
      throw const AuthenticationException(
        'Faca login remoto para carregar analytics gerenciais.',
      );
    }
    final companyId = _operationalContext.currentRemoteCompanyId?.trim();
    if (companyId == null || companyId.isEmpty) {
      throw const AuthenticationException(
        'Sessao remota sem empresa para analytics gerenciais.',
      );
    }
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para carregar analytics gerenciais.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: <String, Object?>{
        'companyId': companyId,
        'startDate': _formatDate(filter.start),
        'endDate': _formatDate(
          filter.endExclusive.subtract(const Duration(days: 1)),
        ),
        if (topN != null) 'topN': topN,
      },
      timeout: const Duration(seconds: 15),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _readMap(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
    throw NetworkRequestException(
      'A API de analytics nao retornou "$key" em formato valido.',
    );
  }

  List<Map<String, dynamic>> _readList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List) {
      return value.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    throw NetworkRequestException(
      'A API de analytics nao retornou "$key" em formato valido.',
    );
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
}
