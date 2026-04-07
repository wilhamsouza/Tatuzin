import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/purchases_remote_datasource.dart';
import '../models/remote_purchase_record.dart';

class RealPurchasesRemoteDatasource implements PurchasesRemoteDatasource {
  const RealPurchasesRemoteDatasource({
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
  String get featureKey => 'purchases';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/purchases/health');
    return true;
  }

  @override
  Future<RemotePurchaseRecord> create(RemotePurchaseRecord record) async {
    final response = await _apiClient.postJson(
      '/purchases',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final purchase = response.data['purchase'];
    if (purchase is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a compra remota criada em formato valido.',
      );
    }

    return RemotePurchaseRecord.fromJson(purchase);
  }

  @override
  Future<RemotePurchaseRecord> fetchById(String remoteId) async {
    final response = await _apiClient.getJson(
      '/purchases/$remoteId',
      options: await _authorizedOptions(),
    );

    final purchase = response.data['purchase'];
    if (purchase is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a compra remota em formato valido.',
      );
    }

    return RemotePurchaseRecord.fromJson(purchase);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Compras remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O espelhamento remoto de compras continua em espera.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de compras',
          'itens',
          'pagamentos',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/purchases/health');
      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Compras remotas',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de compras pronto para espelhar snapshots locais por tenant.'
            : 'Endpoint real de compras online. Faca login remoto para habilitar a sincronizacao manual.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento local-first',
          'itens e pagamentos',
          'tenant',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Compras remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento local-first',
          'itens e pagamentos',
          'tenant',
        ],
      );
    }
  }

  @override
  Future<List<RemotePurchaseRecord>> listAll() async {
    final response = await _apiClient.getJson(
      '/purchases',
      options: await _authorizedOptions(),
    );

    final items = response.data['items'];
    if (items is! List) {
      throw const NetworkRequestException(
        'A API nao retornou a lista de compras em formato valido.',
      );
    }

    return items
        .whereType<Map<String, dynamic>>()
        .map(RemotePurchaseRecord.fromJson)
        .toList();
  }

  @override
  Future<RemotePurchaseRecord> update(
    String remoteId,
    RemotePurchaseRecord record,
  ) async {
    final response = await _apiClient.putJson(
      '/purchases/$remoteId',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final purchase = response.data['purchase'];
    if (purchase is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a compra remota atualizada em formato valido.',
      );
    }

    return RemotePurchaseRecord.fromJson(purchase);
  }

  Future<ApiRequestOptions> _authorizedOptions() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar as compras.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
  }
}
