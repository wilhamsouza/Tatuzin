import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/paginated_remote_fetch.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/utils/app_logger.dart';
import '../datasources/products_remote_datasource.dart';
import '../models/remote_product_record.dart';

class RealProductsRemoteDatasource implements ProductsRemoteDatasource {
  const RealProductsRemoteDatasource({
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
  String get featureKey => 'products';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/products/health');
    return true;
  }

  @override
  Future<RemoteProductRecord> create(RemoteProductRecord record) async {
    final body = record.toUpsertBody();
    AppLogger.info('[ProdutosAPI] create payload=${_safePayloadForLog(body)}');
    final response = await _apiClient.postJson(
      '/products',
      body: body,
      options: await _authorizedOptions(),
    );

    final product = response.data['product'];
    if (product is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o produto remoto criado em formato valido.',
      );
    }

    return RemoteProductRecord.fromJson(product);
  }

  @override
  Future<void> delete(String remoteId) async {
    await _apiClient.delete(
      '/products/$remoteId',
      options: await _authorizedOptions(),
    );
  }

  @override
  Future<RemoteProductRecord> fetchById(String remoteId) async {
    final response = await _apiClient.getJson(
      '/products/$remoteId',
      options: await _authorizedOptions(),
    );

    final product = response.data['product'];
    if (product is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o produto remoto em formato valido.',
      );
    }

    return RemoteProductRecord.fromJson(product);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Produtos remotos',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O cadastro de produtos continua 100% offline.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cadastro remoto',
          'sincronizacao manual',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/products/health');

      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Produtos remotos',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de produtos pronto para push e pull manual por tenant.'
            : 'Endpoint real de produtos online. Faca login remoto para habilitar a sincronizacao manual.',
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
        displayName: 'Produtos remotos',
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
  Future<List<RemoteProductRecord>> listAll() async {
    return fetchAllPaginatedItems(
      fetchPage: ({required page, required pageSize}) async {
        return _apiClient.getJson(
          '/products',
          options: await _authorizedOptions(
            queryParameters: <String, Object?>{
              'includeDeleted': true,
              'page': page,
              'pageSize': pageSize,
            },
          ),
        );
      },
      fromJson: RemoteProductRecord.fromJson,
      invalidItemsMessage:
          'A API nao retornou a lista de produtos em formato valido.',
    );
  }

  @override
  Future<RemoteProductRecord> update(
    String remoteId,
    RemoteProductRecord record,
  ) async {
    final response = await _apiClient.putJson(
      '/products/$remoteId',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final product = response.data['product'];
    if (product is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o produto remoto atualizado em formato valido.',
      );
    }

    return RemoteProductRecord.fromJson(product);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar os produtos.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }

  Map<String, Object?> _safePayloadForLog(Map<String, dynamic> body) {
    return <String, Object?>{
      'name': body['name'],
      'description_present': (body['description'] as String?)?.isNotEmpty,
      'categoryId': body['categoryId'],
      'unitMeasure': body['unitMeasure'],
      'productType': body['productType'],
      'niche': body['niche'],
      'catalogType': body['catalogType'],
      'barcode': body['barcode'],
      'costPriceCents': body['costPriceCents'],
      'manualCostCents': body['manualCostCents'],
      'costSource': body['costSource'],
      'lastCostUpdatedAt': body['lastCostUpdatedAt'],
      'salePriceCents': body['salePriceCents'],
      'stockMil': body['stockMil'],
      'isActive': body['isActive'],
      'deletedAt': body['deletedAt'],
      'variants': (body['variants'] as List<dynamic>? ?? const [])
          .map((variant) {
            if (variant is! Map<String, dynamic>) {
              return variant;
            }
            return <String, Object?>{
              'sku': variant['sku'],
              'colorLabel': variant['colorLabel'],
              'sizeLabel': variant['sizeLabel'],
              'priceAdditionalCents': variant['priceAdditionalCents'],
              'stockMil': variant['stockMil'],
              'sortOrder': variant['sortOrder'],
              'isActive': variant['isActive'],
            };
          })
          .toList(growable: false),
      'modifierGroupCount':
          (body['modifierGroups'] as List<dynamic>? ?? const []).length,
    };
  }
}
