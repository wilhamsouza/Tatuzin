import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_action_result.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_error_info.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_remote_identity_recovery.dart';
import '../../../app/core/sync/sync_status.dart';
import '../domain/entities/client.dart';
import '../domain/repositories/client_repository.dart';
import 'datasources/customers_remote_datasource.dart';
import 'models/remote_customer_record.dart';
import 'sqlite_client_repository.dart';

class CustomersRepositoryImpl
    implements ClientRepository, SyncFeatureProcessor {
  const CustomersRepositoryImpl({
    required SqliteClientRepository localRepository,
    required CustomersRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteClientRepository _localRepository;
  final CustomersRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteClientRepository.featureKey;

  @override
  String get displayName => 'Clientes';

  @override
  Future<int> create(ClientInput input) {
    return _localRepository.create(input);
  }

  @override
  Future<void> delete(int id) {
    return _localRepository.delete(id);
  }

  @override
  Future<List<Client>> search({String query = ''}) {
    return _localRepository.search(query: query);
  }

  Future<SyncActionResult> syncNow({bool retryOnly = false}) async {
    _ensureSyncIsAllowed();

    final startedAt = DateTime.now();
    var pushedCount = 0;
    var pulledCount = 0;
    var failedCount = 0;
    String? message;

    await _remoteDatasource.canReachRemote();

    final localClients = await _localRepository.listForSync();
    for (final client in localClients.where(
      (client) => _shouldPush(client, retryOnly: retryOnly),
    )) {
      try {
        if (client.deletedAt != null && client.remoteId != null) {
          await _remoteDatasource.delete(client.remoteId!);
          await _localRepository.upsertFromRemote(
            RemoteCustomerRecord.fromLocalClient(client),
          );
        } else {
          final remoteRecord = RemoteCustomerRecord.fromLocalClient(client);
          final persisted = client.remoteId == null
              ? await _remoteDatasource.create(remoteRecord)
              : await _remoteDatasource.update(client.remoteId!, remoteRecord);

          await _localRepository.applyPushResult(
            client: client,
            remote: persisted,
          );
        }
        pushedCount++;
      } on NetworkRequestException catch (error) {
        final canRecover =
            client.remoteId != null &&
            SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
        if (canRecover) {
          await _localRepository.recoverMissingRemoteIdentity(client: client);
          failedCount++;
          continue;
        }

        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          client: client,
          message: syncError.message,
          errorType: syncError.type,
        );
      } catch (error) {
        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          client: client,
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
        .where((client) => client.syncStatus == SyncStatus.synced)
        .length;

    return SyncActionResult(
      featureKey: SqliteClientRepository.featureKey,
      displayName: 'Clientes',
      pushedCount: pushedCount,
      pulledCount: pulledCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      message:
          message ??
          (failedCount == 0
              ? 'Clientes sincronizados com sucesso.'
              : 'Sincronizacao de clientes concluida com falhas parciais.'),
    );
  }

  @override
  Future<void> update(int id, ClientInput input) {
    return _localRepository.update(id, input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final client = await _localRepository.findById(
      item.localEntityId,
      includeDeleted: true,
    );
    if (client == null) {
      return const SyncFeatureProcessResult.synced();
    }

    try {
      if (item.operation == SyncQueueOperation.update &&
          client.remoteId != null) {
        final conflict = await _detectConflict(client);
        if (conflict != null) {
          await _localRepository.markConflict(
            client: client,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          return SyncFeatureProcessResult.conflict(conflict: conflict);
        }
      }

      if (item.operation == SyncQueueOperation.delete ||
          client.deletedAt != null) {
        final remoteId = client.remoteId ?? item.remoteId;
        if (remoteId == null) {
          return const SyncFeatureProcessResult.synced();
        }

        await _remoteDatasource.delete(remoteId);
        await _localRepository.upsertFromRemote(
          RemoteCustomerRecord.fromLocalClient(client),
        );
        return SyncFeatureProcessResult.synced(remoteId: remoteId);
      }

      final remoteRecord = RemoteCustomerRecord.fromLocalClient(client);
      final remoteId = client.remoteId ?? item.remoteId;
      final persisted =
          (remoteId == null || item.operation == SyncQueueOperation.create)
          ? await _remoteDatasource.create(remoteRecord)
          : await _remoteDatasource.update(remoteId, remoteRecord);

      await _localRepository.applyPushResult(client: client, remote: persisted);
      return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
    } on NetworkRequestException catch (error) {
      final canRecover =
          item.operation == SyncQueueOperation.update &&
          client.remoteId != null &&
          SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
      if (!canRecover) {
        rethrow;
      }

      await _localRepository.recoverMissingRemoteIdentity(
        client: client,
        queueItem: item,
      );
      return const SyncFeatureProcessResult.requeued(
        reason:
            'Registro remoto antigo nao existe mais; o cliente sera reenviado como criacao.',
      );
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remoteClients = await _remoteDatasource.listAll();
    for (final remoteClient in remoteClients) {
      await _localRepository.upsertFromRemote(remoteClient);
    }
    return remoteClients.length;
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual de clientes.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os clientes.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  bool _shouldPush(Client client, {required bool retryOnly}) {
    if (client.deletedAt != null && client.remoteId == null) {
      return false;
    }

    if (retryOnly) {
      return client.syncStatus == SyncStatus.pendingUpload ||
          client.syncStatus == SyncStatus.pendingUpdate ||
          client.syncStatus == SyncStatus.syncError;
    }

    return client.remoteId == null ||
        client.syncStatus == SyncStatus.localOnly ||
        client.syncStatus == SyncStatus.pendingUpload ||
        client.syncStatus == SyncStatus.pendingUpdate ||
        client.syncStatus == SyncStatus.syncError;
  }

  Future<SyncConflictInfo?> _detectConflict(Client client) async {
    final lastSyncedAt = client.lastSyncedAt;
    if (lastSyncedAt == null || client.remoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(client.remoteId!);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = client.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason: 'Cliente alterado localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: client.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }
}
