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

  Future<OwnerEmployeesPlaceholder> getEmployees() async {
    final response = await _apiClient.getJson(
      '/owner/employees',
      accessToken: await _readRequiredToken(),
    );
    if (response is! Map<String, dynamic>) {
      throw const OwnerApiException(
        message: 'A API nao retornou funcionarios no formato esperado.',
      );
    }
    return OwnerEmployeesPlaceholder.fromMap(response);
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
