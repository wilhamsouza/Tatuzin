import 'package:sqflite/sqflite.dart';

import '../../../../app/core/app_context/record_identity.dart';
import '../../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../../app/core/sync/sync_error_type.dart';
import '../../../../app/core/sync/sync_queue_operation.dart';
import '../models/sale_cancellation_sync_payload.dart';
import '../models/sale_sync_payload.dart';

class SaleSyncStateSupport {
  const SaleSyncStateSupport({
    required SqliteSyncMetadataRepository syncMetadataRepository,
    required SqliteSyncQueueRepository syncQueueRepository,
    required this.featureKey,
    required this.cashEventFeatureKey,
    required this.cancellationFeatureKey,
    required this.financialEventFeatureKey,
  }) : _syncMetadataRepository = syncMetadataRepository,
       _syncQueueRepository = syncQueueRepository;

  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final String featureKey;
  final String cashEventFeatureKey;
  final String cancellationFeatureKey;
  final String financialEventFeatureKey;

  Future<void> registerSaleForSync(
    DatabaseExecutor txn, {
    required int saleId,
    required String saleUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: featureKey,
      localId: saleId,
      localUuid: saleUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: featureKey,
      entityType: 'sale',
      localEntityId: saleId,
      localUuid: saleUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  Future<void> registerCashEventForSync(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: cashEventFeatureKey,
      localId: movementId,
      localUuid: movementUuid,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: cashEventFeatureKey,
      entityType: 'cash_event',
      localEntityId: movementId,
      localUuid: movementUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: createdAt,
    );
  }

  Future<void> registerCancellationForSync(
    DatabaseExecutor txn, {
    required int saleId,
    required String saleUuid,
    required DateTime canceledAt,
  }) async {
    await _syncMetadataRepository.markPendingUpload(
      txn,
      featureKey: cancellationFeatureKey,
      localId: saleId,
      localUuid: saleUuid,
      createdAt: canceledAt,
      updatedAt: canceledAt,
    );
    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: financialEventFeatureKey,
      entityType: 'sale_canceled_event',
      localEntityId: saleId,
      localUuid: saleUuid,
      remoteId: null,
      operation: SyncQueueOperation.create,
      localUpdatedAt: canceledAt,
    );
  }

  Future<void> markSynced(
    DatabaseExecutor txn, {
    required SaleSyncPayload sale,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    await _syncMetadataRepository.markSynced(
      txn,
      featureKey: featureKey,
      localId: sale.saleId,
      localUuid: sale.saleUuid,
      remoteId: remoteId,
      origin: RecordOrigin.local,
      createdAt: sale.soldAt,
      updatedAt: sale.updatedAt,
      syncedAt: syncedAt,
    );
  }

  Future<void> markSyncError(
    DatabaseExecutor txn, {
    required SaleSyncPayload sale,
    required String message,
    required SyncErrorType errorType,
    required DateTime updatedAt,
  }) async {
    await _syncMetadataRepository.markSyncError(
      txn,
      featureKey: featureKey,
      localId: sale.saleId,
      localUuid: sale.saleUuid,
      remoteId: sale.remoteId,
      createdAt: sale.soldAt,
      updatedAt: updatedAt,
      message: message,
      errorType: errorType,
    );
  }

  Future<void> markConflict(
    DatabaseExecutor txn, {
    required SaleSyncPayload sale,
    required String message,
    required DateTime detectedAt,
  }) async {
    await _syncMetadataRepository.markConflict(
      txn,
      featureKey: featureKey,
      localId: sale.saleId,
      localUuid: sale.saleUuid,
      remoteId: sale.remoteId,
      createdAt: sale.soldAt,
      updatedAt: detectedAt,
      message: message,
    );
  }

  Future<void> markCancellationSynced(
    DatabaseExecutor txn, {
    required SaleCancellationSyncPayload sale,
    required String remoteId,
    required DateTime syncedAt,
  }) async {
    await _syncMetadataRepository.markSynced(
      txn,
      featureKey: cancellationFeatureKey,
      localId: sale.saleId,
      localUuid: sale.saleUuid,
      remoteId: remoteId,
      origin: RecordOrigin.local,
      createdAt: sale.canceledAt,
      updatedAt: sale.updatedAt,
      syncedAt: syncedAt,
    );
  }

  Future<void> markCancellationConflict(
    DatabaseExecutor txn, {
    required SaleCancellationSyncPayload sale,
    required String message,
    required DateTime detectedAt,
  }) async {
    await _syncMetadataRepository.markConflict(
      txn,
      featureKey: cancellationFeatureKey,
      localId: sale.saleId,
      localUuid: sale.saleUuid,
      remoteId: sale.remoteId,
      createdAt: sale.canceledAt,
      updatedAt: detectedAt,
      message: message,
    );
  }
}
