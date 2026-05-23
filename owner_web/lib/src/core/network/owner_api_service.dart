import '../auth/owner_auth_storage.dart';
import '../auth/owner_debug_log.dart';
import '../models/owner_models.dart';
import 'owner_api_client.dart';

class OwnerInvoicesQuery {
  const OwnerInvoicesQuery({this.page = 1, this.pageSize = 20, this.status});

  final int page;
  final int pageSize;
  final String? status;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (status != null && status!.trim().isNotEmpty) 'status': status!.trim(),
    };
  }
}

class OwnerSalesSummaryQuery {
  const OwnerSalesSummaryQuery({
    this.startDate,
    this.endDate,
    this.groupBy = 'day',
    this.page = 1,
    this.pageSize = 20,
    this.limit = 10,
  });

  final String? startDate;
  final String? endDate;
  final String groupBy;
  final int page;
  final int pageSize;
  final int limit;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (startDate != null && startDate!.trim().isNotEmpty)
        'startDate': startDate!.trim(),
      if (endDate != null && endDate!.trim().isNotEmpty)
        'endDate': endDate!.trim(),
      'groupBy': groupBy,
      'page': '$page',
      'pageSize': '$pageSize',
      'limit': '$limit',
    };
  }
}

class OwnerDateReportQuery {
  const OwnerDateReportQuery({this.startDate, this.endDate, this.limit = 10});

  final String? startDate;
  final String? endDate;
  final int limit;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (startDate != null && startDate!.trim().isNotEmpty)
        'startDate': startDate!.trim(),
      if (endDate != null && endDate!.trim().isNotEmpty)
        'endDate': endDate!.trim(),
      'limit': '$limit',
    };
  }
}

class OwnerStockSummaryQuery {
  const OwnerStockSummaryQuery({
    this.page = 1,
    this.pageSize = 20,
    this.limit = 10,
  });

  final int page;
  final int pageSize;
  final int limit;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      'limit': '$limit',
    };
  }
}

class OwnerCrmSummaryQuery {
  const OwnerCrmSummaryQuery({this.limit = 10});

  final int limit;

  Map<String, String> toQueryParameters() {
    return <String, String>{'limit': '$limit'};
  }
}

class OwnerCrmCustomersQuery {
  const OwnerCrmCustomersQuery({
    this.search,
    this.status = 'all',
    this.page = 1,
    this.pageSize = 20,
  });

  final String? search;
  final String status;
  final int page;
  final int pageSize;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
      'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    };
  }
}

class OwnerReceivablesQuery {
  const OwnerReceivablesQuery({
    this.status = 'open',
    this.page = 1,
    this.pageSize = 20,
  });

  final String status;
  final int page;
  final int pageSize;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    };
  }
}

class OwnerEmployeesReportQuery extends OwnerDateReportQuery {
  const OwnerEmployeesReportQuery({
    super.startDate,
    super.endDate,
    super.limit = 10,
  });
}

class OwnerCashSessionsQuery {
  const OwnerCashSessionsQuery({
    this.startDate,
    this.endDate,
    this.status = 'all',
    this.search,
    this.employeeId,
    this.page = 1,
    this.pageSize = 20,
  });

  final String? startDate;
  final String? endDate;
  final String status;
  final String? search;
  final String? employeeId;
  final int page;
  final int pageSize;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (startDate != null && startDate!.trim().isNotEmpty)
        'startDate': startDate!.trim(),
      if (endDate != null && endDate!.trim().isNotEmpty)
        'endDate': endDate!.trim(),
      if (employeeId != null && employeeId!.trim().isNotEmpty)
        'employeeId': employeeId!.trim(),
      if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
      'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    };
  }
}

class OwnerApiService {
  const OwnerApiService({
    required OwnerApiClient apiClient,
    required OwnerAuthStorage authStorage,
  }) : _apiClient = apiClient,
       _authStorage = authStorage;

  final OwnerApiClient _apiClient;
  final OwnerAuthStorage _authStorage;

