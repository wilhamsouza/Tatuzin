import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/paginated_remote_fetch.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/customers_remote_datasource.dart';
import '../models/remote_customer_record.dart';

class RealCustomersRemoteDatasource implements CustomersRemoteDatasource {
  const RealCustomersRemoteDatasource({
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
  String get featureKey => 'customers';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/customers/health');
    return true;
  }

  @override
  Future<RemoteCustomerRecord> create(RemoteCustomerRecord record) async {
    final response = await _apiClient.postJson(
      '/customers',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final customer = response.data['customer'];
    if (customer is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o cliente remoto criado em formato valido.',
      );
    }

    return RemoteCustomerRecord.fromJson(customer);
  }

  @override
  Future<void> delete(String remoteId) async {
    await _apiClient.delete(
      '/customers/$remoteId',
      options: await _authorizedOptions(),
    );
  }

  @override
  Future<RemoteCustomerRecord> fetchById(String remoteId) async {
    final response = await _apiClient.getJson(
      '/customers/$remoteId',
      options: await _authorizedOptions(),
    );

    final customer = response.data['customer'];
    if (customer is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o cliente remoto em formato valido.',
      );
    }

    return RemoteCustomerRecord.fromJson(customer);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Clientes remotos',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O cadastro de clientes continua 100% offline.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cadastro remoto',
          'sincronizacao manual',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/customers/health');

      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Clientes remotos',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real de clientes pronto para push e pull manual por tenant.'
            : 'Endpoint real de clientes online. Faca login remoto para habilitar a sincronizacao manual.',
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
        displayName: 'Clientes remotos',
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
  Future<List<RemoteCustomerRecord>> listAll() async {
    return fetchAllPaginatedItems(
      fetchPage: ({required page, required pageSize}) async {
        return _apiClient.getJson(
          '/customers',
          options: await _authorizedOptions(
            queryParameters: <String, Object?>{
              'includeDeleted': true,
              'page': page,
              'pageSize': pageSize,
            },
          ),
        );
      },
      fromJson: RemoteCustomerRecord.fromJson,
      invalidItemsMessage:
          'A API nao retornou a lista de clientes em formato valido.',
    );
  }

  @override
  Future<RemoteCustomerRecord> update(
    String remoteId,
    RemoteCustomerRecord record,
  ) async {
    final response = await _apiClient.putJson(
      '/customers/$remoteId',
      body: record.toUpsertBody(),
      options: await _authorizedOptions(),
    );

    final customer = response.data['customer'];
    if (customer is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o cliente remoto atualizado em formato valido.',
      );
    }

    return RemoteCustomerRecord.fromJson(customer);
  }

  Future<ApiRequestOptions> _authorizedOptions({
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar os clientes.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      queryParameters: queryParameters,
    );
  }
}
