import '../app_context/app_operational_context.dart';
import '../config/app_data_mode.dart';
import '../config/app_environment.dart';
import '../errors/app_exceptions.dart';
import '../network/contracts/api_client_contract.dart';
import '../network/endpoint_config.dart';
import '../network/remote_feature_diagnostic.dart';
import '../session/auth_token_storage.dart';
import 'financial_events_remote_datasource.dart';
import 'remote_financial_event_record.dart';

class RealFinancialEventsRemoteDatasource
    implements FinancialEventsRemoteDatasource {
  const RealFinancialEventsRemoteDatasource({
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
  String get featureKey => 'financial_events';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/financial-events/health');
    return true;
  }

  @override
  Future<RemoteFinancialEventRecord> create(
    RemoteFinancialEventRecord record,
  ) async {
    final response = await _apiClient.postJson(
      '/financial-events',
      body: record.toCreateBody(),
      options: await _authorizedOptions(),
    );

    final event = response.data['event'];
    if (event is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o evento financeiro em formato valido.',
      );
    }

    return RemoteFinancialEventRecord.fromJson(event);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Eventos financeiros',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. Os eventos financeiros remotos continuam em espera.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'eventos financeiros',
          'idempotencia por localUuid',
          'tenant',
        ],
      );
    }

    try {
      await _apiClient.getJson('/financial-events/health');
      final isAuthenticated = _operationalContext.session.isRemoteAuthenticated;
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Eventos financeiros',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: isAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: isAuthenticated
            ? 'Endpoint real pronto para receber cancelamentos de venda e pagamentos de fiado como espelho remoto.'
            : 'Endpoint real online. Faca login remoto para habilitar o espelhamento de eventos financeiros.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cancelamento de venda',
          'pagamento de fiado',
          'espelho local-first',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Eventos financeiros',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'cancelamento de venda',
          'pagamento de fiado',
          'espelho local-first',
        ],
      );
    }
  }

  @override
  Future<List<RemoteFinancialEventRecord>> listAll() async {
    final response = await _apiClient.getJson(
      '/financial-events',
      options: await _authorizedOptions(),
    );

    final items = response.data['items'];
    if (items is! List) {
      throw const NetworkRequestException(
        'A API nao retornou a lista de eventos financeiros em formato valido.',
      );
    }

    return items
        .whereType<Map<String, dynamic>>()
        .map(RemoteFinancialEventRecord.fromJson)
        .toList();
  }

  Future<ApiRequestOptions> _authorizedOptions() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar os eventos financeiros.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
  }
}
