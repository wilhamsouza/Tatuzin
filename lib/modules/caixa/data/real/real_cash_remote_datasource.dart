import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/cash_remote_datasource.dart';
import '../models/remote_cash_event_record.dart';

class RealCashRemoteDatasource implements CashRemoteDatasource {
  const RealCashRemoteDatasource({
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
  String get featureKey => 'cash';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/cash/health');
    return true;
  }

  @override
  Future<RemoteCashEventRecord> createEvent(
    RemoteCashEventRecord record,
  ) async {
    final response = await _apiClient.postJson(
      '/cash/events',
      body: record.toCreateBody(),
      options: await _authorizedOptions(),
    );

    final event = response.data['event'];
    if (event is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o evento de caixa em formato valido.',
      );
    }

    return RemoteCashEventRecord.fromJson(event);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Caixa remoto',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. O caixa segue 100% local, com espelhamento remoto apenas quando a fila financeira for acionada.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de eventos',
          'tenant',
          'idempotencia',
        ],
      );
    }

    try {
      await _apiClient.getJson('/cash/health');
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Caixa remoto',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: _operationalContext.session.isRemoteAuthenticated
            ? 'Endpoint real pronto para espelhar eventos de caixa, sem recalcular saldo.'
            : 'Endpoint real de caixa online. Faca login remoto para habilitar o espelhamento financeiro.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de caixa',
          'tenant',
          'idempotencia',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Caixa remoto',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de caixa',
          'tenant',
          'idempotencia',
        ],
      );
    }
  }

  Future<ApiRequestOptions> _authorizedOptions() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationException(
        'Faca login remoto para sincronizar os eventos de caixa.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
  }
}
