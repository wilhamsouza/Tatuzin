import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/paginated_remote_fetch.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/product_recipes_remote_datasource.dart';
import '../models/remote_product_recipe_record.dart';

class RealProductRecipesRemoteDatasource
    implements ProductRecipesRemoteDatasource {
  const RealProductRecipesRemoteDatasource({
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
  String get featureKey => 'product_recipes';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/product-recipes/health');
    return true;
  }

  @override
  Future<void> delete(String productRemoteId) async {
    await _apiClient.delete(
      '/product-recipes/$productRemoteId',
      options: await _authorizedOptions(),
    );
  }

  @override
  Future<RemoteProductRecipeRecord> fetchByProductId(String productRemoteId) async {
    final response = await _apiClient.getJson(
      '/product-recipes/$productRemoteId',
      options: await _authorizedOptions(),
    );
    final recipe = response.data['recipe'];
    if (recipe is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a ficha tecnica remota em formato valido.',
      );
    }
    return RemoteProductRecipeRecord.fromJson(recipe);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Fichas tecnicas remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O espelho remoto da ficha tecnica permanece opcional.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelho por produto',
          'dependencia de insumos',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/product-recipes/health');
      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Fichas tecnicas remotas',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de ficha tecnica pronto para espelhar composicao por produto.'
            : 'Endpoint real de ficha tecnica online. Faca login remoto para habilitar a sincronizacao manual.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelho por produto',
          'dependencia de insumos',
          'tenant',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Fichas tecnicas remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelho por produto',
          'dependencia de insumos',
          'tenant',
        ],
      );
    }
  }

  @override
  Future<List<RemoteProductRecipeRecord>> listAll() async {
    final items = await fetchAllPaginatedItems(
      fetchPage: ({required page, required pageSize}) async {
        return _apiClient.getJson(
          '/product-recipes',
          options: await _authorizedOptions(
            queryParameters: <String, Object?>{
              'page': page,
              'pageSize': pageSize,
            },
          ),
        );
      },
      fromJson: RemoteProductRecipeRecord.fromJson,
      invalidItemsMessage:
          'A API nao retornou a lista de fichas tecnicas em formato valido.',
    );

    return items.toList(growable: false);
  }

  @override
  Future<RemoteProductRecipeRecord> upsert(
    String productRemoteId,
    RemoteProductRecipeRecord record,
  ) async {
    final response = await _apiClient.putJson(
      '/product-recipes/$productRemoteId',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );
    final recipe = response.data['recipe'];
    if (recipe is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a ficha tecnica remota atualizada em formato valido.',
      );
    }
    return RemoteProductRecipeRecord.fromJson(recipe);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar as fichas tecnicas.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }
}
