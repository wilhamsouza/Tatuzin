import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/paginated_remote_fetch.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/supplies_remote_datasource.dart';
import '../models/remote_supply_record.dart';

class RealSuppliesRemoteDatasource implements SuppliesRemoteDatasource {
  const RealSuppliesRemoteDatasource({
    required ApiClientContract apiClient,
    required AuthTokenStorage tokenStorage,
    required AppEnvironment environment,
    required AppOperationalContext operationalContext,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage,
       _environment = environment,
       _operationalContext = operationalContext;

  final ApiClientContract _apiClient;
  final AuthTokenStorage _tokenStorage;
  final AppEnvironment _environment;
  final AppOperationalContext _operationalContext;

  @override
  EndpointConfig get endpointConfig => _environment.endpointConfig;

  @override
  String get featureKey => 'supplies';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/supplies/health');
    return true;
  }

  @override
  Future<RemoteSupplyRecord> create(RemoteSupplyRecord record) async {
    final response = await _apiClient.postJson(
      '/supplies',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final supply = response.data['supply'];
    if (supply is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o insumo remoto criado em formato valido.',
      );
    }

    return RemoteSupplyRecord.fromJson(supply);
  }

  @override
  Future<void> delete(String remoteId) async {
    await _apiClient.delete(
      '/supplies/$remoteId',
      options: await _authorizedOptions(),
    );
  }

  @override
  Future<RemoteSupplyRecord> fetchById(String remoteId) async {
    final response = await _apiClient.getJson(
      '/supplies/$remoteId',
      options: await _authorizedOptions(),
    );

    final supply = response.data['supply'];
    if (supply is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o insumo remoto em formato valido.',
      );
    }

    return RemoteSupplyRecord.fromJson(supply);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Insumos remotos',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O espelho remoto de insumos permanece opcional.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cadastro remoto',
          'historico de custo',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/supplies/health');
      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Insumos remotos',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de insumos pronto para espelhar cadastro e historico de custo por tenant.'
            : 'Endpoint real de insumos online. Faca login remoto para habilitar a sincronizacao manual.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cadastro remoto',
          'historico de custo',
          'tenant',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Insumos remotos',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cadastro remoto',
          'historico de custo',
          'tenant',
        ],
      );
    }
  }

  @override
  Future<List<RemoteSupplyRecord>> listAll() async {
    return fetchAllPaginatedItems(
      fetchPage: ({required page, required pageSize}) async {
        return _apiClient.getJson(
          '/supplies',
          options: await _authorizedOptions(
            queryParameters: <String, Object?>{
              'includeDeleted': true,
              'page': page,
              'pageSize': pageSize,
            },
          ),
        );
      },
      fromJson: RemoteSupplyRecord.fromJson,
      invalidItemsMessage:
          'A API nao retornou a lista de insumos em formato valido.',
    );
  }

  @override
  Future<RemoteSupplyRecord> update(
    String remoteId,
    RemoteSupplyRecord record,
  ) async {
    final response = await _apiClient.putJson(
      '/supplies/$remoteId',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final supply = response.data['supply'];
    if (supply is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o insumo remoto atualizado em formato valido.',
      );
    }

    return RemoteSupplyRecord.fromJson(supply);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar os insumos.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }
}
