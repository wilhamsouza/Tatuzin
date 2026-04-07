import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/network/contracts/api_client_contract.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../datasources/sales_remote_datasource.dart';
import '../models/remote_sale_record.dart';

class FakeSalesRemoteDatasource implements SalesRemoteDatasource {
  const FakeSalesRemoteDatasource({
    required ApiClientContract apiClient,
    required AppEnvironment environment,
    required AppOperationalContext operationalContext,
  }) : _apiClient = apiClient,
       _environment = environment,
       _operationalContext = operationalContext;

  final ApiClientContract _apiClient;
  final AppEnvironment _environment;
  final AppOperationalContext _operationalContext;

  static final Map<String, RemoteSaleRecord> _recordsByLocalUuid =
      <String, RemoteSaleRecord>{};

  @override
  EndpointConfig get endpointConfig => _environment.endpointConfig;

  @override
  String get featureKey => 'sales';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async {
    return _environment.dataMode.allowsRemoteRead;
  }

  @override
  Future<RemoteSaleRecord> cancel({
    required String remoteSaleId,
    required String localUuid,
    required DateTime canceledAt,
  }) async {
    final existing = await fetchById(remoteSaleId);
    final persisted = RemoteSaleRecord(
      remoteId: existing.remoteId,
      localUuid: existing.localUuid,
      remoteCustomerId: existing.remoteCustomerId,
      receiptNumber: existing.receiptNumber,
      paymentType: existing.paymentType,
      paymentMethod: existing.paymentMethod,
      status: 'canceled',
      totalAmountCents: existing.totalAmountCents,
      totalCostCents: existing.totalCostCents,
      soldAt: existing.soldAt,
      notes: existing.notes,
      createdAt: existing.createdAt,
      updatedAt: canceledAt,
      items: existing.items,
    );
    _recordsByLocalUuid[localUuid] = persisted;
    return persisted;
  }

  @override
  Future<RemoteSaleRecord> create(RemoteSaleRecord record) async {
    final existing = _recordsByLocalUuid[record.localUuid];
    if (existing != null) {
      return existing;
    }

    final persisted = RemoteSaleRecord(
      remoteId: 'fake-sale-${_recordsByLocalUuid.length + 1}',
      localUuid: record.localUuid,
      remoteCustomerId: record.remoteCustomerId,
      receiptNumber: record.receiptNumber,
      paymentType: record.paymentType,
      paymentMethod: record.paymentMethod,
      status: record.status,
      totalAmountCents: record.totalAmountCents,
      totalCostCents: record.totalCostCents,
      soldAt: record.soldAt,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: DateTime.now(),
      items: record.items,
    );
    _recordsByLocalUuid[record.localUuid] = persisted;
    return persisted;
  }

  @override
  Future<RemoteSaleRecord> fetchById(String remoteId) async {
    for (final record in _recordsByLocalUuid.values) {
      if (record.remoteId == remoteId) {
        return record;
      }
    }

    throw const ValidationException(
      'Venda fake nao encontrada para o remoteId informado.',
    );
  }

  @override
  Future<List<RemoteSaleRecord>> listAll() async {
    final records = _recordsByLocalUuid.values.toList();
    records.sort((left, right) => right.soldAt.compareTo(left.soldAt));
    return records;
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    await _apiClient.getJson('/sales/health');
    final reachable = await canReachRemote();
    final isAuthenticated = _operationalContext.session.isAuthenticated;

    final summary = !reachable
        ? 'Modo somente local ativo. O fluxo remoto de vendas permanece em espera.'
        : !isAuthenticated
        ? 'Datasource remoto fake pronto, aguardando autenticacao mock para validar chamadas protegidas.'
        : 'Datasource remoto fake pronto para validar upload e conciliacao futura de vendas.';

    return RemoteFeatureDiagnostic(
      featureKey: featureKey,
      displayName: 'Vendas remotas',
      reachable: reachable,
      requiresAuthentication: requiresAuthentication,
      isAuthenticated: isAuthenticated,
      endpointLabel: endpointConfig.summaryLabel,
      summary: summary,
      lastCheckedAt: DateTime.now(),
      capabilities: const <String>[
        'diagnostico',
        'upload futuro',
        'cancelamento futuro',
      ],
    );
  }
}
