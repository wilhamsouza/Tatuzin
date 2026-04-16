import 'package:sqflite/sqflite.dart';

import '../../../../app/core/app_context/record_identity.dart';
import '../../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../../app/core/sync/sync_error_type.dart';
import '../../../../app/core/sync/sync_queue_operation.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../models/purchase_sync_payload.dart';

class PurchaseSyncStateSupport {
  const PurchaseSyncStateSupport({
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required SqliteSyncQueueRepository syncQueueRepository,
    required this.featureKey,
  }) : _syncMetadataRepository = syncMetadataRepository,
       _syncQueueRepository = syncQueueRepository;

  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final String featureKey;

  Future<void> registerPurchaseForSync(
    DatabaseExecutor txn, {
    required int purchaseId,
    required String purchaseUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
    bool localOnly = false,
    String? reason,
  }) async {
    final metadata = await _syncMetadataRepository.findByLocalId(
      txn,
      featureKey: featureKey,
      localId: purchaseId,
    );
    final remoteId = metadata?.identity.remoteId;
    if (localOnly) {
      await _syncMetadataRepository.saveExplicit(
        txn,
        featureKey: featureKey,
        localId: purchaseId,
        localUuid: purchaseUuid,
        remoteId: remoteId,
        status: SyncStatus.localOnly,
        origin: remoteId == null ? RecordOrigin.local : RecordOrigin.merged,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastSyncedAt: metadata?.lastSyncedAt,
        lastError: reason,
        lastErrorType: SyncErrorType.dependency.storageValue,
        lastErrorAt: updatedAt,
      );
      await _syncQueueRepository.removeForEntity(
        txn,
        featureKey: featureKey,
        localEntityId: purchaseId,
      );
      return;
    }

    if (remoteId == null) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: featureKey,
        localId: purchaseId,
        localUuid: purchaseUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: purchaseId,
        localUuid: purchaseUuid,
        remoteId: remoteId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: featureKey,
      entityType: 'purchase',
      localEntityId: purchaseId,
      localUuid: purchaseUuid,
      remoteId: remoteId,
      operation: remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
  }

  Future<void> markSynced(
    DatabaseExecutor txn, {
    required PurchaseSyncPayload purchase,
    required String remoteId,
    DateTime? syncedAt,
  }) async {
    await _syncMetadataRepository.markSynced(
      txn,
      featureKey: featureKey,
      localId: purchase.purchaseId,
      localUuid: purchase.purchaseUuid,
      remoteId: remoteId,
      origin: RecordOrigin.local,
      createdAt: purchase.createdAt,
      updatedAt: purchase.updatedAt,
      syncedAt: syncedAt ?? DateTime.now(),
    );
  }

  Future<void> markSyncError(
    DatabaseExecutor txn, {
    required PurchaseSyncPayload purchase,
    required String message,
    required SyncErrorType errorType,
    DateTime? updatedAt,
  }) async {
    await _syncMetadataRepository.markSyncError(
      txn,
      featureKey: featureKey,
      localId: purchase.purchaseId,
      localUuid: purchase.purchaseUuid,
      remoteId: purchase.remoteId,
      createdAt: purchase.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      message: message,
      errorType: errorType,
    );
  }

  Future<void> markConflict(
    DatabaseExecutor txn, {
    required PurchaseSyncPayload purchase,
    required String message,
    required DateTime detectedAt,
  }) async {
    await _syncMetadataRepository.markConflict(
      txn,
      featureKey: featureKey,
      localId: purchase.purchaseId,
      localUuid: purchase.purchaseUuid,
      remoteId: purchase.remoteId,
      createdAt: purchase.createdAt,
      updatedAt: detectedAt,
      message: message,
    );
  }
}
