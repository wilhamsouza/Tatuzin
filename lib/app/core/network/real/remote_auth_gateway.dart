import 'dart:async';
import 'dart:io';

import '../../constants/app_constants.dart';
import '../../entitlements/plan_entitlements.dart';
import '../../errors/app_exceptions.dart';
import '../../session/app_session.dart';
import '../../session/app_user.dart';
import '../../session/auth_token_storage.dart';
import '../../session/company_context.dart';
import '../../utils/app_logger.dart';
import '../contracts/api_client_contract.dart';
import '../contracts/auth_gateway.dart';
import 'remote_sign_up_request.dart';

class RemoteAuthGateway implements AuthGateway {
  const RemoteAuthGateway({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
    Duration authSessionTimeout = const Duration(seconds: 10),
    Duration currentUserTimeout = const Duration(seconds: 8),
    Duration currentCompanyTimeout = const Duration(seconds: 8),
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage,
       _authSessionTimeout = authSessionTimeout,
       _currentUserTimeout = currentUserTimeout,
       _currentCompanyTimeout = currentCompanyTimeout;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;
  final Duration _authSessionTimeout;
  final Duration _currentUserTimeout;
  final Duration _currentCompanyTimeout;

  @override
  Future<AppSession?> restoreSession() async {
    final stopwatch = Stopwatch()..start();
    _logStepStarted('auth_session_load_started');
    final token = await _tokenStorage.readAccessToken();
    final clientContext = await _tokenStorage.readClientContext();
    if (token == null) {
      _logStepCompleted('auth_session_loaded', stopwatch, restored: false);
      return null;
    }
    if (clientContext == null) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        const AuthenticationException('missing_client_instance_id'),
      );
      await _tokenStorage.clear();
      return null;
    }

    try {
      final identity = await _fetchIdentity(
        token,
        clientInstanceId: clientContext.clientInstanceId,
      );
      final session = _buildSession(
        identity,
        clientInstanceId: clientContext.clientInstanceId,
      );
      _logStepCompleted(
        'auth_session_loaded',
        stopwatch,
        companyRemoteId: session.company.remoteId,
        userRemoteId: session.user.remoteId,
        restored: true,
      );
      return session;
    } on AuthenticationException catch (error, stackTrace) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        error,
        stackTrace: stackTrace,
      );
      await _tokenStorage.clear();
      return null;
    } catch (error, stackTrace) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<AppSession> refreshSession() async {
    final stopwatch = Stopwatch()..start();
    _logStepStarted('auth_session_load_started');
    final token = await _tokenStorage.readAccessToken();
    final clientContext = await _tokenStorage.readClientContext();
    if (token == null) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        const AuthenticationException('missing_refresh_session'),
      );
      throw const AuthenticationException(
        'Nao existe sessao remota salva para atualizar.',
      );
    }
    if (clientContext == null) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        const AuthenticationException('missing_client_instance_id'),
      );
      await _tokenStorage.clear();
      throw const AuthenticationException(
        'Sessao remota salva sem identificador deste dispositivo.',
      );
    }

    try {
      final identity = await _fetchIdentity(
        token,
        clientInstanceId: clientContext.clientInstanceId,
      );
      final session = _buildSession(
        identity,
        clientInstanceId: clientContext.clientInstanceId,
      );
      _logStepCompleted(
        'auth_session_loaded',
        stopwatch,
        companyRemoteId: session.company.remoteId,
        userRemoteId: session.user.remoteId,
        restored: true,
      );
      return session;
    } catch (error, stackTrace) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<AppSession> signIn({
    required String identifier,
    required String password,
  }) async {
    final clientContext = await _tokenStorage.ensureClientContext(
      clientType: 'mobile_app',
      deviceLabel: _deviceLabel,
      platform: _platformLabel,
      appVersion: AppConstants.appVersion,
    );

    final stopwatch = Stopwatch()..start();
    try {
      _logStepStarted('auth_session_load_started');
      final response = await _apiClient.postJson(
        '/auth/login',
        body: <String, dynamic>{
          'email': identifier.trim(),
          'password': password,
          ...clientContext.toApiPayload(),
        },
        options: ApiRequestOptions(timeout: _authSessionTimeout),
      );
      final userRemoteId = _readOptionalStringFromNestedMap(
        response.data,
        'user',
        'id',
      );
      _logStepCompleted(
        'auth_session_loaded',
        stopwatch,
        userRemoteId: userRemoteId,
      );
      return _buildAuthenticatedSession(
        response.data,
        clientInstanceId: clientContext.clientInstanceId,
      );
    } catch (error, stackTrace) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        error,
        stackTrace: stackTrace,
      );
      await _tokenStorage.clear();
      rethrow;
    }
  }

  @override
  Future<AppSession> signUp({
    required String companyName,
    required String companySlug,
    required String userName,
    required String email,
    required String password,
  }) async {
    final clientContext = await _tokenStorage.ensureClientContext(
      clientType: 'mobile_app',
      deviceLabel: _deviceLabel,
      platform: _platformLabel,
      appVersion: AppConstants.appVersion,
    );

    final request = RemoteSignUpRequest(
      companyName: companyName,
      companySlug: companySlug,
      userName: userName,
      email: email,
      password: password,
    );

    final stopwatch = Stopwatch()..start();
    try {
      _logStepStarted('auth_session_load_started');
      final response = await _apiClient.postJson(
        '/auth/register',
        body: request.toApiPayload(clientContext),
        options: ApiRequestOptions(timeout: _authSessionTimeout),
      );
      final userRemoteId = _readOptionalStringFromNestedMap(
        response.data,
        'user',
        'id',
      );
      _logStepCompleted(
        'auth_session_loaded',
        stopwatch,
        userRemoteId: userRemoteId,
      );
      return _buildAuthenticatedSession(
        response.data,
        clientInstanceId: clientContext.clientInstanceId,
      );
    } catch (error, stackTrace) {
      _logStepFailure(
        'auth_session_load_started',
        stopwatch,
        error,
        stackTrace: stackTrace,
      );
      await _tokenStorage.clear();
      rethrow;
    }
  }

  @override
  Future<String> requestPasswordReset({required String email}) async {
    final response = await _apiClient.postJson(
      '/auth/forgot-password',
      body: <String, dynamic>{'email': email.trim()},
    );

    return _readMessage(
      response.data,
      fallbackMessage:
          'Se existir uma conta com este e-mail, enviaremos as instrucoes para redefinir sua senha.',
    );
  }

  @override
  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final response = await _apiClient.postJson(
      '/auth/reset-password',
      body: <String, dynamic>{
        'token': token.trim(),
        'newPassword': newPassword,
      },
    );

    await _tokenStorage.clear();

    return _readMessage(
      response.data,
      fallbackMessage:
          'Sua senha foi redefinida com sucesso. Entre novamente para continuar.',
    );
  }

  @override
  Future<void> signOut() async {
    final token = await _tokenStorage.readAccessToken();
    if (token != null) {
      try {
        await _apiClient.postJson('/auth/logout', options: _authorized(token));
      } on AppException {
        // Keep logout resilient on the device even if the backend is down.
      }
    }

    await _tokenStorage.clear();
  }

  Future<_AuthIdentityPayload> _fetchIdentity(
    String accessToken, {
    required String clientInstanceId,
  }) async {
    final userStopwatch = Stopwatch()..start();
    _logStepStarted('current_user_load_started');
    late ApiResponse<Map<String, dynamic>> meResponse;
    try {
      meResponse = await _apiClient.getJson(
        '/auth/me',
        options: ApiRequestOptions(
          headers: _authorized(accessToken).headers,
          timeout: _currentUserTimeout,
        ),
      );
    } catch (error, stackTrace) {
      _logStepFailure(
        'current_user_load_started',
        userStopwatch,
        error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final userRemoteId = _readOptionalStringFromNestedMap(
      meResponse.data,
      'user',
      'id',
    );
    _logStepCompleted(
      'current_user_loaded',
      userStopwatch,
      userRemoteId: userRemoteId,
    );

    final latestAccessToken =
        await _tokenStorage.readAccessToken() ?? accessToken;
    final companyStopwatch = Stopwatch()..start();
    _logStepStarted('app_bootstrap_load_started', userRemoteId: userRemoteId);
    late ApiResponse<Map<String, dynamic>> bootstrapResponse;
    try {
      bootstrapResponse = await _apiClient.getJson(
        '/app/bootstrap',
        options: ApiRequestOptions(
          headers: _authorized(
            latestAccessToken,
            clientInstanceId: clientInstanceId,
          ).headers,
          timeout: _currentCompanyTimeout,
        ),
      );
    } catch (error, stackTrace) {
      _logStepFailure(
        'app_bootstrap_load_started',
        companyStopwatch,
        error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final companyRemoteId = _readOptionalStringFromNestedMap(
      bootstrapResponse.data,
      'company',
      'id',
    );
    _logStepCompleted(
      'app_bootstrap_loaded',
      companyStopwatch,
      companyRemoteId: companyRemoteId,
      userRemoteId: userRemoteId,
    );

    return _AuthIdentityPayload.fromBootstrap(
      bootstrapResponse.data,
      fallbackUser: meResponse.data['user'] is Map
          ? Map<String, dynamic>.from(meResponse.data['user'] as Map)
          : null,
    );
  }

  ApiRequestOptions _authorized(String token, {String? clientInstanceId}) {
    return ApiRequestOptions(
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        if (clientInstanceId != null && clientInstanceId.trim().isNotEmpty)
          'X-Client-Instance-Id': clientInstanceId.trim(),
      },
    );
  }

  Future<AppSession> _buildAuthenticatedSession(
    Map<String, dynamic> authPayload, {
    required String clientInstanceId,
  }) async {
    final accessToken = _readString(
      authPayload,
      'accessToken',
      fallbackMessage: 'A API nao retornou um token de acesso valido.',
    );
    final refreshToken = _readString(
      authPayload,
      'refreshToken',
      fallbackMessage: 'A API nao retornou um refresh token valido.',
    );

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    final userStopwatch = Stopwatch()..start();
    _logStepStarted('current_user_load_started');
    final userRemoteId = _readOptionalStringFromNestedMap(
      authPayload,
      'user',
      'id',
    );
    _logStepCompleted(
      'current_user_loaded',
      userStopwatch,
      userRemoteId: userRemoteId,
    );

    final companyStopwatch = Stopwatch()..start();
    _logStepStarted('app_bootstrap_load_started', userRemoteId: userRemoteId);
    late ApiResponse<Map<String, dynamic>> bootstrapResponse;
    try {
      bootstrapResponse = await _apiClient.getJson(
        '/app/bootstrap',
        options: ApiRequestOptions(
          headers: _authorized(
            accessToken,
            clientInstanceId: clientInstanceId,
          ).headers,
          timeout: _currentCompanyTimeout,
        ),
      );
    } catch (error, stackTrace) {
      _logStepFailure(
        'app_bootstrap_load_started',
        companyStopwatch,
        error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final companyRemoteId = _readOptionalStringFromNestedMap(
      bootstrapResponse.data,
      'company',
      'id',
    );
    _logStepCompleted(
      'app_bootstrap_loaded',
      companyStopwatch,
      companyRemoteId: companyRemoteId,
      userRemoteId: userRemoteId,
    );

    return _buildSession(
      _AuthIdentityPayload.fromBootstrap(
        bootstrapResponse.data,
        fallbackUser: authPayload['user'] is Map
            ? Map<String, dynamic>.from(authPayload['user'] as Map)
            : null,
      ),
      clientInstanceId: clientInstanceId,
    );
  }

  AppSession _buildSession(
    _AuthIdentityPayload payload, {
    required String? clientInstanceId,
  }) {
    return AppSession(
      scope: SessionScope.authenticatedRemote,
      user: AppUser(
        localId: null,
        remoteId: payload.userId,
        displayName: payload.userName,
        email: payload.userEmail,
        roleLabel: _roleLabel(payload.membershipRole),
        kind: AppUserKind.remoteAuthenticated,
        isPlatformAdmin: payload.isPlatformAdmin,
      ),
      company: CompanyContext(
        localId: null,
        remoteId: payload.companyId,
        displayName: payload.companyName,
        legalName: payload.companyLegalName,
        documentNumber: payload.companyDocumentNumber,
        licensePlan: payload.licensePlan,
        licenseStatus: payload.licenseStatus,
        licenseStartsAt: payload.licenseStartsAt,
        licenseExpiresAt: payload.licenseExpiresAt,
        maxDevices: payload.maxDevices,
        syncEnabled: payload.syncEnabled,
        entitlements: payload.entitlements,
      ),
      startedAt: DateTime.now(),
      isOfflineFallback: false,
      clientInstanceId: clientInstanceId,
      membership: AppMembershipContext(
        role: payload.membershipRole,
        permissions: payload.membershipPermissions,
      ),
      employee: payload.employee,
    );
  }

  String _roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'OWNER':
        return 'Dono da empresa';
      case 'ADMIN':
        return 'Administrador';
      case 'OPERATOR':
        return 'Operador';
      case 'SUPPORT':
        return 'Suporte';
      default:
        return role;
    }
  }

  String get _platformLabel {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    return Platform.operatingSystem;
  }

  String get _deviceLabel {
    if (Platform.isAndroid) {
      return 'Tatuzin Android';
    }
    if (Platform.isIOS) {
      return 'Tatuzin iPhone';
    }
    if (Platform.isWindows) {
      return 'Tatuzin Windows';
    }
    if (Platform.isMacOS) {
      return 'Tatuzin macOS';
    }
    if (Platform.isLinux) {
      return 'Tatuzin Linux';
    }
    return 'Tatuzin App';
  }

  void _logStepStarted(
    String step, {
    String? companyRemoteId,
    String? userRemoteId,
  }) {
    AppLogger.info(
      '$step | duration_ms=0 | '
      'company_remote_id=${companyRemoteId ?? 'n/a'} | '
      'user_remote_id=${userRemoteId ?? 'n/a'}',
    );
  }

  void _logStepCompleted(
    String step,
    Stopwatch stopwatch, {
    String? companyRemoteId,
    String? userRemoteId,
    bool? restored,
  }) {
    AppLogger.info(
      '$step | duration_ms=${stopwatch.elapsedMilliseconds} | '
      'company_remote_id=${companyRemoteId ?? 'n/a'} | '
      'user_remote_id=${userRemoteId ?? 'n/a'}'
      '${restored == null ? '' : ' | restored=$restored'}',
    );
  }

  void _logStepFailure(
    String step,
    Stopwatch stopwatch,
    Object error, {
    StackTrace? stackTrace,
  }) {
    AppLogger.error(
      'bootstrap_failed | step=$step | duration_ms=${stopwatch.elapsedMilliseconds} | '
      'reason=$error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  String? _readOptionalStringFromNestedMap(
    Map<String, dynamic> source,
    String parentKey,
    String childKey,
  ) {
    final parent = source[parentKey];
    if (parent is! Map<String, dynamic>) {
      return null;
    }

    final value = parent[childKey];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return null;
  }

  static String _readString(
    Map<String, dynamic> source,
    String key, {
    required String fallbackMessage,
  }) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    throw AuthenticationException(fallbackMessage);
  }

  static String _readMessage(
    Map<String, dynamic> source, {
    required String fallbackMessage,
  }) {
    final value = source['message'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallbackMessage;
  }
}

class _AuthIdentityPayload {
  const _AuthIdentityPayload({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.isPlatformAdmin,
    required this.companyId,
    required this.companyName,
    required this.companyLegalName,
    required this.companyDocumentNumber,
    required this.membershipRole,
    required this.membershipPermissions,
    required this.employee,
    required this.licensePlan,
    required this.licenseStatus,
    required this.licenseStartsAt,
    required this.licenseExpiresAt,
    required this.maxDevices,
    required this.syncEnabled,
    required this.entitlements,
  });

  final String userId;
  final String userName;
  final String userEmail;
  final bool isPlatformAdmin;
  final String companyId;
  final String companyName;
  final String companyLegalName;
  final String? companyDocumentNumber;
  final String membershipRole;
  final Set<String> membershipPermissions;
  final AppEmployeeContext? employee;
  final String? licensePlan;
  final String? licenseStatus;
  final DateTime? licenseStartsAt;
  final DateTime? licenseExpiresAt;
  final int? maxDevices;
  final bool syncEnabled;
  final PlanEntitlements entitlements;

  factory _AuthIdentityPayload.fromBootstrap(
    Map<String, dynamic> source, {
    required Map<String, dynamic>? fallbackUser,
  }) {
    final sourceUser = source['user'] is Map
        ? Map<String, dynamic>.from(source['user'] as Map)
        : null;
    final user = <String, dynamic>{
      if (fallbackUser != null) ...fallbackUser,
      if (sourceUser != null) ...sourceUser,
    };
    final company = source['company'];
    final membership = source['membership'];
    final license = source['license'];

    if (user.isEmpty ||
        company is! Map<String, dynamic> ||
        membership is! Map<String, dynamic>) {
      throw const AuthenticationException(
        'A API nao retornou a identidade esperada para a sessao remota.',
      );
    }

    final legalName = (company['legalName'] as String?)?.trim();
    final companyName = RemoteAuthGateway._readString(
      company,
      'name',
      fallbackMessage: 'Nome da empresa remota ausente.',
    );

    return _AuthIdentityPayload(
      userId: RemoteAuthGateway._readString(
        user,
        'id',
        fallbackMessage: 'Usuario remoto invalido.',
      ),
      userName: RemoteAuthGateway._readString(
        user,
        'name',
        fallbackMessage: 'Nome do usuario remoto ausente.',
      ),
      userEmail: RemoteAuthGateway._readString(
        user,
        'email',
        fallbackMessage: 'E-mail do usuario remoto ausente.',
      ),
      isPlatformAdmin: user['isPlatformAdmin'] == true,
      companyId: RemoteAuthGateway._readString(
        company,
        'id',
        fallbackMessage: 'Empresa remota invalida.',
      ),
      companyName: companyName,
      companyLegalName: legalName != null && legalName.isNotEmpty
          ? legalName
          : companyName,
      companyDocumentNumber: (company['documentNumber'] as String?)?.trim(),
      membershipRole: RemoteAuthGateway._readString(
        membership,
        'role',
        fallbackMessage: 'Perfil remoto ausente.',
      ),
      membershipPermissions: _readPermissions(membership['permissions']),
      employee: _readEmployeeContext(source['employee']),
      licensePlan: license is Map<String, dynamic>
          ? (license['plan'] as String?)?.trim()
          : null,
      licenseStatus: license is Map<String, dynamic>
          ? (license['status'] as String?)?.trim().toLowerCase()
          : null,
      licenseStartsAt: _tryParseDateTime(
        license is Map<String, dynamic> ? license['startsAt'] : null,
      ),
      licenseExpiresAt: _tryParseDateTime(
        license is Map<String, dynamic> ? license['expiresAt'] : null,
      ),
      maxDevices: license is Map<String, dynamic>
          ? _tryParseInt(license['maxDevices'])
          : null,
      syncEnabled: license is Map<String, dynamic>
          ? license['syncEnabled'] == true
          : false,
      entitlements: PlanEntitlements.fromBootstrapJson(source),
    );
  }

  static DateTime? _tryParseDateTime(Object? rawValue) {
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(rawValue.trim());
  }

  static int? _tryParseInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return int.tryParse(rawValue.trim());
    }
    return null;
  }

  static Set<String> _readPermissions(Object? rawValue) {
    if (rawValue is! Iterable) {
      return const <String>{};
    }
    return rawValue
        .whereType<String>()
        .map((permission) => permission.trim())
        .where((permission) => permission.isNotEmpty)
        .toSet();
  }

  static AppEmployeeContext? _readEmployeeContext(Object? rawValue) {
    if (rawValue is! Map) {
      return null;
    }
    final source = Map<String, dynamic>.from(rawValue);
    final id = (source['id'] as String?)?.trim();
    final role = (source['role'] as String?)?.trim();
    final status = (source['status'] as String?)?.trim();
    if (id == null ||
        id.isEmpty ||
        role == null ||
        role.isEmpty ||
        status == null ||
        status.isEmpty) {
      return null;
    }
    return AppEmployeeContext(
      id: id,
      role: role,
      status: status,
      permissions: _readPermissions(source['permissions']),
    );
  }
}
