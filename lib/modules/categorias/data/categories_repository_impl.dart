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
import '../domain/entities/category.dart';
import '../domain/repositories/category_repository.dart';
import 'datasources/categories_remote_datasource.dart';
import 'models/remote_category_record.dart';
import 'sqlite_category_repository.dart';

class CategoriesRepositoryImpl
    implements CategoryRepository, SyncFeatureProcessor {
  const CategoriesRepositoryImpl({
    required SqliteCategoryRepository localRepository,
    required CategoriesRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteCategoryRepository _localRepository;
  final CategoriesRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteCategoryRepository.featureKey;

  @override
  String get displayName => 'Categorias';

  @override
  Future<int> create(CategoryInput input) {
    return _localRepository.create(input);
  }

  @override
  Future<void> delete(int id) {
    return _localRepository.delete(id);
  }

  @override
  Future<List<Category>> search({String query = ''}) {
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

    final localCategories = await _localRepository.listForSync();
    for (final category in localCategories.where(
      (category) => _shouldPush(category, retryOnly: retryOnly),
    )) {
      try {
        if (category.deletedAt != null && category.remoteId != null) {
          await _remoteDatasource.delete(category.remoteId!);
          await _localRepository.upsertFromRemote(
            RemoteCategoryRecord.fromLocalCategory(category),
          );
        } else {
          final remoteRecord = RemoteCategoryRecord.fromLocalCategory(category);
          final persisted = category.remoteId == null
              ? await _remoteDatasource.create(remoteRecord)
              : await _remoteDatasource.update(
                  category.remoteId!,
                  remoteRecord,
                );

          await _localRepository.applyPushResult(
            category: category,
            remote: persisted,
          );
        }
        pushedCount++;
      } on NetworkRequestException catch (error) {
        final canRecover =
            category.remoteId != null &&
            SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
        if (canRecover) {
          await _localRepository.recoverMissingRemoteIdentity(
            category: category,
          );
          failedCount++;
          continue;
        }

        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          category: category,
          message: syncError.message,
          errorType: syncError.type,
        );
      } catch (error) {
        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          category: category,
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
        .where((category) => category.syncStatus == SyncStatus.synced)
        .length;

    return SyncActionResult(
      featureKey: SqliteCategoryRepository.featureKey,
      displayName: 'Categorias',
      pushedCount: pushedCount,
      pulledCount: pulledCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      message:
          message ??
          (failedCount == 0
              ? 'Categorias sincronizadas com sucesso.'
              : 'Sincronizacao de categorias concluida com falhas parciais.'),
    );
  }

  @override
  Future<void> update(int id, CategoryInput input) {
    return _localRepository.update(id, input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final category = await _localRepository.findById(
      item.localEntityId,
      includeDeleted: true,
    );
    if (category == null) {
      return const SyncFeatureProcessResult.synced();
    }

    try {
      if (item.operation == SyncQueueOperation.update &&
          category.remoteId != null) {
        final conflict = await _detectConflict(category);
        if (conflict != null) {
          await _localRepository.markConflict(
            category: category,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          return SyncFeatureProcessResult.conflict(conflict: conflict);
        }
      }

      if (item.operation == SyncQueueOperation.delete ||
          category.deletedAt != null) {
        final remoteId = category.remoteId ?? item.remoteId;
        if (remoteId == null) {
          return const SyncFeatureProcessResult.synced();
        }

        await _remoteDatasource.delete(remoteId);
        await _localRepository.upsertFromRemote(
          RemoteCategoryRecord.fromLocalCategory(category),
        );
        return SyncFeatureProcessResult.synced(remoteId: remoteId);
      }

      final remoteRecord = RemoteCategoryRecord.fromLocalCategory(category);
      final persisted =
          (category.remoteId == null ||
              item.operation == SyncQueueOperation.create)
          ? await _remoteDatasource.create(remoteRecord)
          : await _remoteDatasource.update(category.remoteId!, remoteRecord);

      await _localRepository.applyPushResult(
        category: category,
        remote: persisted,
      );
      return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
    } on NetworkRequestException catch (error) {
      final canRecover =
          item.operation == SyncQueueOperation.update &&
          category.remoteId != null &&
          SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
      if (!canRecover) {
        rethrow;
      }

      await _localRepository.recoverMissingRemoteIdentity(
        category: category,
        queueItem: item,
      );
      return const SyncFeatureProcessResult.requeued(
        reason:
            'Registro remoto antigo nao existe mais; a categoria sera reenviada como criacao.',
      );
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remoteCategories = await _remoteDatasource.listAll();
    for (final remoteCategory in remoteCategories) {
      await _localRepository.upsertFromRemote(remoteCategory);
    }
    return remoteCategories.length;
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual de categorias.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar as categorias.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  bool _shouldPush(Category category, {required bool retryOnly}) {
    if (category.deletedAt != null && category.remoteId == null) {
      return false;
    }

    if (retryOnly) {
      return category.syncStatus == SyncStatus.pendingUpload ||
          category.syncStatus == SyncStatus.pendingUpdate ||
          category.syncStatus == SyncStatus.syncError;
    }

    return category.remoteId == null ||
        category.syncStatus == SyncStatus.localOnly ||
        category.syncStatus == SyncStatus.pendingUpload ||
        category.syncStatus == SyncStatus.pendingUpdate ||
        category.syncStatus == SyncStatus.syncError;
  }

  Future<SyncConflictInfo?> _detectConflict(Category category) async {
    final lastSyncedAt = category.lastSyncedAt;
    if (lastSyncedAt == null || category.remoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(category.remoteId!);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = category.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason:
          'Categoria alterada localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: category.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }
}
