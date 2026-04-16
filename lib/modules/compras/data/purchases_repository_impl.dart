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
import '../domain/entities/purchase.dart';
import '../domain/entities/purchase_detail.dart';
import '../domain/entities/purchase_item.dart';
import '../domain/entities/purchase_payment.dart';
import '../domain/entities/purchase_status.dart';
import '../domain/repositories/purchase_repository.dart';
import 'datasources/purchases_remote_datasource.dart';
import 'models/purchase_sync_payload.dart';
import 'models/remote_purchase_record.dart';
import 'sqlite_purchase_repository.dart';

class PurchasesRepositoryImpl
    implements PurchaseRepository, SyncFeatureProcessor {
  const PurchasesRepositoryImpl({
    required SqlitePurchaseRepository localRepository,
    required PurchasesRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqlitePurchaseRepository _localRepository;
  final PurchasesRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqlitePurchaseRepository.featureKey;

  @override
  String get displayName => 'Compras';

  @override
  Future<void> cancel(int purchaseId, {String? reason}) {
    return _localRepository.cancel(purchaseId, reason: reason);
  }

  @override
  Future<int> create(PurchaseUpsertInput input) {
    return _localRepository.create(input);
  }

  @override
  Future<PurchaseDetail> fetchDetail(int purchaseId) {
    return _localRepository.fetchDetail(purchaseId);
  }

  @override
  Future<PurchaseDetail> registerPayment(PurchasePaymentInput input) {
    return _localRepository.registerPayment(input);
  }

  @override
  Future<List<Purchase>> search({
    String query = '',
    PurchaseStatus? status,
    int? supplierId,
  }) {
    return _localRepository.search(
      query: query,
      status: status,
      supplierId: supplierId,
    );
  }

  Future<SyncActionResult> syncNow({bool retryOnly = false}) async {
    _ensureSyncIsAllowed();

    final startedAt = DateTime.now();
    var pushedCount = 0;
    var pulledCount = 0;
    var failedCount = 0;
    String? message;

    await _localRepository.seedPendingSupplyPurchaseSyncIfNeeded();
    await _remoteDatasource.canReachRemote();

    final localPurchases = await _localRepository.listForSync();
    for (final purchase in localPurchases.where(
      (purchase) => _shouldPush(purchase, retryOnly: retryOnly),
    )) {
      final syncPayload = await _localRepository.findPurchaseForSync(
        purchase.id,
      );
      if (syncPayload == null) {
        continue;
      }

      try {
        final dependencyReason = _dependencyReason(syncPayload);
        if (dependencyReason != null) {
          await _localRepository.markSyncError(
            purchase: syncPayload,
            message: dependencyReason,
            errorType: SyncErrorType.dependency,
          );
          failedCount++;
          continue;
        }

        final conflict = await _detectConflict(syncPayload);
        if (conflict != null) {
          await _localRepository.markConflict(
            purchase: syncPayload,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          failedCount++;
          continue;
        }

        final persisted = await _pushPurchase(syncPayload);

        await _localRepository.applyPushResult(
          purchase: syncPayload,
          remote: persisted,
        );
        pushedCount++;
      } catch (error) {
        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          purchase: syncPayload,
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
          'Falha ao atualizar o estado remoto consolidado: ${resolveSyncError(error).message}';
    }

    final consolidated = await _localRepository.listForSync();
    final syncedCount = consolidated
        .where((purchase) => purchase.syncStatus == SyncStatus.synced)
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
              ? 'Compras sincronizadas com sucesso.'
              : 'Sincronizacao de compras concluida com falhas parciais.'),
    );
  }

  @override
  Future<void> update(int id, PurchaseUpsertInput input) {
    return _localRepository.update(id, input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _localRepository.seedPendingSupplyPurchaseSyncIfNeeded();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final purchase = await _localRepository.findPurchaseForSync(
      item.localEntityId,
    );
    if (purchase == null) {
      return const SyncFeatureProcessResult.synced();
    }

    final dependencyReason = _dependencyReason(purchase);
    if (dependencyReason != null) {
      return SyncFeatureProcessResult.blocked(reason: dependencyReason);
    }

    if (item.operation == SyncQueueOperation.update &&
        purchase.remoteId != null) {
      final conflict = await _detectConflict(purchase);
      if (conflict != null) {
        await _localRepository.markConflict(
          purchase: purchase,
          message: conflict.reason,
          detectedAt: DateTime.now(),
        );
        return SyncFeatureProcessResult.conflict(conflict: conflict);
      }
    }

    final persisted = await _pushPurchase(purchase, queueItem: item);

    await _localRepository.applyPushResult(
      purchase: purchase,
      remote: persisted,
    );
    return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remotePurchases = await _remoteDatasource.listAll();
    for (final remotePurchase in remotePurchases) {
      await _localRepository.reconcileRemoteSnapshot(remotePurchase);
    }
    return remotePurchases.length;
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual de compras.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar as compras.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  bool _shouldPush(Purchase purchase, {required bool retryOnly}) {
    if (retryOnly) {
      return purchase.syncStatus == SyncStatus.pendingUpload ||
          purchase.syncStatus == SyncStatus.pendingUpdate ||
          purchase.syncStatus == SyncStatus.syncError;
    }

    return purchase.remoteId == null ||
        purchase.syncStatus == SyncStatus.localOnly ||
        purchase.syncStatus == SyncStatus.pendingUpload ||
        purchase.syncStatus == SyncStatus.pendingUpdate ||
        purchase.syncStatus == SyncStatus.syncError;
  }

  String? _dependencyReason(PurchaseSyncPayload purchase) {
    if (purchase.supplierRemoteId == null ||
        purchase.supplierRemoteId!.isEmpty) {
      return 'Compra ainda nao pode subir porque o fornecedor remoto ainda nao foi recriado.';
    }

    for (final item in purchase.items) {
      if (item.itemType == PurchaseItemType.supply) {
        if (item.supplyRemoteId == null || item.supplyRemoteId!.isEmpty) {
          return 'Compra ainda nao pode subir porque o insumo "${item.itemNameSnapshot}" ainda nao foi recriado no backend.';
        }
        continue;
      }
      if (item.productRemoteId == null || item.productRemoteId!.isEmpty) {
        return 'Compra ainda nao pode subir porque o produto "${item.itemNameSnapshot}" ainda nao foi recriado no backend.';
      }
    }

    return null;
  }

  Future<SyncConflictInfo?> _detectConflict(
    PurchaseSyncPayload purchase,
  ) async {
    final lastSyncedAt = purchase.lastSyncedAt;
    final remoteId = purchase.remoteId;
    if (lastSyncedAt == null || remoteId == null) {
      return null;
    }

    final remote = await _fetchRemoteForConflict(remoteId);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = purchase.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason: 'Compra alterada localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: purchase.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }

  Future<RemotePurchaseRecord> _pushPurchase(
    PurchaseSyncPayload purchase, {
    SyncQueueItem? queueItem,
  }) async {
    final remoteRecord = RemotePurchaseRecord.fromSyncPayload(purchase);
    final remoteId = purchase.remoteId ?? queueItem?.remoteId;
    try {
      return (remoteId == null ||
              queueItem?.operation == SyncQueueOperation.create)
          ? await _remoteDatasource.create(remoteRecord)
          : await _remoteDatasource.update(remoteId, remoteRecord);
    } on NetworkRequestException catch (error) {
      if (!SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error)) {
        rethrow;
      }

      throw const ValidationException(
        'Compra ainda nao pode subir porque o registro remoto antigo nao existe mais. Recrie primeiro fornecedor, produtos e insumos remotos e depois tente reenviar a compra.',
      );
    }
  }

  Future<RemotePurchaseRecord> _fetchRemoteForConflict(String remoteId) async {
    try {
      return await _remoteDatasource.fetchById(remoteId);
    } on NetworkRequestException catch (error) {
      if (!SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error)) {
        rethrow;
      }

      throw const ValidationException(
        'Registro remoto antigo da compra nao existe mais. A recuperacao automatica nao e aplicada em compras; recrie primeiro fornecedor, produtos e insumos remotos e revise o payload.',
      );
    }
  }
}
