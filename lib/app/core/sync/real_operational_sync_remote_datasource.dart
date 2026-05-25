import '../errors/app_exceptions.dart';
import '../network/contracts/api_client_contract.dart';
import '../session/auth_token_storage.dart';
import 'operational_sync_event.dart';
import 'operational_sync_remote_datasource.dart';

class RealOperationalSyncRemoteDataSource
    implements OperationalSyncRemoteDataSource {
  const RealOperationalSyncRemoteDataSource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;

  @override
  Future<OperationalSyncPushResponse> pushEvents(
    List<OperationalSyncEvent> events, {
    String? lastKnownServerVersion,
  }) async {
    final response = await _apiClient.postJson(
      '/sync/push',
      body: <String, dynamic>{
        if (lastKnownServerVersion != null)
          'lastKnownServerVersion': lastKnownServerVersion,
        'events': events.map((event) => event.toJson()).toList(),
      },
      options: await _authorizedOptions(),
    );
    return OperationalSyncPushResponse.fromJson(response.data);
  }

  @override
  Future<OperationalSyncPullResponse> pullChanges({
    required String sinceVersion,
    Iterable<String> features = const <String>[],
    int limit = 100,
  }) async {
    final response = await _apiClient.getJson(
      '/sync/pull',
      options: await _authorizedOptions(
        queryParameters: <String, Object?>{
          'sinceVersion': sinceVersion,
          if (features.isNotEmpty) 'features': features.join(','),
          'limit': limit,
        },
      ),
    );
    return OperationalSyncPullResponse.fromJson(response.data);
  }

  @override
  Future<OperationalSyncStatusResponse> getStatus() async {
    final response = await _apiClient.getJson(
      '/sync/status',
      options: await _authorizedOptions(),
    );
    return OperationalSyncStatusResponse.fromJson(response.data);
  }

  @override
  Future<List<OperationalSyncConflict>> getConflicts({
    String status = 'OPEN',
  }) async {
    final response = await _apiClient.getJson(
      '/sync/conflicts',
      options: await _authorizedOptions(
        queryParameters: <String, Object?>{'status': status},
      ),
    );
    final items = response.data['items'];
    if (items is! List) {
      return const <OperationalSyncConflict>[];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(OperationalSyncConflict.fromJson)
        .toList(growable: false);
  }

  @override
  Future<OperationalSyncConflict> resolveConflict(
    String conflictId,
    Map<String, dynamic> resolution,
  ) async {
    final response = await _apiClient.postJson(
      '/sync/conflicts/$conflictId/resolve',
      body: <String, dynamic>{'resolution': resolution},
      options: await _authorizedOptions(),
    );
    final conflict = response.data['conflict'];
    if (conflict is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o conflito operacional em formato valido.',
      );
    }
    return OperationalSyncConflict.fromJson(conflict);
  }

  @override
  Future<void> reportDiagnostics(OperationalSyncDiagnosticReport report) async {
    final clientContext = await _tokenStorage.readClientContext();
    final body = report.toJson();
    if (clientContext != null) {
      if (_notBlank(clientContext.appVersion) &&
          !body.containsKey('appVersion')) {
        body['appVersion'] = clientContext.appVersion;
      }
      if (_notBlank(clientContext.platform) && !body.containsKey('platform')) {
        body['platform'] = clientContext.platform;
      }
    }
    await _apiClient.postJson(
      '/sync/diagnostics',
      body: body,
      options: await _authorizedOptions(),
    );
  }

  bool _notBlank(String? value) => value != null && value.trim().isNotEmpty;

  @override
  Future<List<OperationalSyncSupportCommand>> fetchSupportCommands() async {
    final response = await _apiClient.getJson(
      '/sync/support-commands',
      options: await _authorizedOptions(),
    );
    final items = response.data['items'];
    if (items is! List) {
      return const <OperationalSyncSupportCommand>[];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(OperationalSyncSupportCommand.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> completeSupportCommand(
    String commandId,
    Map<String, dynamic> result,
  ) async {
    await _apiClient.postJson(
      '/sync/support-commands/$commandId/complete',
      body: <String, dynamic>{'result': result},
      options: await _authorizedOptions(),
    );
  }

  @override
  Future<void> failSupportCommand(
    String commandId, {
    required String errorMessage,
    Map<String, dynamic> result = const <String, dynamic>{},
  }) async {
    await _apiClient.postJson(
      '/sync/support-commands/$commandId/fail',
      body: <String, dynamic>{'errorMessage': errorMessage, 'result': result},
      options: await _authorizedOptions(),
    );
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    final clientContext = await _tokenStorage.readClientContext();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar o PDV.',
      );
    }
    if (clientContext == null ||
        clientContext.clientInstanceId.trim().isEmpty) {
      throw const AuthenticationException(
        'Identificador deste aparelho ausente para sincronizar o PDV.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'X-Client-Instance-Id': clientContext.clientInstanceId,
      },
      queryParameters: queryParameters,
    );
  }
}
