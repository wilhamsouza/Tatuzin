import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/paginated_remote_fetch.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/categories_remote_datasource.dart';
import '../models/remote_category_record.dart';

class RealCategoriesRemoteDatasource implements CategoriesRemoteDatasource {
  const RealCategoriesRemoteDatasource({
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
  String get featureKey => 'categories';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/categories/health');
    return true;
  }

  @override
  Future<RemoteCategoryRecord> create(RemoteCategoryRecord record) async {
    final response = await _apiClient.postJson(
      '/categories',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final category = response.data['category'];
    if (category is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a categoria remota criada em formato valido.',
      );
    }

    return RemoteCategoryRecord.fromJson(category);
  }

  @override
  Future<void> delete(String remoteId) async {
    await _apiClient.delete(
      '/categories/$remoteId',
      options: await _authorizedOptions(),
    );
  }

  @override
  Future<RemoteCategoryRecord> fetchById(String remoteId) async {
    final response = await _apiClient.getJson(
      '/categories/$remoteId',
      options: await _authorizedOptions(),
    );

    final category = response.data['category'];
    if (category is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a categoria remota em formato valido.',
      );
    }

    return RemoteCategoryRecord.fromJson(category);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Categorias remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O cadastro de categorias continua 100% offline.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cadastro remoto',
          'sincronizacao manual',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/categories/health');
      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Categorias remotas',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de categorias pronto para push e pull manual por tenant.'
            : 'Endpoint real de categorias online. Faca login remoto para habilitar a sincronizacao manual.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'listagem remota',
          'push manual',
          'pull manual',
          'tenant',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Categorias remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'listagem remota',
          'push manual',
          'pull manual',
          'tenant',
        ],
      );
    }
  }

  @override
  Future<List<RemoteCategoryRecord>> listAll() async {
    return fetchAllPaginatedItems(
      fetchPage: ({required page, required pageSize}) async {
        return _apiClient.getJson(
          '/categories',
          options: await _authorizedOptions(
            queryParameters: <String, Object?>{
              'includeDeleted': true,
              'page': page,
              'pageSize': pageSize,
            },
          ),
        );
      },
      fromJson: RemoteCategoryRecord.fromJson,
      invalidItemsMessage:
          'A API nao retornou a lista de categorias em formato valido.',
    );
  }

  @override
  Future<RemoteCategoryRecord> update(
    String remoteId,
    RemoteCategoryRecord record,
  ) async {
    final response = await _apiClient.putJson(
      '/categories/$remoteId',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final category = response.data['category'];
    if (category is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a categoria remota atualizada em formato valido.',
      );
    }

    return RemoteCategoryRecord.fromJson(category);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar as categorias.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }
}
