import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../datasources/cash_remote_datasource.dart';
import '../models/remote_cash_event_record.dart';

class FakeCashRemoteDatasource implements CashRemoteDatasource {
  const FakeCashRemoteDatasource({
    required ApiClientContract apiClient,
    required AppEnvironment environment,
    required AppOperationalContext operationalContext,
  }) : _apiClient = apiClient,
       _environment = environment,
       _operationalContext = operationalContext;

  final ApiClientContract _apiClient;
  final AppEnvironment _environment;
  final AppOperationalContext _operationalContext;

  static final Map<String, RemoteCashEventRecord> _eventsByLocalUuid =
      <String, RemoteCashEventRecord>{};

  @override
  EndpointConfig get endpointConfig => _environment.endpointConfig;

  @override
  String get featureKey => 'cash';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    return _environment.dataMode.allowsRemoteRead;
  }

  @override
  Future<RemoteCashEventRecord> createEvent(
    RemoteCashEventRecord record,
  ) async {
    final existing = _eventsByLocalUuid[record.localUuid];
    if (existing != null) {
      return existing;
    }

    final persisted = RemoteCashEventRecord(
      remoteId: 'fake-cash-event-${_eventsByLocalUuid.length + 1}',
      localUuid: record.localUuid,
      eventType: record.eventType,
      amountCents: record.amountCents,
      paymentMethod: record.paymentMethod,
      referenceType: record.referenceType,
      referenceId: record.referenceId,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: DateTime.now(),
    );
    _eventsByLocalUuid[record.localUuid] = persisted;
    return persisted;
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    await _apiClient.getJson('/cash/health');
    final reachable = await canReachRemote();
    final isAuthenticated = _operationalContext.session.isAuthenticated;

    final summary = !reachable
        ? 'O caixa segue operando apenas sobre a base local enquanto o modo remoto estiver desligado.'
        : !isAuthenticated
        ? 'Caixa remoto fake pronto, aguardando autenticacao mock para validar sessao administrativa.'
        : 'Caixa remoto fake pronto para futura reconciliacao de sessoes e movimentos.';

    return RemoteFeatureDiagnostic(
      featureKey: featureKey,
      displayName: 'Caixa remoto',
      reachable: reachable,
      requiresAuthentication: requiresAuthentication,
      isAuthenticated: isAuthenticated,
      endpointLabel: endpointConfig.summaryLabel,
      summary: summary,
      lastCheckedAt: DateTime.now(),
      capabilities: const <String>[
        'diagnostico',
        'espelhamento de eventos',
        'idempotencia',
      ],
    );
  }
}
