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
  Future<void> cancel(int purchaseId, {String? reason}) async {
    if (_shouldUseErpRemoteWrite) {
      final purchase = await _localRepository
          .findPurchaseForSync(purchaseId)
          .timeout(const Duration(seconds: 8));
      final remoteId = _requireRemoteId(
        purchase,
        'Compra ainda nao possui vinculo remoto para cancelamento server-first.',
      );
      final now = DateTime.now();
      try {
        final remote = RemotePurchaseRecord.fromSyncPayload(purchase!).copyWith(
          status: PurchaseStatus.cancelada,
          canceledAt: now,
          updatedAt: now,
          notes: _mergeNotes(
            purchase.notes,
            reason == null || reason.trim().isEmpty
                ? 'Compra cancelada.'
                : 'Compra cancelada: ${reason.trim()}',
          ),
        );
        final persisted = await _remoteDatasource
            .update(remoteId, remote)
            .timeout(const Duration(seconds: 15));
        await _localRepository.cancel(purchaseId, reason: reason);
        final updated = await _localRepository
            .findPurchaseForSync(purchaseId)
            .timeout(const Duration(seconds: 8));
        if (updated != null) {
          await _localRepository.applyPushResult(
            purchase: updated,
            remote: persisted,
          );
        }
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Compras ERP server-first falhou ao cancelar na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.cancel(purchaseId, reason: reason);
  }

  @override
  Future<int> create(PurchaseUpsertInput input) async {
    if (_shouldUseErpRemoteWrite) {
      try {
        final remoteDraft = await _localRepository
            .buildRemoteRecordFromInput(input)
            .timeout(const Duration(seconds: 8));
        final persisted = await _remoteDatasource
            .create(remoteDraft)
            .timeout(const Duration(seconds: 15));
        final localId = await _localRepository
            .create(input)
            .timeout(const Duration(seconds: 8));
        final purchase = await _localRepository
            .findPurchaseForSync(localId)
            .timeout(const Duration(seconds: 8));
        if (purchase != null) {
          await _localRepository.applyPushResult(
            purchase: purchase,
            remote: persisted,
          );
        }
        return localId;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Compras ERP server-first falhou ao criar na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.create(input);
  }

  @override
  Future<PurchaseDetail> fetchDetail(int purchaseId) async {
    if (_shouldUseErpRemoteRead) {
      final local = await _localRepository
          .findById(purchaseId)
          .timeout(const Duration(seconds: 8));
      final remoteId = local?.remoteId;
      if (remoteId != null && remoteId.trim().isNotEmpty) {
        try {
          final remote = await _remoteDatasource
              .fetchById(remoteId)
              .timeout(const Duration(seconds: 15));
          final cached = await _localRepository
              .cacheRemoteSnapshot(remote)
              .timeout(const Duration(seconds: 8));
          return _localRepository
              .fetchDetail(cached?.id ?? purchaseId)
              .timeout(const Duration(seconds: 8));
        } catch (error, stackTrace) {
          AppLogger.error(
            'Compras ERP server-first falhou ao buscar detalhe remoto; usando cache local.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    return _localRepository.fetchDetail(purchaseId);
  }

  @override
  Future<PurchaseDetail> registerPayment(PurchasePaymentInput input) async {
    if (_shouldUseErpRemoteWrite) {
      final purchase = await _localRepository
          .findPurchaseForSync(input.purchaseId)
          .timeout(const Duration(seconds: 8));
      final remoteId = _requireRemoteId(
        purchase,
        'Compra ainda nao possui vinculo remoto para pagamento server-first.',
      );
      final pending = purchase!.pendingAmountCents;
      if (input.amountCents <= 0 || input.amountCents > pending) {
        throw const ValidationException(
          'Valor de pagamento invalido para a compra.',
        );
      }
      final paymentUuid = input.paymentUuid ?? IdGenerator.next();
      try {
        final remote = _remoteWithPayment(
          purchase,
          input: input,
          paymentUuid: paymentUuid,
        );
        final persisted = await _remoteDatasource
            .update(remoteId, remote)
            .timeout(const Duration(seconds: 15));
        final detail = await _localRepository
            .registerPayment(
              PurchasePaymentInput(
                purchaseId: input.purchaseId,
                amountCents: input.amountCents,
                paymentMethod: input.paymentMethod,
                paymentUuid: paymentUuid,
                notes: input.notes,
              ),
            )
            .timeout(const Duration(seconds: 8));
        final updated = await _localRepository
            .findPurchaseForSync(input.purchaseId)
            .timeout(const Duration(seconds: 8));
        if (updated != null) {
          await _localRepository.applyPushResult(
            purchase: updated,
            remote: persisted,
          );
        }
        return detail;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Compras ERP server-first falhou ao registrar pagamento na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.registerPayment(input);
  }

  @override
  Future<List<Purchase>> search({
    String query = '',
    PurchaseStatus? status,
    int? supplierId,
  }) async {
    if (_shouldUseErpRemoteRead) {
      try {
        final remotePurchases = await _remoteDatasource.listAll().timeout(
          const Duration(seconds: 15),
        );
        return _cacheAndResolveRemotePurchases(
          remotePurchases,
          query: query,
          status: status,
          supplierId: supplierId,
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Compras ERP server-first falhou; usando cache local com timeout.',
          error: error,
          stackTrace: stackTrace,
        );
        return _localRepository
            .search(query: query, status: status, supplierId: supplierId)
            .timeout(const Duration(seconds: 8));
      }
    }

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
  Future<void> update(int id, PurchaseUpsertInput input) async {
    if (_shouldUseErpRemoteWrite) {
      final purchase = await _localRepository
          .findPurchaseForSync(id)
          .timeout(const Duration(seconds: 8));
      final remoteId = _requireRemoteId(
        purchase,
        'Compra ainda nao possui vinculo remoto para atualizacao server-first.',
      );
      try {
        final remoteDraft = await _localRepository
            .buildRemoteRecordFromInput(
              input,
              remoteId: remoteId,
              localUuid: purchase!.purchaseUuid,
              createdAt: purchase.createdAt,
            )
            .timeout(const Duration(seconds: 8));
        final persisted = await _remoteDatasource
            .update(remoteId, remoteDraft)
            .timeout(const Duration(seconds: 15));
        await _localRepository
            .update(id, input)
            .timeout(const Duration(seconds: 8));
        final updated = await _localRepository
            .findPurchaseForSync(id)
            .timeout(const Duration(seconds: 8));
        if (updated != null) {
          await _localRepository.applyPushResult(
            purchase: updated,
            remote: persisted,
          );
        }
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Compras ERP server-first falhou ao atualizar na API.',
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
      await _localRepository.cacheRemoteSnapshot(remotePurchase);
    }
    return remotePurchases.length;
  }

  bool get _shouldUseErpRemoteRead =>
      _dataAccessPolicy.strategyFor(AppModule.erp) ==
          DataSourceStrategy.serverFirst &&
      _operationalContext.canUseCloudReads;

  bool get _shouldUseErpRemoteWrite => _shouldUseErpRemoteRead;

  Future<List<Purchase>> _cacheAndResolveRemotePurchases(
    List<RemotePurchaseRecord> remotePurchases, {
    required String query,
    required PurchaseStatus? status,
    required int? supplierId,
  }) async {
    final purchases = <Purchase>[];
    for (final remote in remotePurchases) {
      final purchase = await _localRepository
          .cacheRemoteSnapshot(remote)
          .timeout(const Duration(seconds: 8));
      if (purchase != null &&
          _matchesFilters(
            purchase,
            query: query,
            status: status,
            supplierId: supplierId,
          )) {
        purchases.add(purchase);
      }
    }
    purchases.sort(
      (left, right) => right.purchasedAt.compareTo(left.purchasedAt),
    );
    return purchases;
  }

  bool _matchesFilters(
    Purchase purchase, {
    required String query,
    required PurchaseStatus? status,
    required int? supplierId,
  }) {
    if (status != null && purchase.status != status) {
      return false;
    }
    if (supplierId != null && purchase.supplierId != supplierId) {
      return false;
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return purchase.supplierName.toLowerCase().contains(normalized) ||
        (purchase.documentNumber?.toLowerCase().contains(normalized) ?? false);
  }

  String _requireRemoteId(PurchaseSyncPayload? purchase, String message) {
    final remoteId = purchase?.remoteId;
    if (remoteId == null || remoteId.trim().isEmpty) {
      throw ValidationException(message);
    }
    return remoteId;
  }

  RemotePurchaseRecord _remoteWithPayment(
    PurchaseSyncPayload purchase, {
    required PurchasePaymentInput input,
    required String paymentUuid,
  }) {
    final now = DateTime.now();
    final nextPaid = purchase.paidAmountCents + input.amountCents;
    final nextPending = purchase.finalAmountCents - nextPaid <= 0
        ? 0
        : purchase.finalAmountCents - nextPaid;
    final nextStatus = nextPending <= 0
        ? PurchaseStatus.paga
        : PurchaseStatus.parcialmentePaga;
    return RemotePurchaseRecord.fromSyncPayload(purchase).copyWith(
      status: nextStatus,
      paidAmountCents: nextPaid,
      pendingAmountCents: nextPending,
      updatedAt: now,
      payments: <RemotePurchasePaymentRecord>[
        ...RemotePurchaseRecord.fromSyncPayload(purchase).payments,
        RemotePurchasePaymentRecord(
          remoteId: '',
          localUuid: paymentUuid,
          amountCents: input.amountCents,
          paymentMethod: input.paymentMethod,
          paidAt: now,
          notes: input.notes,
        ),
      ],
    );
  }

  String? _mergeNotes(String? current, String? next) {
    final currentValue = current?.trim();
    final nextValue = next?.trim();
    if (currentValue == null || currentValue.isEmpty) {
      return nextValue == null || nextValue.isEmpty ? null : nextValue;
    }
    if (nextValue == null || nextValue.isEmpty) {
      return currentValue;
    }
    return '$currentValue\n$nextValue';
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
