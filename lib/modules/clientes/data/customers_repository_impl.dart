import 'dart:async';

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
import '../../../app/core/utils/app_logger.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/client.dart';
import '../domain/repositories/client_repository.dart';
import 'datasources/customers_remote_datasource.dart';
import 'models/remote_customer_record.dart';
import 'sqlite_client_repository.dart';

class CustomersRepositoryImpl
    implements ClientRepository, SyncFeatureProcessor {
  CustomersRepositoryImpl({
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
  Future<void>? _cacheMergeInFlight;

  @override
  String get featureKey => SqliteClientRepository.featureKey;

  @override
  String get displayName => 'Clientes';

  @override
  Future<int> create(ClientInput input) async {
    if (_shouldUseCrmRemoteWrite) {
      try {
        final remote = await _remoteDatasource
            .create(_remoteCustomerFromInput(input))
            .timeout(const Duration(seconds: 15));
        return _cacheAndResolveRemoteCustomer(remote);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Clientes CRM server-first falhou ao criar na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.create(input);
  }

  @override
  Future<void> delete(int id) async {
    if (_shouldUseCrmRemoteWrite) {
      final client = await _localRepository
          .findById(id, includeDeleted: true)
          .timeout(const Duration(seconds: 8));
      if (client?.remoteId == null) {
        throw const ValidationException(
          'Cliente ainda nao possui vinculo remoto para exclusao server-first.',
        );
      }

      try {
        await _remoteDatasource
            .delete(client!.remoteId!)
            .timeout(const Duration(seconds: 15));
        await _localRepository.applyPushResult(
          client: client,
          remote: RemoteCustomerRecord.fromLocalClient(
            client,
          ).copyWithInactive(),
        );
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Clientes CRM server-first falhou ao excluir na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.delete(id);
  }

  @override
  Future<List<Client>> search({String query = ''}) async {
    if (_shouldUseCrmRemoteRead) {
      try {
        AppLogger.info('[ClientesRepo] remote_list_started');
        final remoteClients = await _remoteDatasource.listAll().timeout(
          const Duration(seconds: 15),
        );
        AppLogger.info(
          '[ClientesRepo] remote_list_finished count=${remoteClients.length}',
        );
        return _cacheAndResolveRemoteCustomers(remoteClients, query: query);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Clientes server-first falhou; tentando cache local com timeout.',
          error: error,
          stackTrace: stackTrace,
        );
        return _localRepository
            .search(query: query)
            .timeout(const Duration(seconds: 8));
      }
    }

    return _localRepository
        .search(query: query)
        .timeout(const Duration(seconds: 12));
  }

  Future<Client?> findById(int id) async {
    final local = await _localRepository
        .findById(id, includeDeleted: true)
        .timeout(const Duration(seconds: 8));
    if (!_shouldUseCrmRemoteRead || local?.remoteId == null) {
      return local;
    }

    try {
      final remote = await _remoteDatasource
          .fetchById(local!.remoteId!)
          .timeout(const Duration(seconds: 15));
      return _cacheAndFindRemoteCustomer(remote);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Clientes CRM server-first falhou ao buscar detalhe remoto; usando cache local.',
        error: error,
        stackTrace: stackTrace,
      );
      return local;
    }
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
  Future<void> update(int id, ClientInput input) async {
    if (_shouldUseCrmRemoteWrite) {
      final client = await _localRepository
          .findById(id, includeDeleted: true)
          .timeout(const Duration(seconds: 8));
      if (client?.remoteId == null) {
        throw const ValidationException(
          'Cliente ainda nao possui vinculo remoto para atualizacao server-first.',
        );
      }

      try {
        final remote = await _remoteDatasource
            .update(
              client!.remoteId!,
              _remoteCustomerFromInput(
                input,
                remoteId: client.remoteId!,
                localUuid: client.uuid,
                createdAt: client.createdAt,
              ),
            )
            .timeout(const Duration(seconds: 15));
        await _localRepository.applyPushResult(client: client, remote: remote);
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Clientes CRM server-first falhou ao atualizar na API.',
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

  bool get _shouldUseCrmRemoteRead =>
      _dataAccessPolicy.strategyFor(AppModule.crm) ==
          DataSourceStrategy.serverFirst &&
      _operationalContext.canUseCloudReads;

  bool get _shouldUseCrmRemoteWrite => _shouldUseCrmRemoteRead;

  Future<List<Client>> _cacheAndResolveRemoteCustomers(
    List<RemoteCustomerRecord> remoteClients, {
    required String query,
  }) async {
    final mergeFuture = _scheduleCacheMerge(remoteClients);
    try {
      await mergeFuture.timeout(const Duration(seconds: 2));
      return _readCachedRemoteCustomers(
        remoteClients,
        query: query,
      ).timeout(const Duration(seconds: 4));
    } catch (error, stackTrace) {
      AppLogger.error(
        '[ClientesRepo] cache_merge_failed error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      return _remoteCustomersToEntities(remoteClients, query: query);
    }
  }

  Future<int> _cacheAndResolveRemoteCustomer(
    RemoteCustomerRecord remote,
  ) async {
    final client = await _cacheAndFindRemoteCustomer(remote);
    if (client == null) {
      throw const NetworkRequestException(
        'Cliente remoto salvo, mas o cache local nao retornou o espelho.',
      );
    }
    return client.id;
  }

  Future<Client?> _cacheAndFindRemoteCustomer(
    RemoteCustomerRecord remote,
  ) async {
    await _localRepository.upsertFromRemote(
      remote,
      preserveLocalPendingChanges: false,
    );
    return _localRepository
        .findByRemoteId(remote.remoteId)
        .timeout(const Duration(seconds: 8));
  }

  Future<void> _scheduleCacheMerge(List<RemoteCustomerRecord> remoteClients) {
    final activeMerge = _cacheMergeInFlight;
    if (activeMerge != null) {
      return activeMerge;
    }

    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      '[ClientesRepo] cache_merge_started count=${remoteClients.length}',
    );
    final merge = _cacheRemoteCustomers(remoteClients).whenComplete(() {
      AppLogger.info(
        '[ClientesRepo] cache_merge_finished duration_ms=${stopwatch.elapsedMilliseconds}',
      );
      _cacheMergeInFlight = null;
    });
    _cacheMergeInFlight = merge;
    return merge;
  }

  Future<void> _cacheRemoteCustomers(
    List<RemoteCustomerRecord> remoteClients,
  ) async {
    for (final remoteClient in remoteClients) {
      await _localRepository.upsertFromRemote(
        remoteClient,
        preserveLocalPendingChanges: false,
      );
    }
  }

  Future<List<Client>> _readCachedRemoteCustomers(
    List<RemoteCustomerRecord> remoteClients, {
    required String query,
  }) async {
    final clients = <Client>[];
    for (final remoteClient in remoteClients) {
      final client = await _localRepository.findByRemoteId(
        remoteClient.remoteId,
      );
      if (client != null &&
          client.deletedAt == null &&
          _matchesQuery(client, query)) {
        clients.add(client);
      }
    }
    clients.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return clients;
  }

  List<Client> _remoteCustomersToEntities(
    List<RemoteCustomerRecord> records, {
    required String query,
  }) {
    final clients = records
        .map(_remoteCustomerToEntity)
        .where((client) => client.deletedAt == null)
        .where((client) => _matchesQuery(client, query))
        .toList(growable: false);
    clients.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return clients;
  }

  Client _remoteCustomerToEntity(RemoteCustomerRecord remote) {
    return Client(
      id: _remotePlaceholderId(remote.remoteId),
      uuid: remote.localUuid,
      name: remote.name,
      phone: remote.phone,
      address: remote.address,
      notes: remote.notes,
      debtorBalanceCents: 0,
      creditBalanceCents: 0,
      isActive: remote.isActive,
      createdAt: remote.createdAt,
      updatedAt: remote.updatedAt,
      deletedAt: remote.deletedAt,
      remoteId: remote.remoteId,
      syncStatus: SyncStatus.synced,
      lastSyncedAt: DateTime.now(),
    );
  }

  int _remotePlaceholderId(String remoteId) {
    var hash = 0;
    for (final codeUnit in remoteId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x3fffffff;
    }
    return hash == 0 ? -1 : -hash;
  }

  RemoteCustomerRecord _remoteCustomerFromInput(
    ClientInput input, {
    String remoteId = '',
    String? localUuid,
    DateTime? createdAt,
  }) {
    final now = DateTime.now();
    return RemoteCustomerRecord(
      remoteId: remoteId,
      localUuid: localUuid ?? IdGenerator.next(),
      name: input.name.trim(),
      phone: _cleanNullable(input.phone),
      address: _cleanNullable(input.address),
      notes: _cleanNullable(input.notes),
      isActive: input.isActive,
      createdAt: createdAt ?? now,
      updatedAt: now,
      deletedAt: input.isActive ? null : now,
    );
  }

  bool _matchesQuery(Client client, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return client.name.toLowerCase().contains(normalized) ||
        (client.phone?.toLowerCase().contains(normalized) ?? false);
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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