  Future<OwnerSession> login({
    required String email,
    required String password,
  }) async {
    final clientContext = await _authStorage.ensureClientContext();
    ownerDebugLog('auth.service.login.request', {
      'email': email.trim(),
      'clientType': clientContext.clientType,
      'hasClientInstanceId': clientContext.clientInstanceId.isNotEmpty,
    });
    final response = await _apiClient.postJson(
      '/auth/login',
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        ...clientContext.toApiPayload(),
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a sessao no formato esperado.',
      );
    }
    final session = OwnerSession.fromLoginResponse(response);
    ownerDebugLog('auth.service.login.response', {
      'userEmail': session.user.email,
      'companyId': session.company.id,
      'membershipRole': session.membership.role,
      'hasAccessToken': session.accessToken.trim().isNotEmpty,
      'hasRefreshToken': session.refreshToken?.trim().isNotEmpty == true,
    });
    return session;
  }

  Future<OwnerSession> restoreSession(String accessToken) async {
    ownerDebugLog('auth.service.restore.request', {
      'hasAccessToken': accessToken.trim().isNotEmpty,
    });
    final response = await _apiClient.getJson(
      '/auth/me',
      accessToken: accessToken,
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'Nao foi possivel restaurar a sessao.',
      );
    }
    return OwnerSession.fromIdentityResponse(
      response,
      accessToken: accessToken,
    );
  }

  Future<void> logout(String accessToken) async {
    await _apiClient.postJson('/auth/logout', accessToken: accessToken);
  }

  Future<void> validateOwnerAccess(String accessToken) async {
    await getCompany(accessToken: accessToken);
  }

  Future<OwnerCompanySummary> getCompany({String? accessToken}) async {
    final response = await _apiClient.getJson(
      '/owner/company',
      accessToken: accessToken ?? await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a empresa no formato esperado.',
      );
    }
    return OwnerCompanySummary.fromMap(response);
  }

  Future<OwnerDashboard> getDashboard() async {
    final response = await _apiClient.getJson(
      '/owner/dashboard',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o dashboard no formato esperado.',
      );
    }
    return OwnerDashboard.fromMap(response);
  }

  Future<OwnerBusinessDashboard> getBusinessDashboard() async {
    final response = await _apiClient.getJson(
      '/owner/dashboard/business',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message:
            'A API nao retornou o dashboard gerencial no formato esperado.',
      );
    }
    return OwnerBusinessDashboard.fromMap(response);
  }

  Future<OwnerSalesSummary> getSalesSummary({
    OwnerSalesSummaryQuery query = const OwnerSalesSummaryQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/reports/sales-summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou as vendas no formato esperado.',
      );
    }
    return OwnerSalesSummary.fromMap(response);
  }

  Future<OwnerProductsReport> getProductsReport({
    OwnerDateReportQuery query = const OwnerDateReportQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/reports/products',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou produtos no formato esperado.',
      );
    }
    return OwnerProductsReport.fromMap(response);
  }

  Future<OwnerStockSummary> getStockSummary({
    OwnerStockSummaryQuery query = const OwnerStockSummaryQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/stock/summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou estoque no formato esperado.',
      );
    }
    return OwnerStockSummary.fromMap(response);
  }

  Future<OwnerCrmSummary> getCrmSummary({
    OwnerCrmSummaryQuery query = const OwnerCrmSummaryQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/crm/summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou CRM no formato esperado.',
      );
    }
    return OwnerCrmSummary.fromMap(response);
  }

  Future<OwnerCrmCustomerPage> getCrmCustomers({
    OwnerCrmCustomersQuery query = const OwnerCrmCustomersQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/crm/customers',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou clientes no formato esperado.',
      );
    }
    return OwnerCrmCustomerPage.fromMap(response);
  }

  Future<OwnerCrmCustomerDetail> getCrmCustomer(String id) async {
    final response = await _apiClient.getJson(
      '/owner/crm/customers/${Uri.encodeComponent(id)}',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o cliente no formato esperado.',
      );
    }
    return OwnerCrmCustomerDetail.fromMap(response);
  }

  Future<OwnerReceivablesReport> getReceivables({
    OwnerReceivablesQuery query = const OwnerReceivablesQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/financial/receivables',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou contas a receber no formato esperado.',
      );
    }
    return OwnerReceivablesReport.fromMap(response);
  }

  Future<OwnerEmployeeReports> getEmployeeReports({
    OwnerEmployeesReportQuery query = const OwnerEmployeesReportQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/reports/employees',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou funcionarios no formato esperado.',
      );
    }
    return OwnerEmployeeReports.fromMap(response);
  }

  Future<OwnerCommissionsSummary> getCommissions({
    OwnerDateReportQuery query = const OwnerDateReportQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/commissions',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou comissoes no formato esperado.',
      );
    }
    return OwnerCommissionsSummary.fromMap(response);
  }

  Future<OwnerReportsCatalog> getReportsCatalog() async {
    final response = await _apiClient.getJson(
      '/owner/reports/catalog',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o catalogo no formato esperado.',
      );
    }
    return OwnerReportsCatalog.fromMap(response);
  }

  Future<OwnerCashSessionsReport> getCashSessions({
    OwnerCashSessionsQuery query = const OwnerCashSessionsQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/reports/cash-sessions',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou os caixas no formato esperado.',
      );
    }
    return OwnerCashSessionsReport.fromMap(response);
  }

  Future<OwnerCashSessionDetail> getCashSessionDetail(String id) async {
    final response = await _apiClient.getJson(
      '/owner/reports/cash-sessions/${Uri.encodeComponent(id)}',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o caixa no formato esperado.',
      );
    }
    return OwnerCashSessionDetail.fromMap(response);
  }

  Future<Map<String, dynamic>> registerSaleReturn({
    required String cashSessionId,
    required String saleId,
    required Map<String, dynamic> body,
  }) async {
    return _writeMap(
      '/owner/reports/cash-sessions/${Uri.encodeComponent(cashSessionId)}/sales/${Uri.encodeComponent(saleId)}/return',
      body,
    );
  }

  Future<Map<String, dynamic>> cancelCashSessionSale({
    required String cashSessionId,
    required String saleId,
    required String reason,
  }) async {
    return _writeMap(
      '/owner/reports/cash-sessions/${Uri.encodeComponent(cashSessionId)}/sales/${Uri.encodeComponent(saleId)}/cancel',
      <String, dynamic>{'reason': reason},
    );
  }

  Future<OwnerBillingStatus> getBillingStatus() async {
    final response = await _apiClient.getJson(
      '/owner/billing/status',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a assinatura no formato esperado.',
      );
    }
    return OwnerBillingStatus.fromMap(response);
  }

  Future<OwnerInvoicesPage> getBillingInvoices({
    OwnerInvoicesQuery query = const OwnerInvoicesQuery(),
  }) async {
    final response = await _apiClient.getJson(
      '/owner/billing/invoices',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou as cobrancas no formato esperado.',
      );
    }
    return OwnerInvoicesPage.fromMap(response);
  }

  Future<OwnerEmployeesOverview> getEmployees() async {
    final response = await _apiClient.getJson(
      '/owner/employees',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou funcionarios no formato esperado.',
      );
    }
    return OwnerEmployeesOverview.fromMap(response);
  }

  Future<OwnerEmployeeMutationResult> createEmployee({
    required Map<String, dynamic> body,
  }) async {
    final response = await _apiClient.postJson(
      '/owner/employees',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o funcionario no formato esperado.',
      );
    }
    return OwnerEmployeeMutationResult.fromMap(response);
  }

  Future<OwnerEmployeeMutationResult> updateEmployee({
    required String employeeId,
    required Map<String, dynamic> body,
  }) async {
    final response = await _apiClient.patchJson(
      '/owner/employees/${Uri.encodeComponent(employeeId)}',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o funcionario no formato esperado.',
      );
    }
    return OwnerEmployeeMutationResult.fromMap(response);
  }

  Future<OwnerEmployeeMutationResult> setEmployeeEnabled({
    required String employeeId,
    required bool enabled,
  }) async {
    final response = await _apiClient.postJson(
      '/owner/employees/${Uri.encodeComponent(employeeId)}/${enabled ? 'enable' : 'disable'}',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o funcionario no formato esperado.',
      );
    }
    return OwnerEmployeeMutationResult.fromMap(response);
  }

  Future<OwnerTemporaryPasswordResult> generateTemporaryPassword({
    required String employeeId,
  }) async {
    final response = await _apiClient.postJson(
      '/owner/employees/${Uri.encodeComponent(employeeId)}/access/temporary-password',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a senha temporaria no formato esperado.',
      );
    }
    return OwnerTemporaryPasswordResult.fromMap(response);
  }

  Future<OwnerCommissionSettings> updateCommissionSettings({
    required String employeeId,
    required Map<String, dynamic> body,
  }) async {
    final response = await _apiClient.patchJson(
      '/owner/employees/${Uri.encodeComponent(employeeId)}/commission-settings',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a comissao no formato esperado.',
      );
    }
    return OwnerCommissionSettings.fromMap(
      response['settings'] is Map<String, dynamic>
          ? response['settings'] as Map<String, dynamic>
          : const <String, dynamic>{},
    );
  }

  Future<OwnerReceiptSettings> getReceiptSettings() async {
    final response = await _apiClient.getJson(
      '/owner/receipt-settings',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o comprovante no formato esperado.',
      );
    }
    return OwnerReceiptSettings.fromMap(response);
  }

  Future<OwnerReceiptSettings> updateReceiptSettings({
    required Map<String, dynamic> body,
  }) async {
    final response = await _apiClient.patchJson(
      '/owner/receipt-settings',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou o comprovante no formato esperado.',
      );
    }
    return OwnerReceiptSettings.fromMap(response);
  }

  Future<OwnerDevicesResult> getDevices() async {
    final response = await _apiClient.getJson(
      '/owner/devices',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou dispositivos no formato esperado.',
      );
    }
    return OwnerDevicesResult.fromMap(response);
  }

  Future<OwnerSyncStatus> getSyncStatus() async {
    final response = await _apiClient.getJson(
      '/owner/sync/status',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a sincronizacao no formato esperado.',
      );
    }
    return OwnerSyncStatus.fromMap(response);
  }

  Future<Map<String, dynamic>> subscribe({required String plan}) async {
    return _writeMap('/owner/billing/subscribe', <String, dynamic>{
      'plan': plan,
      'billingCycle': 'monthly',
    });
  }

  Future<Map<String, dynamic>> changePlan({required String plan}) async {
    return _writeMap('/owner/billing/change-plan', <String, dynamic>{
      'plan': plan,
    });
  }

  Future<Map<String, dynamic>> cancelSubscription() async {
    return _writeMap('/owner/billing/cancel', const <String, dynamic>{
      'effective': 'period_end',
    });
  }

  Future<Map<String, dynamic>> resumeSubscription() async {
    return _writeMap('/owner/billing/resume');
  }

  Future<Map<String, dynamic>> refreshBilling() async {
    return _writeMap('/owner/billing/refresh');
  }

  Future<Map<String, dynamic>> _writeMap(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await _apiClient.postJson(
      path,
      accessToken: await _readRequiredToken(),
      body: body,
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou a resposta no formato esperado.',
      );
    }
    return response;
  }

  Future<String> _readRequiredToken() async {
    final token = await _authStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const OwnerApiException(
        message: 'Sua sessao expirou. Entre novamente.',
        statusCode: 401,
        code: 'OWNER_AUTH_REQUIRED',
      );
    }
    return token.trim();
  }
}
