import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../datasources/fiado_remote_datasource.dart';
import '../models/remote_fiado_payment_record.dart';

class FakeFiadoRemoteDatasource implements FiadoRemoteDatasource {
  const FakeFiadoRemoteDatasource({
    required ApiClientContract apiClient,
    required AppEnvironment environment,
    required AppOperationalContext operationalContext,
  }) : _apiClient = apiClient,
       _environment = environment,
       _operationalContext = operationalContext;

  final ApiClientContract _apiClient;
  final AppEnvironment _environment;
  final AppOperationalContext _operationalContext;

  static final Map<String, RemoteFiadoPaymentRecord> _paymentsByLocalUuid =
      <String, RemoteFiadoPaymentRecord>{};

  @override
  EndpointConfig get endpointConfig => _environment.endpointConfig;

  @override
  String get featureKey => 'fiado';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    return _environment.dataMode.allowsRemoteRead;
  }

  @override
  Future<RemoteFiadoPaymentRecord> createPayment(
    RemoteFiadoPaymentRecord record,
  ) async {
    final existing = _paymentsByLocalUuid[record.localUuid];
    if (existing != null) {
      return existing;
    }

    final persisted = RemoteFiadoPaymentRecord(
      remoteId: 'fake-fiado-payment-${_paymentsByLocalUuid.length + 1}',
      remoteSaleId: record.remoteSaleId,
      localUuid: record.localUuid,
      amountCents: record.amountCents,
      paymentMethod: record.paymentMethod,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: DateTime.now(),
    );
    _paymentsByLocalUuid[record.localUuid] = persisted;
    return persisted;
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    await _apiClient.getJson('/fiado/health');
    final reachable = await canReachRemote();
    final isAuthenticated = _operationalContext.session.isAuthenticated;

    final summary = !reachable
        ? 'Notas e recebimentos seguem inteiramente locais enquanto o modo remoto estiver desativado.'
        : !isAuthenticated
        ? 'Fiado remoto fake pronto, aguardando login mock para validar protecao de dados financeiros.'
        : 'Fiado remoto fake pronto para futura conciliacao de contas e recebimentos.';

    return RemoteFeatureDiagnostic(
      featureKey: featureKey,
      displayName: 'Fiado remoto',
      reachable: reachable,
      requiresAuthentication: requiresAuthentication,
      isAuthenticated: isAuthenticated,
      endpointLabel: endpointConfig.summaryLabel,
      summary: summary,
      lastCheckedAt: DateTime.now(),
      capabilities: const <String>[
        'diagnostico',
        'espelhamento de recebimentos',
        'idempotencia',
      ],
    );
  }
}
