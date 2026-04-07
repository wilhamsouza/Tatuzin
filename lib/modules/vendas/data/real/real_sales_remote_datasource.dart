import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/sales_remote_datasource.dart';
import '../models/remote_sale_record.dart';

class RealSalesRemoteDatasource implements SalesRemoteDatasource {
  const RealSalesRemoteDatasource({
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
  String get featureKey => 'sales';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/sales/health');
    return true;
  }

  @override
  Future<RemoteSaleRecord> cancel({
    required String remoteSaleId,
    required String localUuid,
    required DateTime canceledAt,
  }) async {
    final response = await _apiClient.putJson(
      '/sales/$remoteSaleId/cancel',
      body: <String, dynamic>{
        'localUuid': localUuid,
        'canceledAt': canceledAt.toIso8601String(),
      },
      options: await _authorizedOptions(),
    );

    final sale = response.data['sale'];
    if (sale is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o cancelamento da venda em formato valido.',
      );
    }

    return RemoteSaleRecord.fromJson(sale);
  }

  @override
  Future<RemoteSaleRecord> create(RemoteSaleRecord record) async {
    final response = await _apiClient.postJson(
      '/sales',
      body: record.toCreateBody(),
      options: await _authorizedOptions(),
    );

    final sale = response.data['sale'];
    if (sale is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a venda remota em formato valido.',
      );
    }

    return RemoteSaleRecord.fromJson(sale);
  }

  @override
  Future<RemoteSaleRecord> fetchById(String remoteId) async {
    final response = await _apiClient.getJson(
      '/sales/$remoteId',
      options: await _authorizedOptions(),
    );

    final sale = response.data['sale'];
    if (sale is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou a venda remota em formato valido.',
      );
    }

    return RemoteSaleRecord.fromJson(sale);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Vendas remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O espelhamento remoto de vendas continua em espera.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de vendas',
          'idempotencia',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/sales/health');
      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Vendas remotas',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de vendas pronto para espelhar eventos locais por tenant.'
            : 'Endpoint real de vendas online. Faca login remoto para habilitar a fila de espelhamento.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento local-first',
          'idempotencia por localUuid',
          'tenant',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Vendas remotas',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento local-first',
          'idempotencia por localUuid',
          'tenant',
        ],
      );
    }
  }

  @override
  Future<List<RemoteSaleRecord>> listAll() async {
    final response = await _apiClient.getJson(
      '/sales',
      options: await _authorizedOptions(),
    );

    final items = response.data['items'];
    if (items is! List) {
      throw const NetworkRequestException(
        'A API nao retornou a lista de vendas em formato valido.',
      );
    }

    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteSaleRecord.fromJson)
        .toList();
  }

  Future<ApiRequestOptions> _authorizedOptions() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar as vendas.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
  }
}
