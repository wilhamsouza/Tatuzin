import '../errors/app_exceptions.dart';
import '../app_context/record_identity.dart';
import '../database/app_database.dart';
import 'sqlite_sync_audit_repository.dart';
import 'sqlite_sync_metadata_repository.dart';
import 'sqlite_sync_queue_repository.dart';
import 'sync_audit_event_type.dart';
import 'sync_queue_item.dart';
import 'sync_queue_operation.dart';

class SyncRemoteIdentityRecovery {
  SyncRemoteIdentityRecovery(this._appDatabase)
    : _metadataRepository = SqliteSyncMetadataRepository(_appDatabase),
      _queueRepository = SqliteSyncQueueRepository(_appDatabase),
      _auditRepository = SqliteSyncAuditRepository(_appDatabase);

  final AppDatabase _appDatabase;
  final SqliteSyncMetadataRepository _metadataRepository;
  final SqliteSyncQueueRepository _queueRepository;
  final SqliteSyncAuditRepository _auditRepository;

  static bool isRemoteIdentityMissing(Object error) {
    return error is NetworkRequestException && error.cause == 404;
  }

  Future<void> recoverForReupload({
    required String featureKey,
    required String entityType,
    required int localEntityId,
    required String localUuid,
    required String? staleRemoteId,
    required DateTime createdAt,
    required DateTime updatedAt,
    SyncQueueItem? queueItem,
    required String entityLabel,
  }) async {
    final database = await _appDatabase.database;
    final recoveredAt = DateTime.now();

    await database.transaction((txn) async {
      final metadata = await _metadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: localEntityId,
      );
      final previousRemoteId = metadata?.identity.remoteId ?? staleRemoteId;

      await _auditRepository.log(
        executor: txn,
        featureKey: featureKey,
        entityType: entityType,
        localEntityId: localEntityId,
        localUuid: localUuid,
        remoteId: previousRemoteId,
        eventType: SyncAuditEventType.remoteIdentityLost,
        message:
            'O registro remoto antigo de $entityLabel nao existe mais; o vinculo sera recriado com seguranca.',
        details: <String, dynamic>{
          'queueId': queueItem?.id,
          'correlationKey': queueItem?.correlationKey,
          'previousRemoteId': previousRemoteId,
          'previousOperation':
              queueItem?.operation.storageValue ??
              SyncQueueOperation.update.storageValue,
        },
        createdAt: recoveredAt,
      );

      await _metadataRepository.markPendingUpload(
        txn,
        featureKey: featureKey,
        localId: localEntityId,
        localUuid: localUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      await _auditRepository.log(
        executor: txn,
        featureKey: featureKey,
        entityType: entityType,
        localEntityId: localEntityId,
        localUuid: localUuid,
        remoteId: previousRemoteId,
        eventType: SyncAuditEventType.remoteIdCleared,
        message:
            'O remoteId invalido foi limpo para que o cadastro volte a subir como criacao.',
        details: <String, dynamic>{
          'queueId': queueItem?.id,
          'previousRemoteId': previousRemoteId,
          'newOrigin': recordOriginToStorage(RecordOrigin.local),
        },
        createdAt: recoveredAt,
      );

      await _auditRepository.log(
        executor: txn,
        featureKey: featureKey,
        entityType: entityType,
        localEntityId: localEntityId,
        localUuid: localUuid,
        remoteId: null,
        eventType: SyncAuditEventType.metadataReclassifiedForReupload,
        message:
            'A metadata local foi reclassificada para pending_upload sem apagar o registro local.',
        details: <String, dynamic>{
          'queueId': queueItem?.id,
          'newStatus': 'pending_upload',
          'localUuid': localUuid,
        },
        createdAt: recoveredAt,
      );

      if (queueItem != null) {
        await _queueRepository.reenqueueAsCreate(
          queueItem.id,
          requeuedAt: recoveredAt,
          executor: txn,
        );
      } else {
        await _queueRepository.enqueueMutation(
          txn,
          featureKey: featureKey,
          entityType: entityType,
          localEntityId: localEntityId,
          localUuid: localUuid,
          remoteId: null,
          operation: SyncQueueOperation.create,
          localUpdatedAt: updatedAt,
        );
        await _auditRepository.log(
          executor: txn,
          featureKey: featureKey,
          entityType: entityType,
          localEntityId: localEntityId,
          localUuid: localUuid,
          remoteId: null,
          eventType: SyncAuditEventType.queueReenqueuedAsCreate,
          message:
              'O item foi reenfileirado como criacao para repovoar o backend limpo.',
          details: <String, dynamic>{
            'queueId': null,
            'newOperation': SyncQueueOperation.create.storageValue,
          },
          createdAt: recoveredAt,
        );
      }

      await _auditRepository.log(
        executor: txn,
        featureKey: featureKey,
        entityType: entityType,
        localEntityId: localEntityId,
        localUuid: localUuid,
        remoteId: null,
        eventType: SyncAuditEventType.dependencyRevalidationTriggered,
        message:
            'As dependencias da fila serao revalidadas na proxima tentativa de sincronizacao.',
        details: <String, dynamic>{
          'queueId': queueItem?.id,
          'correlationKey': queueItem?.correlationKey,
        },
        createdAt: recoveredAt,
      );
    });
  }
}
