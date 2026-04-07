import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../datasources/fiado_remote_datasource.dart';
import '../models/remote_fiado_payment_record.dart';

class RealFiadoRemoteDatasource implements FiadoRemoteDatasource {
  const RealFiadoRemoteDatasource({
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
  String get featureKey => 'fiado';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    if (!_environment.dataMode.allowsRemoteRead) {
      return false;
    }

    await _apiClient.getJson('/fiado/health');
    return true;
  }

  @override
  Future<RemoteFiadoPaymentRecord> createPayment(
    RemoteFiadoPaymentRecord record,
  ) async {
    final response = await _apiClient.postJson(
      '/fiado/payments',
      body: record.toCreateBody(),
      options: await _authorizedOptions(),
    );

    final payment = response.data['payment'];
    if (payment is! Map<String, dynamic>) {
      throw const NetworkRequestException(
        'A API nao retornou o pagamento de fiado em formato valido.',
      );
    }

    return RemoteFiadoPaymentRecord.fromJson(payment);
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    if (!_environment.dataMode.allowsRemoteRead ||
        !endpointConfig.isConfigured) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Fiado remoto',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary:
            'Modo somente local ativo. Os pagamentos continuam apenas locais ate a sincronizacao ser acionada.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de recebimentos',
          'tenant',
          'idempotencia',
        ],
      );
    }

    try {
      await _apiClient.getJson('/fiado/health');
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Fiado remoto',
        reachable: true,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: _operationalContext.session.isRemoteAuthenticated
            ? 'Endpoint real pronto para espelhar pagamentos de fiado por tenant.'
            : 'Endpoint real de fiado online. Faca login remoto para habilitar o espelhamento de pagamentos.',
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de pagamentos',
          'tenant',
          'idempotencia',
        ],
      );
    } on AppException catch (error) {
      return RemoteFeatureDiagnostic(
        featureKey: featureKey,
        displayName: 'Fiado remoto',
        reachable: false,
        requiresAuthentication: requiresAuthentication,
        isAuthenticated: _operationalContext.session.isRemoteAuthenticated,
        endpointLabel: endpointConfig.summaryLabel,
        summary: error.message,
        lastCheckedAt: DateTime.now(),
        capabilities: const <String>[
          'espelhamento de pagamentos',
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
        'Faca login remoto para sincronizar pagamentos de fiado.',
      );
    }

    return ApiRequestOptions(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
  }
}
