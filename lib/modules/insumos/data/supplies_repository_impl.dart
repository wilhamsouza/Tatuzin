import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_action_result.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_error_info.dart';
import '../../../app/core/sync/sync_error_type.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_remote_identity_recovery.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/supply.dart';
import '../domain/entities/supply_cost_history_entry.dart';
import '../domain/entities/supply_inventory.dart';
import '../domain/repositories/supply_repository.dart';
import 'datasources/supplies_remote_datasource.dart';
import 'models/remote_supply_record.dart';
import 'models/supply_sync_payload.dart';
import 'sqlite_supply_repository.dart';

class SuppliesRepositoryImpl implements SupplyRepository, SyncFeatureProcessor {
  const SuppliesRepositoryImpl({
    required SqliteSupplyRepository localRepository,
    required SuppliesRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteSupplyRepository _localRepository;
  final SuppliesRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteSupplyRepository.featureKey;

  @override
  String get displayName => 'Insumos';

  @override
  Future<int> create(SupplyInput input) async {
    if (_shouldUseErpRemoteWrite) {
      try {
        final remote = await _remoteDatasource
            .create(_remoteSupplyFromInput(input))
            .timeout(const Duration(seconds: 15));
        return _cacheAndResolveRemoteSupply(remote);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Insumos ERP server-first falhou ao criar na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.create(input);
  }

  @override
  Future<void> deactivate(int id) async {
    if (_shouldUseErpRemoteWrite) {
      final supply = await _localRepository
          .findSupplyForSync(id)
          .timeout(const Duration(seconds: 8));
      if (supply?.remoteId == null) {
        throw const ValidationException(
          'Insumo ainda nao possui vinculo remoto para desativacao server-first.',
        );
      }

      try {
        final remote = await _remoteDatasource
            .update(
              supply!.remoteId!,
              RemoteSupplyRecord.fromSyncPayload(supply).copyWithInactive(),
            )
            .timeout(const Duration(seconds: 15));
        await _localRepository.applyPushResult(supply: supply, remote: remote);
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Insumos ERP server-first falhou ao desativar na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.deactivate(id);
  }

  @override
  Future<Supply?> findById(int id) async {
    final local = await _localRepository
        .findById(id)
        .timeout(const Duration(seconds: 8));
    final syncPayload = await _localRepository
        .findSupplyForSync(id)
        .timeout(const Duration(seconds: 8));
    if (!_shouldUseErpRemoteRead || syncPayload?.remoteId == null) {
      return local;
    }

    try {
      final remote = await _remoteDatasource
          .fetchById(syncPayload!.remoteId!)
          .timeout(const Duration(seconds: 15));
      return _cacheAndFindRemoteSupply(remote);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Insumos ERP server-first falhou no detalhe; usando cache local.',
        error: error,
        stackTrace: stackTrace,
      );
      return local;
    }
  }

  @override
  Future<List<SupplyInventoryOverview>> listInventoryOverview({
    String query = '',
  }) {
    return _localRepository.listInventoryOverview(query: query);
  }

  @override
  Future<List<SupplyInventoryMovement>> listInventoryMovements({
    int? supplyId,
    SupplyInventorySourceType? sourceType,
    DateTime? occurredFrom,
    DateTime? occurredTo,
    int limit = 200,
  }) {
    return _localRepository.listInventoryMovements(
      supplyId: supplyId,
      sourceType: sourceType,
      occurredFrom: occurredFrom,
      occurredTo: occurredTo,
      limit: limit,
    );
  }

  @override
  Future<List<SupplyReorderSuggestion>> listReorderSuggestions({
    String query = '',
    SupplyReorderFilter filter = SupplyReorderFilter.all,
  }) {
    return _localRepository.listReorderSuggestions(
      query: query,
      filter: filter,
    );
  }

  @override
  Future<SupplyInventoryConsistencyReport> verifyInventoryConsistency({
    Iterable<int>? supplyIds,
    bool repair = true,
  }) {
    return _localRepository.verifyInventoryConsistency(
      supplyIds: supplyIds,
      repair: repair,
    );
  }

  @override
  Future<List<SupplyCostHistoryEntry>> listCostHistory({
    required int supplyId,
    int limit = 20,
  }) {
    return _localRepository.listCostHistory(supplyId: supplyId, limit: limit);
  }

  @override
  Future<List<Supply>> search({
    String query = '',
    bool activeOnly = false,
  }) async {
    if (_shouldUseErpRemoteRead) {
      try {
        final remoteSupplies = await _remoteDatasource.listAll().timeout(
          const Duration(seconds: 15),
        );
        return _cacheAndResolveRemoteSupplies(
          remoteSupplies,
          query: query,
          activeOnly: activeOnly,
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Insumos ERP server-first falhou; usando cache local com timeout.',
          error: error,
          stackTrace: stackTrace,
        );
        return _localRepository
            .search(query: query, activeOnly: activeOnly)
            .timeout(const Duration(seconds: 8));
      }
    }

    return _localRepository.search(query: query, activeOnly: activeOnly);
  }

  Future<SyncActionResult> syncNow({bool retryOnly = false}) async {
    _ensureSyncIsAllowed();

    final startedAt = DateTime.now();
    var pushedCount = 0;
    var pulledCount = 0;
    var failedCount = 0;
    String? message;

    await _localRepository.seedPendingSyncIfNeeded();
    await _remoteDatasource.canReachRemote();

    final localSupplies = await _localRepository.listForSync();
    for (final supply in localSupplies.where(
      (item) => _shouldPush(item, retryOnly: retryOnly),
    )) {
      try {
        final dependencyReason = _dependencyBlockReason(supply);
        if (dependencyReason != null) {
          await _localRepository.markSyncError(
            supply: supply,
            message: dependencyReason,
            errorType: SyncErrorType.dependency,
          );
          failedCount++;
          continue;
        }

        final conflict = await _detectConflict(supply);
        if (conflict != null) {
          await _localRepository.markConflict(
            supply: supply,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          failedCount++;
          continue;
        }

        final persisted = await _pushSupply(supply);
        await _localRepository.applyPushResult(
          supply: supply,
          remote: persisted,
        );
        pushedCount++;
      } on NetworkRequestException catch (error) {
        final canRecover =
            supply.remoteId != null &&
            SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
        if (canRecover) {
          await _localRepository.recoverMissingRemoteIdentity(supply: supply);
          failedCount++;
          continue;
        }

        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          supply: supply,
          message: syncError.message,
          errorType: syncError.type,
        );
      } catch (error) {
        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          supply: supply,
          message: syncError.message,
          errorType: syncError.type,
        );
      }
    }

    try {
      pulledCount = await pullRemoteSnapshot();
    } catch (error) {
      failedCount++;
      message =
          'Falha ao atualizar o espelho remoto de insumos: ${resolveSyncError(error).message}';
    }

    final consolidated = await _localRepository.listForSync();
    final syncedCount = consolidated
        .where((supply) => supply.syncStatus == SyncStatus.synced)
        .length;

    return SyncActionResult(
      featureKey: featureKey,
      displayName: displayName,
      pushedCount: pushedCount,
      pulledCount: pulledCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      message:
          message ??
          (failedCount == 0
              ? 'Insumos sincronizados com sucesso.'
              : 'Sincronizacao de insumos concluida com falhas parciais.'),
    );
  }

  @override
  Future<void> update(int id, SupplyInput input) async {
    if (_shouldUseErpRemoteWrite) {
      final supply = await _localRepository
          .findSupplyForSync(id)
          .timeout(const Duration(seconds: 8));
      if (supply?.remoteId == null) {
        throw const ValidationException(
          'Insumo ainda nao possui vinculo remoto para atualizacao server-first.',
        );
      }

      try {
        final remote = await _remoteDatasource
            .update(
              supply!.remoteId!,
              _remoteSupplyFromInput(
                input,
                localUuid: supply.supplyUuid,
                remoteId: supply.remoteId!,
                createdAt: supply.createdAt,
                costHistory: supply.costHistory,
              ),
            )
            .timeout(const Duration(seconds: 15));
        await _localRepository.applyPushResult(supply: supply, remote: remote);
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Insumos ERP server-first falhou ao atualizar na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.update(id, input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _localRepository.seedPendingSyncIfNeeded();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final supply = await _localRepository.findSupplyForSync(item.localEntityId);
    if (supply == null) {
      return const SyncFeatureProcessResult.synced();
    }

    final dependencyReason = _dependencyBlockReason(supply);
    if (dependencyReason != null) {
      return SyncFeatureProcessResult.blocked(reason: dependencyReason);
    }

    try {
      if (item.operation == SyncQueueOperation.update &&
          supply.remoteId != null) {
        final conflict = await _detectConflict(supply);
        if (conflict != null) {
          await _localRepository.markConflict(
            supply: supply,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          return SyncFeatureProcessResult.conflict(conflict: conflict);
        }
      }

      final persisted = await _pushSupply(supply, queueItem: item);
      await _localRepository.applyPushResult(supply: supply, remote: persisted);
      return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
    } on NetworkRequestException catch (error) {
      final canRecover =
          item.operation == SyncQueueOperation.update &&
          supply.remoteId != null &&
          SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
      if (!canRecover) {
        rethrow;
      }

      await _localRepository.recoverMissingRemoteIdentity(
        supply: supply,
        queueItem: item,
      );
      return const SyncFeatureProcessResult.requeued(
        reason:
            'Registro remoto antigo nao existe mais; o insumo sera reenviado como criacao.',
      );
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remoteSupplies = await _remoteDatasource.listAll();
    for (final remoteSupply in remoteSupplies) {
      await _localRepository.upsertFromRemote(remoteSupply);
    }
    return remoteSupplies.length;
  }

  bool get _shouldUseErpRemoteRead =>
      _dataAccessPolicy.strategyFor(AppModule.erp) ==
          DataSourceStrategy.serverFirst &&
      _operationalContext.canUseCloudReads;

  bool get _shouldUseErpRemoteWrite => _shouldUseErpRemoteRead;

  Future<List<Supply>> _cacheAndResolveRemoteSupplies(
    List<RemoteSupplyRecord> remoteSupplies, {
    required String query,
    required bool activeOnly,
  }) async {
    final supplies = <Supply>[];
    for (final remoteSupply in remoteSupplies) {
      final supply = await _cacheAndFindRemoteSupply(remoteSupply);
      if (supply != null &&
          (!activeOnly || supply.isActive) &&
          _matchesQuery(supply, query)) {
        supplies.add(supply);
      }
    }
    supplies.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return supplies;
  }

  Future<int> _cacheAndResolveRemoteSupply(RemoteSupplyRecord remote) async {
    final supply = await _cacheAndFindRemoteSupply(remote);
    if (supply == null) {
      throw const NetworkRequestException(
        'Insumo remoto salvo, mas o cache local nao retornou o espelho.',
      );
    }
    return supply.id;
  }

  Future<Supply?> _cacheAndFindRemoteSupply(RemoteSupplyRecord remote) async {
    await _localRepository.upsertFromRemote(remote);
    return _localRepository
        .findByRemoteId(remote.remoteId)
        .timeout(const Duration(seconds: 8));
  }

  RemoteSupplyRecord _remoteSupplyFromInput(
    SupplyInput input, {
    String? localUuid,
    String remoteId = '',
    DateTime? createdAt,
    List<SupplyCostHistorySyncPayload> costHistory =
        const <SupplyCostHistorySyncPayload>[],
  }) {
    final now = DateTime.now();
    return RemoteSupplyRecord(
      remoteId: remoteId,
      localUuid: localUuid ?? IdGenerator.next(),
      remoteDefaultSupplierId: null,
      name: input.name,
      sku: input.sku,
      unitType: input.unitType,
      purchaseUnitType: input.purchaseUnitType,
      conversionFactor: input.conversionFactor,
      lastPurchasePriceCents: input.lastPurchasePriceCents,
      averagePurchasePriceCents: input.averagePurchasePriceCents,
      currentStockMil: input.currentStockMil,
      minimumStockMil: input.minimumStockMil,
      isActive: input.isActive,
      createdAt: createdAt ?? now,
      updatedAt: now,
      deletedAt: input.isActive ? null : now,
      costHistory: costHistory
          .map(RemoteSupplyCostHistoryRecord.fromSyncPayload)
          .toList(growable: false),
    );
  }

  bool _matchesQuery(Supply supply, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return supply.name.toLowerCase().contains(normalized) ||
        (supply.sku?.toLowerCase().contains(normalized) ?? false) ||
        (supply.defaultSupplierName?.toLowerCase().contains(normalized) ??
            false);
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual de insumos.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os insumos.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  bool _shouldPush(SupplySyncPayload supply, {required bool retryOnly}) {
    if (retryOnly) {
      return supply.syncStatus == SyncStatus.pendingUpload ||
          supply.syncStatus == SyncStatus.pendingUpdate ||
          supply.syncStatus == SyncStatus.syncError;
    }

    return supply.remoteId == null ||
        supply.syncStatus == SyncStatus.localOnly ||
        supply.syncStatus == SyncStatus.pendingUpload ||
        supply.syncStatus == SyncStatus.pendingUpdate ||
        supply.syncStatus == SyncStatus.syncError;
  }

  String? _dependencyBlockReason(SupplySyncPayload supply) {
    if (supply.defaultSupplierLocalId != null &&
        (supply.defaultSupplierRemoteId == null ||
            supply.defaultSupplierRemoteId!.isEmpty)) {
      return 'Insumo ainda nao pode subir porque o fornecedor padrao remoto ainda nao foi recriado.';
    }

    return null;
  }

  Future<SyncConflictInfo?> _detectConflict(SupplySyncPayload supply) async {
    final lastSyncedAt = supply.lastSyncedAt;
    final remoteId = supply.remoteId;
    if (lastSyncedAt == null || remoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(remoteId);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = supply.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason: 'Insumo alterado localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: supply.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }

  Future<RemoteSupplyRecord> _pushSupply(
    SupplySyncPayload supply, {
    SyncQueueItem? queueItem,
  }) async {
    final remoteRecord = RemoteSupplyRecord.fromSyncPayload(supply);
    final remoteId = supply.remoteId ?? queueItem?.remoteId;
    return (remoteId == null ||
            queueItem?.operation == SyncQueueOperation.create)
        ? _remoteDatasource.create(remoteRecord)
        : _remoteDatasource.update(remoteId, remoteRecord);
  }
}
