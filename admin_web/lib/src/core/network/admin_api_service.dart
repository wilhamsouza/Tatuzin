import '../auth/admin_auth_storage.dart';
import '../auth/admin_debug_log.dart';
import '../models/admin_models.dart';
import 'admin_api_client.dart';

class AdminApiService {
  const AdminApiService({
    required AdminApiClient apiClient,
    required AdminAuthStorage authStorage,
  }) : _apiClient = apiClient,
       _authStorage = authStorage;

  final AdminApiClient _apiClient;
  final AdminAuthStorage _authStorage;

  Future<AdminSession> login({
    required String email,
    required String password,
  }) async {
    final clientContext = await _authStorage.ensureClientContext();
    adminDebugLog('auth.service.login.request', {
      'email': email.trim(),
      'clientType': clientContext.clientType,
      'clientInstanceId': clientContext.clientInstanceId,
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
      throw const AdminApiException(
        message: 'A API nao retornou a sessao administrativa no formato esperado.',
      );
    }

    adminDebugLog('auth.service.login.response', {
      'keys': response.keys.toList(growable: false),
      'hasAccessToken': response['accessToken'] is String,
      'hasRefreshToken': response['refreshToken'] is String,
      'tokenType': response['tokenType']?.toString(),
      'isPlatformAdmin': response['user'] is Map<String, dynamic>
          ? (response['user'] as Map<String, dynamic>)['isPlatformAdmin'] == true
          : false,
      'sessionId': response['session'] is Map<String, dynamic>
          ? (response['session'] as Map<String, dynamic>)['id']?.toString()
          : null,
    });

    final session = AdminSession.fromLoginResponse(response);
    if (!session.user.isPlatformAdmin) {
      throw const AdminApiException(
        message: 'Este acesso e restrito ao Tatuzin Admin.',
        statusCode: 403,
        code: 'NOT_PLATFORM_ADMIN',
      );
    }
    return session;
  }

  Future<AdminSession> restoreSession(String accessToken) async {
    adminDebugLog('auth.service.restore.request', {
      'accessToken': accessToken,
    });
    final response = await _apiClient.getJson(
      '/auth/me',
      accessToken: accessToken,
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'Nao foi possivel restaurar a sessao administrativa.',
      );
    }

    final currentAccessToken =
        await _authStorage.readAccessToken() ?? accessToken.trim();
    final session = AdminSession.fromIdentityResponse(
      response,
      accessToken: currentAccessToken,
    );
    adminDebugLog('auth.service.restore.response', {
      'isPlatformAdmin': session.user.isPlatformAdmin,
      'userEmail': session.user.email,
    });
    if (!session.user.isPlatformAdmin) {
      throw const AdminApiException(
        message: 'Este acesso e restrito ao Tatuzin Admin.',
        statusCode: 403,
        code: 'NOT_PLATFORM_ADMIN',
      );
    }
    return session;
  }

  Future<void> logout(String accessToken) async {
    await _apiClient.postJson('/auth/logout', accessToken: accessToken);
  }

  Future<void> revokeSession(String sessionId) async {
    await _apiClient.postJson(
      '/admin/sessions/$sessionId/revoke',
      accessToken: await _readRequiredToken(),
    );
  }

  Future<AdminDashboardSnapshot> fetchDashboard() async {
    adminDebugLog('admin.dashboard.bootstrap.started');
    final results = await Future.wait<dynamic>([
      fetchCompanies(),
      fetchAuditSummary(),
      fetchSyncSummary(),
    ]);

    adminDebugLog('admin.dashboard.bootstrap.completed', {
      'companies': (results[0] as List<AdminCompanySummary>).length,
      'auditEvents': (results[1] as AdminAuditSummary).recentEvents.length,
      'syncCompanies': (results[2] as AdminSyncSummary).companySummaries.length,
    });

    return AdminDashboardSnapshot(
      companies: results[0] as List<AdminCompanySummary>,
      auditSummary: results[1] as AdminAuditSummary,
      syncSummary: results[2] as AdminSyncSummary,
    );
  }

  Future<List<AdminCompanySummary>> fetchCompanies() async {
    final response = await _apiClient.getJson(
      '/admin/companies',
      accessToken: await _readRequiredToken(),
    );

    final payload = response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return (payload['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AdminCompanySummary.fromMap)
        .toList();
  }

  Future<AdminCompanyDetail> fetchCompanyDetail(String companyId) async {
    final response = await _apiClient.getJson(
      '/admin/companies/$companyId',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou o detalhe da empresa no formato esperado.',
      );
    }

    return AdminCompanyDetail.fromMap(response);
  }

  Future<List<AdminLicenseSnapshot>> fetchLicenses() async {
    final response = await _apiClient.getJson(
      '/admin/licenses',
      accessToken: await _readRequiredToken(),
    );

    final payload = response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return (payload['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AdminLicenseSnapshot.fromMap)
        .toList();
  }

  Future<AdminLicenseSnapshot> updateLicense({
    required String companyId,
    required String plan,
    required String status,
    required DateTime? startsAt,
    required DateTime? expiresAt,
    required bool syncEnabled,
    required int? maxDevices,
  }) async {
    final response = await _apiClient.patchJson(
      '/admin/licenses/$companyId',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        'plan': plan.trim(),
        'status': status.trim().toLowerCase(),
        'startsAt': startsAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'syncEnabled': syncEnabled,
        'maxDevices': maxDevices,
      },
    );

    final payload = response as Map<String, dynamic>? ?? const <String, dynamic>{};
    final license = payload['license'];
    if (license is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a licenca atualizada no formato esperado.',
      );
    }
    return AdminLicenseSnapshot.fromMap(license);
  }

  Future<AdminAuditSummary> fetchAuditSummary() async {
    final response = await _apiClient.getJson(
      '/admin/audit/summary',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a auditoria administrativa no formato esperado.',
      );
    }

    return AdminAuditSummary.fromMap(response);
  }

  Future<AdminSyncSummary> fetchSyncSummary() async {
    final response = await _apiClient.getJson(
      '/admin/sync/summary',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a saude da sync no formato esperado.',
      );
    }

    return AdminSyncSummary.fromMap(response);
  }

  Future<String> _readRequiredToken() async {
    final token = await _authStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AdminApiException(
        message: 'Sessao administrativa nao encontrada. Faca login novamente.',
        statusCode: 401,
        code: 'ADMIN_SESSION_MISSING',
      );
    }
    return token.trim();
  }
}
