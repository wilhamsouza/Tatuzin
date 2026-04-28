import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/cost_entry.dart';
import '../domain/entities/cost_overview.dart';
import '../domain/entities/cost_status.dart';
import '../domain/entities/cost_type.dart';
import '../domain/repositories/cost_repository.dart';
import 'datasources/costs_remote_datasource.dart';
import 'models/remote_cost_record.dart';
import 'sqlite_cost_repository.dart';

class CostRepositoryImpl implements CostRepository {
  const CostRepositoryImpl({
    required SqliteCostRepository localRepository,
    CostsRemoteDatasource? remoteDatasource,
    AppOperationalContext? operationalContext,
    DataAccessPolicy? dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteCostRepository _localRepository;
  final CostsRemoteDatasource? _remoteDatasource;
  final AppOperationalContext? _operationalContext;
  final DataAccessPolicy? _dataAccessPolicy;

  static const bool hasCompatibleRemoteCostContract = true;

  @override
  Future<CostEntry> cancelCost({required int costId, String? notes}) {
    if (_shouldUseRemoteWrite) {
      return _cancelRemoteFirst(costId: costId, notes: notes);
    }
    return _localRepository
        .cancelCost(costId: costId, notes: notes)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<int> createCost(CreateCostInput input) {
    if (_shouldUseRemoteWrite) {
      return _createRemoteFirst(input);
    }
    return _localRepository
        .createCost(input)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostEntry> fetchCost(int costId) {
    return _localRepository
        .fetchCost(costId)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostOverview> fetchOverview() {
    if (_shouldUseRemoteRead) {
      return _fetchOverviewRemoteFirst();
    }
    return _localRepository.fetchOverview().timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostEntry> markCostPaid(MarkCostPaidInput input) {
    if (_shouldUseRemoteWrite) {
      return _markPaidRemoteFirst(input);
    }
    return _localRepository
        .markCostPaid(input)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<List<CostEntry>> searchCosts({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) {
    if (_shouldUseRemoteRead) {
      return _searchCostsRemoteFirst(
        type: type,
        query: query,
        status: status,
        from: from,
        to: to,
        overdueOnly: overdueOnly,
      );
    }
    return _localRepository
        .searchCosts(
          type: type,
          query: query,
          status: status,
          from: from,
          to: to,
          overdueOnly: overdueOnly,
        )
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<CostEntry> updateCost({
    required int costId,
    required UpdateCostInput input,
  }) {
    if (_shouldUseRemoteWrite) {
      return _updateRemoteFirst(costId: costId, input: input);
    }
    return _localRepository
        .updateCost(costId: costId, input: input)
        .timeout(const Duration(seconds: 8));
  }

  bool get _shouldUseRemoteRead {
    final policy = _dataAccessPolicy;
    final context = _operationalContext;
    return _remoteDatasource != null &&
        policy != null &&
        context != null &&
        policy.strategyFor(AppModule.erp) == DataSourceStrategy.serverFirst &&
        context.canUseCloudReads;
  }

  bool get _shouldUseRemoteWrite => _shouldUseRemoteRead;

  Future<CostOverview> _fetchOverviewRemoteFirst() async {
    try {
      AppLogger.info('[Custos] remote summary started');
      final summary = await _remoteDatasource!.fetchSummary().timeout(
        const Duration(seconds: 15),
      );
      AppLogger.info('[Custos] remote summary finished');
      return summary.toOverview();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Falha ao carregar resumo de custos remoto. Usando cache local.',
        error: error,
        stackTrace: stackTrace,
      );
      return _localRepository.fetchOverview().timeout(
        const Duration(seconds: 8),
      );
    }
  }

  Future<List<CostEntry>> _searchCostsRemoteFirst({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) async {
    try {
      AppLogger.info('[Custos] remote list started');
      final remoteCosts = await _remoteDatasource!
          .list(
            type: type,
            query: query,
            status: status,
            from: from,
            to: to,
            overdueOnly: overdueOnly,
          )
          .timeout(const Duration(seconds: 15));
      final cached = <CostEntry>[];
      for (final remote in remoteCosts) {
        cached.add(await _localRepository.upsertFromRemote(remote));
      }
      AppLogger.info('[Custos] remote list finished: ${cached.length} costs');
      return cached;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Falha ao carregar custos remotos. Usando cache local.',
        error: error,
        stackTrace: stackTrace,
      );
      return _localRepository
          .searchCosts(
            type: type,
            query: query,
            status: status,
            from: from,
            to: to,
            overdueOnly: overdueOnly,
          )
          .timeout(const Duration(seconds: 8));
    }
  }

  Future<int> _createRemoteFirst(CreateCostInput input) async {
    final remote = await _remoteDatasource!
        .create(
          RemoteCostRecord.fromCreateInput(
            localUuid: IdGenerator.next(),
            input: input,
          ),
        )
        .timeout(const Duration(seconds: 15));
    final cached = await _localRepository.upsertFromRemote(remote);
    return cached.id;
  }

  Future<CostEntry> _updateRemoteFirst({
    required int costId,
    required UpdateCostInput input,
  }) async {
    final local = await _localRepository.fetchCost(costId);
    final remoteId = await _ensureRemoteCostForLocal(local);
    final remote = await _remoteDatasource!
        .update(remoteId: remoteId, input: input)
        .timeout(const Duration(seconds: 15));
    return _localRepository.upsertFromRemote(remote);
  }

  Future<CostEntry> _markPaidRemoteFirst(MarkCostPaidInput input) async {
    final local = await _localRepository.fetchCost(input.costId);
    final remoteId = await _ensureRemoteCostForLocal(local);
    final remote = await _remoteDatasource!
        .pay(remoteId: remoteId, input: input)
        .timeout(const Duration(seconds: 15));
    return _localRepository.upsertFromRemote(remote);
  }

  Future<CostEntry> _cancelRemoteFirst({
    required int costId,
    String? notes,
  }) async {
    final local = await _localRepository.fetchCost(costId);
    final remoteId = await _ensureRemoteCostForLocal(local);
    final remote = await _remoteDatasource!
        .cancel(remoteId: remoteId, notes: notes)
        .timeout(const Duration(seconds: 15));
    return _localRepository.upsertFromRemote(remote);
  }

  Future<String> _ensureRemoteCostForLocal(CostEntry local) async {
    final remoteId = local.remoteId;
    if (remoteId != null && remoteId.trim().isNotEmpty) {
      return remoteId;
    }

    final remote = await _remoteDatasource!
        .create(
          RemoteCostRecord.fromCreateInput(
            localUuid: local.uuid,
            input: CreateCostInput(
              description: local.description,
              type: local.type,
              category: local.category,
              amountCents: local.amountCents,
              referenceDate: local.referenceDate,
              notes: local.notes,
              isRecurring: local.isRecurring,
            ),
          ),
        )
        .timeout(const Duration(seconds: 15));
    final cached = await _localRepository.upsertFromRemote(remote);
    return cached.remoteId ?? remote.remoteId;
  }
}
