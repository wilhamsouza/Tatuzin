import '../auth/admin_auth_storage.dart';
import '../auth/admin_debug_log.dart';
import '../models/admin_access_models.dart';
import '../models/admin_analytics_models.dart';
import '../models/admin_billing_models.dart';
import '../models/admin_crm_models.dart';
import '../models/admin_hybrid_governance_models.dart';
import '../models/admin_models.dart';
import '../models/admin_plan_models.dart';
import '../models/admin_sync_center_models.dart';
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
        message:
            'A API nao retornou a sessao administrativa no formato esperado.',
      );
    }

    adminDebugLog('auth.service.login.response', {
      'keys': response.keys.toList(growable: false),
      'hasAccessToken': response['accessToken'] is String,
      'hasRefreshToken': response['refreshToken'] is String,
      'tokenType': response['tokenType']?.toString(),
      'isPlatformAdmin': response['user'] is Map<String, dynamic>
          ? (response['user'] as Map<String, dynamic>)['isPlatformAdmin'] ==
                true
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
      'hasAccessToken': accessToken.trim().isNotEmpty,
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
      'companies': (results[0] as AdminPaginatedResult<AdminCompanySummary>)
          .items
          .length,
      'auditEvents': (results[1] as AdminAuditSummary).recentEvents.length,
      'syncCompanies': (results[2] as AdminSyncSummary).companySummaries.length,
    });

    return AdminDashboardSnapshot(
      companies:
          (results[0] as AdminPaginatedResult<AdminCompanySummary>).items,
      auditSummary: results[1] as AdminAuditSummary,
      syncSummary: results[2] as AdminSyncSummary,
    );
  }

  Future<AdminPaginatedResult<AdminCompanySummary>> fetchCompanies({
    AdminCompaniesQuery? query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/companies',
      accessToken: await _readRequiredToken(),
      queryParameters: query?.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminCompanySummary>(
      items: readAdminItems(payload).map(AdminCompanySummary.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
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

  Future<AdminPlansOverview> fetchPlansOverview() async {
    final response = await _apiClient.getJson(
      '/admin/plans',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou planos no formato esperado.',
      );
    }

    return AdminPlansOverview.fromMap(response);
  }

  Future<AdminCompanyAccessSummary> fetchCompanyAccessSummary(
    String companyId,
  ) async {
    final response = await _apiClient.getJson(
      '/admin/companies/$companyId/access-summary',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou usuarios e funcionarios no formato esperado.',
      );
    }

    return AdminCompanyAccessSummary.fromMap(response);
  }

  Future<AdminCompanySyncHealth> fetchCompanySyncHealth(
    String companyId,
  ) async {
    final response = await _apiClient.getJson(
      '/admin/companies/$companyId/sync/health',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou a saude da sincronizacao no formato esperado.',
      );
    }

    return AdminCompanySyncHealth.fromMap(response);
  }

  Future<List<AdminCompanySyncDevice>> fetchCompanySyncDevices(
    String companyId,
  ) async {
    final response = await _apiClient.getJson(
      '/admin/companies/$companyId/devices',
      accessToken: await _readRequiredToken(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return readAdminItems(
      payload,
    ).map(AdminCompanySyncDevice.fromMap).toList(growable: false);
  }

  Future<AdminPaginatedResult<AdminSyncEventDiagnostic>>
  fetchCompanySyncEvents({required AdminCompanySyncEventsQuery query}) async {
    final response = await _apiClient.getJson(
      '/admin/companies/${query.companyId}/sync/events',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminSyncEventDiagnostic>(
      items: readAdminItems(
        payload,
      ).map(AdminSyncEventDiagnostic.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminPaginatedResult<AdminSyncConflictDiagnostic>>
  fetchCompanySyncConflicts({
    required AdminCompanySyncConflictsQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/companies/${query.companyId}/sync/conflicts',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminSyncConflictDiagnostic>(
      items: readAdminItems(
        payload,
      ).map(AdminSyncConflictDiagnostic.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminPaginatedResult<AdminSyncIncidentDiagnostic>>
  fetchCompanySyncIncidents({
    required AdminCompanySyncIncidentsQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/companies/${query.companyId}/sync/incidents',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminSyncIncidentDiagnostic>(
      items: readAdminItems(
        payload,
      ).map(AdminSyncIncidentDiagnostic.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminPaginatedResult<AdminLicenseSnapshot>> fetchLicenses({
    AdminLicensesQuery? query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/licenses',
      accessToken: await _readRequiredToken(),
      queryParameters: query?.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminLicenseSnapshot>(
      items: readAdminItems(payload).map(AdminLicenseSnapshot.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
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

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    final license = payload['license'];
    if (license is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a licenca atualizada no formato esperado.',
      );
    }
    return AdminLicenseSnapshot.fromMap(license);
  }

  Future<AdminPaginatedResult<AdminBillingCompanySummary>>
  fetchBillingCompanies({AdminBillingCompaniesQuery? query}) async {
    final response = await _apiClient.getJson(
      '/admin/billing/companies',
      accessToken: await _readRequiredToken(),
      queryParameters: query?.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminBillingCompanySummary>(
      items: readAdminItems(
        payload,
      ).map(AdminBillingCompanySummary.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminBillingCompanyStatus> fetchBillingCompanyStatus(
    String companyId,
  ) async {
    final response = await _apiClient.getJson(
      '/admin/companies/$companyId/billing/status',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API não retornou o status de billing no formato esperado.',
      );
    }

    return AdminBillingCompanyStatus.fromMap(response);
  }

  Future<AdminPaginatedResult<AdminBillingEvent>> fetchBillingEvents({
    required AdminBillingListQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/companies/${query.companyId}/billing/events',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminBillingEvent>(
      items: readAdminItems(
        payload,
      ).map(AdminBillingEvent.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminPaginatedResult<AdminBillingCheckoutSession>>
  fetchBillingCheckoutSessions({required AdminBillingListQuery query}) async {
    final response = await _apiClient.getJson(
      '/admin/companies/${query.companyId}/billing/checkout-sessions',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminBillingCheckoutSession>(
      items: readAdminItems(
        payload,
      ).map(AdminBillingCheckoutSession.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminBillingActionResult> refreshBillingCompany({
    required String companyId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da ação administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/companies/$companyId/billing/refresh',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{'reason': trimmedReason},
    );
    return AdminBillingActionResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminBillingActionResult> forceBillingPlan({
    required String companyId,
    required String plan,
    required String reason,
    String? status,
    DateTime? currentPeriodEnd,
    bool clearProvider = false,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da ação administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/companies/$companyId/billing/force-plan',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        'plan': plan.trim(),
        'reason': trimmedReason,
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (currentPeriodEnd != null)
          'currentPeriodEnd': currentPeriodEnd.toIso8601String(),
        'clearProvider': clearProvider,
      },
    );
    return AdminBillingActionResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminBillingActionResult> cancelBillingLocal({
    required String companyId,
    required String reason,
    required String effective,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da ação administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/companies/$companyId/billing/cancel-local',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        'reason': trimmedReason,
        'effective': effective.trim(),
      },
    );
    return AdminBillingActionResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminAuditSummary> fetchAuditSummary({AdminAuditQuery? query}) async {
    final response = await _apiClient.getJson(
      '/admin/audit/summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query?.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou a auditoria administrativa no formato esperado.',
      );
    }

    return AdminAuditSummary.fromMap(response);
  }

  Future<AdminSyncSummary> fetchSyncSummary({AdminSyncQuery? query}) async {
    final response = await _apiClient.getJson(
      '/admin/sync/summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query?.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a saude da sync no formato esperado.',
      );
    }

    return AdminSyncSummary.fromMap(response);
  }

  Future<AdminSyncOperationalSummary> fetchSyncOperationalSummary({
    AdminSyncOperationalQuery? query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/operational-summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query?.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o resumo operacional de sync no formato esperado.',
      );
    }

    return AdminSyncOperationalSummary.fromMap(response);
  }

  Future<AdminPaginatedResult<AdminSyncCenterCompany>>
  fetchSyncCenterCompanies({AdminSyncCenterCompaniesQuery? query}) async {
    final response = await _apiClient.getJson(
      '/admin/sync/companies',
      accessToken: await _readRequiredToken(),
      queryParameters: (query ?? const AdminSyncCenterCompaniesQuery())
          .toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminSyncCenterCompany>(
      items: readAdminItems(
        payload,
      ).map(AdminSyncCenterCompany.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminSyncCenterCompanySummary> fetchSyncCenterCompanySummary(
    String companyId,
  ) async {
    final response = await _apiClient.getJson(
      '/admin/sync/companies/$companyId/summary',
      accessToken: await _readRequiredToken(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o resumo de sincronizacao no formato esperado.',
      );
    }

    return AdminSyncCenterCompanySummary.fromMap(response);
  }

  Future<AdminPaginatedResult<AdminSyncCenterEvent>> fetchSyncCenterEvents({
    required AdminSyncCenterEventsQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/companies/${query.companyId}/events',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminSyncCenterEvent>(
      items: readAdminItems(
        payload,
      ).map(AdminSyncCenterEvent.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminPaginatedResult<AdminSyncCenterConflict>>
  fetchSyncCenterConflicts({
    required AdminSyncCenterConflictsQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/companies/${query.companyId}/conflicts',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminSyncCenterConflict>(
      items: readAdminItems(
        payload,
      ).map(AdminSyncCenterConflict.fromMap).toList(growable: false),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<List<AdminSyncSupportDevice>> fetchSyncSupportDevices({
    required String companyId,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/companies/$companyId/devices',
      accessToken: await _readRequiredToken(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return readAdminItems(
      payload,
    ).map(AdminSyncSupportDevice.fromMap).toList(growable: false);
  }

  Future<AdminSyncSupportDeviceDetail> fetchSyncSupportDeviceDetail({
    required String companyId,
    required String deviceId,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/companies/$companyId/devices/$deviceId/diagnostics',
      accessToken: await _readRequiredToken(),
    );
    return AdminSyncSupportDeviceDetail.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncSupportDryRunResult> dryRunSyncSupportAction({
    required String companyId,
    required String deviceId,
    required String command,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/sync/companies/$companyId/devices/$deviceId/support-actions/dry-run',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{'command': command, 'reason': normalizedReason},
    );
    return AdminSyncSupportDryRunResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncSupportActionResult> createSyncSupportAction({
    required String companyId,
    required String deviceId,
    required String command,
    required String reason,
    required String confirmationText,
  }) async {
    final normalizedReason = reason.trim();
    final confirmation = confirmationText.trim();
    if (normalizedReason.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    if (confirmation.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o texto de confirmacao.',
        code: 'ADMIN_CONFIRMATION_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/sync/companies/$companyId/devices/$deviceId/support-actions',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        'command': command,
        'reason': normalizedReason,
        'confirmationText': confirmation,
      },
    );
    return AdminSyncSupportActionResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncCenterEventDetail> fetchSyncCenterEventDetail({
    required String companyId,
    required String eventId,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/events/$eventId',
      accessToken: await _readRequiredToken(),
      queryParameters: <String, String>{'companyId': companyId},
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o evento de sincronizacao no formato esperado.',
      );
    }

    return AdminSyncCenterEventDetail.fromMap(response);
  }

  Future<AdminSyncCenterConflictDetail> fetchSyncCenterConflictDetail({
    required String companyId,
    required String conflictId,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/sync/conflicts/$conflictId',
      accessToken: await _readRequiredToken(),
      queryParameters: <String, String>{'companyId': companyId},
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o conflito de sincronizacao no formato esperado.',
      );
    }

    return AdminSyncCenterConflictDetail.fromMap(response);
  }

  Future<AdminSyncCenterDryRunResult> dryRunSyncEventReprocess({
    required String companyId,
    required String eventId,
    required String reason,
  }) async {
    final body = _syncCenterReasonBody(companyId: companyId, reason: reason);
    final response = await _apiClient.postJson(
      '/admin/sync/events/$eventId/reprocess-dry-run',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    return AdminSyncCenterDryRunResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncCenterActionResult> reprocessSyncEvent({
    required String companyId,
    required String eventId,
    required String reason,
    required String confirmationText,
  }) async {
    final body = _syncCenterReasonBody(companyId: companyId, reason: reason);
    final confirmation = confirmationText.trim();
    if (confirmation != 'REPROCESSAR') {
      throw const AdminApiException(
        message: 'Digite REPROCESSAR para confirmar.',
        code: 'ADMIN_CONFIRMATION_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/sync/events/$eventId/reprocess',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{...body, 'confirmationText': confirmation},
    );
    return AdminSyncCenterActionResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncCenterDryRunResult> dryRunSyncConflictArchive({
    required String companyId,
    required String conflictId,
    required String reason,
  }) async {
    final body = _syncCenterReasonBody(companyId: companyId, reason: reason);
    final response = await _apiClient.postJson(
      '/admin/sync/conflicts/$conflictId/archive-dry-run',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    return AdminSyncCenterDryRunResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncCenterActionResult> archiveSyncConflict({
    required String companyId,
    required String conflictId,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    final body = _syncCenterReasonBody(companyId: companyId, reason: reason);
    final confirmation = confirmationText.trim();
    if (confirmation != 'ARQUIVAR') {
      throw const AdminApiException(
        message: 'Digite ARQUIVAR para liberar a confirmacao.',
        code: 'ADMIN_CONFIRMATION_REQUIRED',
      );
    }
    final response = await _apiClient.postJson(
      '/admin/sync/conflicts/$conflictId/archive',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        ...body,
        'confirmationText': confirmation,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return AdminSyncCenterActionResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminSyncCenterDryRunResult> dryRunManualStockAdjustment({
    required String companyId,
    required String conflictId,
    required String reason,
  }) async {
    final body = _syncCenterReasonBody(companyId: companyId, reason: reason);
    final response = await _apiClient.postJson(
      '/admin/sync/conflicts/$conflictId/manual-stock-adjustment-dry-run',
      accessToken: await _readRequiredToken(),
      body: body,
    );
    return AdminSyncCenterDryRunResult.fromMap(
      response as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<AdminManagementDashboardSnapshot> fetchManagementDashboard({
    required AdminManagementScopeQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/dashboard',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o dashboard gerencial no formato esperado.',
      );
    }

    return AdminManagementDashboardSnapshot.fromMap(response);
  }

  Future<AdminSalesByDayReport> fetchSalesByDayReport({
    required AdminManagementScopeQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/sales-by-day',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou o relatorio de vendas por dia.',
      );
    }

    return AdminSalesByDayReport.fromMap(response);
  }

  Future<AdminSalesByProductReport> fetchSalesByProductReport({
    required AdminManagementScopeQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/sales-by-product',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou o relatorio de vendas por produto.',
      );
    }

    return AdminSalesByProductReport.fromMap(response);
  }

  Future<AdminSalesByCustomerReport> fetchSalesByCustomerReport({
    required AdminManagementScopeQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/sales-by-customer',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou o relatorio de vendas por cliente.',
      );
    }

    return AdminSalesByCustomerReport.fromMap(response);
  }

  Future<AdminCashConsolidatedReport> fetchCashConsolidatedReport({
    required AdminManagementScopeQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/cash-consolidated',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou o relatorio de caixa consolidado.',
      );
    }

    return AdminCashConsolidatedReport.fromMap(response);
  }

  Future<AdminFinancialSummaryReport> fetchFinancialSummaryReport({
    required AdminManagementScopeQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/analytics/reports/financial-summary',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o resumo financeiro consolidado no formato esperado.',
      );
    }

    return AdminFinancialSummaryReport.fromMap(response);
  }

  Future<AdminPaginatedResult<AdminCrmCustomerSummary>> fetchCrmCustomers({
    required AdminCrmCustomersQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/crm/customers',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminCrmCustomerSummary>(
      items: readAdminItems(
        payload,
      ).map(AdminCrmCustomerSummary.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminCrmCustomerDetail> fetchCrmCustomerDetail({
    required AdminCrmCustomerKey key,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/crm/customers/${key.customerId}',
      accessToken: await _readRequiredToken(),
      queryParameters: key.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o detalhe do cliente CRM no formato esperado.',
      );
    }

    return AdminCrmCustomerDetail.fromMap(response);
  }

  Future<AdminPaginatedResult<AdminCrmTimelineEvent>> fetchCrmCustomerTimeline({
    required AdminCrmCustomerTimelineQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/crm/customers/${query.customerId}/timeline',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    return AdminPaginatedResult<AdminCrmTimelineEvent>(
      items: readAdminItems(
        payload,
      ).map(AdminCrmTimelineEvent.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(payload),
      filters: readAdminFilters(payload),
      sort: AdminSortMeta.fromPayload(payload),
    );
  }

  Future<AdminCrmNote> createCrmCustomerNote({
    required AdminCrmCustomerKey key,
    required String body,
  }) async {
    final response = await _apiClient.postJson(
      '/admin/crm/customers/${key.customerId}/notes',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{'companyId': key.companyId, 'body': body.trim()},
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    final note = payload['note'];
    if (note is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a nota CRM criada no formato esperado.',
      );
    }

    return AdminCrmNote.fromMap(note);
  }

  Future<AdminCrmTask> createCrmCustomerTask({
    required AdminCrmCustomerKey key,
    required String title,
    String? description,
    DateTime? dueAt,
    String? assignedToUserId,
  }) async {
    final response = await _apiClient.postJson(
      '/admin/crm/customers/${key.customerId}/tasks',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        'companyId': key.companyId,
        'title': title.trim(),
        'description': description?.trim(),
        'dueAt': dueAt?.toUtc().toIso8601String(),
        'assignedToUserId': assignedToUserId?.trim(),
      },
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    final task = payload['task'];
    if (task is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a tarefa CRM criada no formato esperado.',
      );
    }

    return AdminCrmTask.fromMap(task);
  }

  Future<List<AdminCrmTag>> applyCrmCustomerTags({
    required AdminCrmCustomerKey key,
    required List<String> labels,
    String mode = 'replace',
  }) async {
    final response = await _apiClient.postJson(
      '/admin/crm/customers/${key.customerId}/tags',
      accessToken: await _readRequiredToken(),
      body: <String, dynamic>{
        'companyId': key.companyId,
        'mode': mode,
        'tags': labels
            .map(
              (label) => <String, dynamic>{
                'label': label.trim(),
                'color': null,
              },
            )
            .toList(growable: false),
      },
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    final tags = payload['tags'];
    if (tags is! List<dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou as tags CRM no formato esperado.',
      );
    }

    return tags
        .whereType<Map<String, dynamic>>()
        .map(AdminCrmTag.fromMap)
        .toList(growable: false);
  }

  Future<AdminHybridGovernanceOverview> fetchHybridGovernanceOverview({
    required AdminHybridGovernanceQuery query,
  }) async {
    final response = await _apiClient.getJson(
      '/admin/hybrid-governance/overview',
      accessToken: await _readRequiredToken(),
      queryParameters: query.toQueryParameters(),
    );

    if (response is! Map<String, dynamic>) {
      throw const AdminApiException(
        message: 'A API nao retornou a governanca hibrida no formato esperado.',
      );
    }

    return AdminHybridGovernanceOverview.fromMap(response);
  }

  Future<AdminHybridGovernanceProfile> updateHybridGovernanceProfile({
    required String companyId,
    required AdminHybridGovernanceProfile profile,
  }) async {
    final response = await _apiClient.patchJson(
      '/admin/hybrid-governance/profile',
      accessToken: await _readRequiredToken(),
      body: profile.toUpdateBody(companyId),
    );

    final payload =
        response as Map<String, dynamic>? ?? const <String, dynamic>{};
    final rawProfile = payload['profile'];
    if (rawProfile is! Map<String, dynamic>) {
      throw const AdminApiException(
        message:
            'A API nao retornou o perfil de governanca hibrida no formato esperado.',
      );
    }

    return AdminHybridGovernanceProfile.fromMap(rawProfile);
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

  Map<String, dynamic> _syncCenterReasonBody({
    required String companyId,
    required String reason,
  }) {
    final normalizedCompanyId = companyId.trim();
    final normalizedReason = reason.trim();
    if (normalizedCompanyId.isEmpty) {
      throw const AdminApiException(
        message: 'Empresa obrigatoria para a acao de sincronizacao.',
        code: 'ADMIN_COMPANY_REQUIRED',
      );
    }
    if (normalizedReason.isEmpty) {
      throw const AdminApiException(
        message: 'Informe o motivo da acao administrativa.',
        code: 'ADMIN_REASON_REQUIRED',
      );
    }
    return <String, dynamic>{
      'companyId': normalizedCompanyId,
      'reason': normalizedReason,
    };
  }
}
