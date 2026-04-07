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
import '../domain/entities/supplier.dart';
import '../domain/repositories/supplier_repository.dart';
import 'datasources/suppliers_remote_datasource.dart';
import 'models/remote_supplier_record.dart';
import 'sqlite_supplier_repository.dart';

class SuppliersRepositoryImpl
    implements SupplierRepository, SyncFeatureProcessor {
  const SuppliersRepositoryImpl({
    required SqliteSupplierRepository localRepository,
    required SuppliersRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteSupplierRepository _localRepository;
  final SuppliersRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteSupplierRepository.featureKey;

  @override
  String get displayName => 'Fornecedores';

  @override
  Future<int> create(SupplierInput input) {
    return _localRepository.create(input);
  }

  @override
  Future<void> delete(int id) {
    return _localRepository.delete(id);
  }

  @override
  Future<Supplier?> findById(int id) {
    return _localRepository.findById(id);
  }

  @override
  Future<List<Supplier>> search({String query = ''}) {
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

    final localSuppliers = await _localRepository.listForSync();
    for (final supplier in localSuppliers.where(
      (supplier) => _shouldPush(supplier, retryOnly: retryOnly),
    )) {
      try {
        if (supplier.deletedAt != null && supplier.remoteId != null) {
          await _remoteDatasource.delete(supplier.remoteId!);
          await _localRepository.upsertFromRemote(
            RemoteSupplierRecord.fromLocalSupplier(supplier),
          );
        } else {
          final remoteRecord = RemoteSupplierRecord.fromLocalSupplier(supplier);
          final persisted = supplier.remoteId == null
              ? await _remoteDatasource.create(remoteRecord)
              : await _remoteDatasource.update(
                  supplier.remoteId!,
                  remoteRecord,
                );

          await _localRepository.applyPushResult(
            supplier: supplier,
            remote: persisted,
          );
        }
        pushedCount++;
      } on NetworkRequestException catch (error) {
        final canRecover =
            supplier.remoteId != null &&
            SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
        if (canRecover) {
          await _localRepository.recoverMissingRemoteIdentity(
            supplier: supplier,
          );
          failedCount++;
          continue;
        }

        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          supplier: supplier,
          message: syncError.message,
          errorType: syncError.type,
        );
      } catch (error) {
        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          supplier: supplier,
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
        .where((supplier) => supplier.syncStatus == SyncStatus.synced)
        .length;

    return SyncActionResult(
      featureKey: SqliteSupplierRepository.featureKey,
      displayName: 'Fornecedores',
      pushedCount: pushedCount,
      pulledCount: pulledCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      message:
          message ??
          (failedCount == 0
              ? 'Fornecedores sincronizados com sucesso.'
              : 'Sincronizacao de fornecedores concluida com falhas parciais.'),
    );
  }

  @override
  Future<void> update(int id, SupplierInput input) {
    return _localRepository.update(id, input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final supplier = await _localRepository.findById(item.localEntityId);
    if (supplier == null) {
      return const SyncFeatureProcessResult.synced();
    }

    try {
      if (item.operation == SyncQueueOperation.update &&
          supplier.remoteId != null) {
        final conflict = await _detectConflict(supplier);
        if (conflict != null) {
          await _localRepository.markConflict(
            supplier: supplier,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          return SyncFeatureProcessResult.conflict(conflict: conflict);
        }
      }

      if (item.operation == SyncQueueOperation.delete ||
          supplier.deletedAt != null) {
        final remoteId = supplier.remoteId ?? item.remoteId;
        if (remoteId == null) {
          return const SyncFeatureProcessResult.synced();
        }

        await _remoteDatasource.delete(remoteId);
        await _localRepository.upsertFromRemote(
          RemoteSupplierRecord.fromLocalSupplier(supplier),
        );
        return SyncFeatureProcessResult.synced(remoteId: remoteId);
      }

      final remoteRecord = RemoteSupplierRecord.fromLocalSupplier(supplier);
      final remoteId = supplier.remoteId ?? item.remoteId;
      final persisted =
          (remoteId == null || item.operation == SyncQueueOperation.create)
          ? await _remoteDatasource.create(remoteRecord)
          : await _remoteDatasource.update(remoteId, remoteRecord);

      await _localRepository.applyPushResult(
        supplier: supplier,
        remote: persisted,
      );
      return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
    } on NetworkRequestException catch (error) {
      final canRecover =
          item.operation == SyncQueueOperation.update &&
          supplier.remoteId != null &&
          SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
      if (!canRecover) {
        rethrow;
      }

      await _localRepository.recoverMissingRemoteIdentity(
        supplier: supplier,
        queueItem: item,
      );
      return const SyncFeatureProcessResult.requeued(
        reason:
            'Registro remoto antigo nao existe mais; o fornecedor sera reenviado como criacao.',
      );
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remoteSuppliers = await _remoteDatasource.listAll();
    for (final remoteSupplier in remoteSuppliers) {
      await _localRepository.upsertFromRemote(remoteSupplier);
    }
    return remoteSuppliers.length;
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual de fornecedores.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os fornecedores.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  bool _shouldPush(Supplier supplier, {required bool retryOnly}) {
    if (supplier.deletedAt != null && supplier.remoteId == null) {
      return false;
    }

    if (retryOnly) {
      return supplier.syncStatus == SyncStatus.pendingUpload ||
          supplier.syncStatus == SyncStatus.pendingUpdate ||
          supplier.syncStatus == SyncStatus.syncError;
    }

    return supplier.remoteId == null ||
        supplier.syncStatus == SyncStatus.localOnly ||
        supplier.syncStatus == SyncStatus.pendingUpload ||
        supplier.syncStatus == SyncStatus.pendingUpdate ||
        supplier.syncStatus == SyncStatus.syncError;
  }

  Future<SyncConflictInfo?> _detectConflict(Supplier supplier) async {
    final lastSyncedAt = supplier.lastSyncedAt;
    if (lastSyncedAt == null || supplier.remoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(supplier.remoteId!);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = supplier.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason:
          'Fornecedor alterado localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: supplier.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }
}
