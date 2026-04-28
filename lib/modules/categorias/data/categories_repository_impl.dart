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
import '../domain/entities/category.dart';
import '../domain/repositories/category_repository.dart';
import 'datasources/categories_remote_datasource.dart';
import 'models/remote_category_record.dart';
import 'sqlite_category_repository.dart';

class CategoriesRepositoryImpl
    implements CategoryRepository, SyncFeatureProcessor {
  CategoriesRepositoryImpl({
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
  Future<void>? _cacheMergeInFlight;

  @override
  String get featureKey => SqliteCategoryRepository.featureKey;

  @override
  String get displayName => 'Categorias';

  @override
  Future<int> create(CategoryInput input) async {
    if (_shouldUseErpRemoteWrite) {
      try {
        final remote = await _remoteDatasource
            .create(_remoteCategoryFromInput(input))
            .timeout(const Duration(seconds: 15));
        return _cacheAndResolveRemoteCategory(remote);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Categorias ERP server-first falhou ao criar na API.',
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
    if (_shouldUseErpRemoteWrite) {
      final category = await _localRepository
          .findById(id, includeDeleted: true)
          .timeout(const Duration(seconds: 8));
      if (category?.remoteId == null) {
        throw const ValidationException(
          'Categoria ainda nao possui vinculo remoto para exclusao server-first.',
        );
      }

      try {
        await _remoteDatasource
            .delete(category!.remoteId!)
            .timeout(const Duration(seconds: 15));
        await _localRepository.upsertFromRemote(
          RemoteCategoryRecord(
            remoteId: category.remoteId!,
            localUuid: category.uuid,
            name: category.name,
            description: category.description,
            isActive: false,
            createdAt: category.createdAt,
            updatedAt: DateTime.now(),
            deletedAt: DateTime.now(),
          ),
        );
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Categorias ERP server-first falhou ao excluir na API.',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    return _localRepository.delete(id);
  }

  @override
  Future<List<Category>> search({String query = ''}) async {
    if (_shouldUseErpRemoteRead) {
      try {
        AppLogger.info('[CategoriasRepo] remote_list_started');
        final remoteCategories = await _remoteDatasource.listAll().timeout(
          const Duration(seconds: 15),
        );
        AppLogger.info(
          '[CategoriasRepo] remote_list_finished count=${remoteCategories.length}',
        );
        return _cacheAndResolveRemoteCategories(remoteCategories, query: query);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Categorias ERP server-first falhou; usando cache local com timeout.',
          error: error,
          stackTrace: stackTrace,
        );
        return _localRepository
            .search(query: query)
            .timeout(const Duration(seconds: 8));
      }
    }

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
  Future<void> update(int id, CategoryInput input) async {
    if (_shouldUseErpRemoteWrite) {
      final category = await _localRepository
          .findById(id, includeDeleted: true)
          .timeout(const Duration(seconds: 8));
      if (category?.remoteId == null) {
        throw const ValidationException(
          'Categoria ainda nao possui vinculo remoto para atualizacao server-first.',
        );
      }

      try {
        final remote = await _remoteDatasource
            .update(
              category!.remoteId!,
              _remoteCategoryFromInput(
                input,
                localUuid: category.uuid,
                remoteId: category.remoteId!,
                createdAt: category.createdAt,
              ),
            )
            .timeout(const Duration(seconds: 15));
        await _localRepository.applyPushResult(
          category: category,
          remote: remote,
        );
        return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Categorias ERP server-first falhou ao atualizar na API.',
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

  bool get _shouldUseErpRemoteRead =>
      _dataAccessPolicy.strategyFor(AppModule.erp) ==
          DataSourceStrategy.serverFirst &&
      _operationalContext.canUseCloudReads;

  bool get _shouldUseErpRemoteWrite => _shouldUseErpRemoteRead;

  Future<List<Category>> _cacheAndResolveRemoteCategories(
    List<RemoteCategoryRecord> remoteCategories, {
    required String query,
  }) async {
    final mergeFuture = _scheduleCacheMerge(remoteCategories);
    try {
      await mergeFuture.timeout(const Duration(seconds: 2));
      return _readCachedRemoteCategories(
        remoteCategories,
        query: query,
      ).timeout(const Duration(seconds: 4));
    } catch (error, stackTrace) {
      AppLogger.error(
        '[CategoriasRepo] cache_merge_failed error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      return _remoteCategoriesToEntities(remoteCategories, query: query);
    }
  }

  Future<int> _cacheAndResolveRemoteCategory(
    RemoteCategoryRecord remote,
  ) async {
    final category = await _cacheAndFindRemoteCategory(remote);
    if (category == null) {
      throw const NetworkRequestException(
        'Categoria remota salva, mas o cache local nao retornou o espelho.',
      );
    }
    return category.id;
  }

  Future<Category?> _cacheAndFindRemoteCategory(
    RemoteCategoryRecord remote,
  ) async {
    await _localRepository.upsertFromRemote(remote);
    return _localRepository
        .findByRemoteId(remote.remoteId)
        .timeout(const Duration(seconds: 8));
  }

  Future<void> _scheduleCacheMerge(
    List<RemoteCategoryRecord> remoteCategories,
  ) {
    final activeMerge = _cacheMergeInFlight;
    if (activeMerge != null) {
      return activeMerge;
    }

    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      '[CategoriasRepo] cache_merge_started count=${remoteCategories.length}',
    );
    final merge = _cacheRemoteCategories(remoteCategories).whenComplete(() {
      AppLogger.info(
        '[CategoriasRepo] cache_merge_finished duration_ms=${stopwatch.elapsedMilliseconds}',
      );
      _cacheMergeInFlight = null;
    });
    _cacheMergeInFlight = merge;
    return merge;
  }

  Future<void> _cacheRemoteCategories(
    List<RemoteCategoryRecord> remoteCategories,
  ) async {
    for (final remoteCategory in remoteCategories) {
      await _localRepository.upsertFromRemote(remoteCategory);
    }
  }

  Future<List<Category>> _readCachedRemoteCategories(
    List<RemoteCategoryRecord> remoteCategories, {
    required String query,
  }) async {
    final categories = <Category>[];
    for (final remoteCategory in remoteCategories) {
      final category = await _localRepository.findByRemoteId(
        remoteCategory.remoteId,
      );
      if (category != null &&
          category.deletedAt == null &&
          _matchesQuery(category, query)) {
        categories.add(category);
      }
    }
    categories.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return categories;
  }

  List<Category> _remoteCategoriesToEntities(
    List<RemoteCategoryRecord> records, {
    required String query,
  }) {
    final categories = records
        .map(_remoteCategoryToEntity)
        .where((category) => category.deletedAt == null)
        .where((category) => _matchesQuery(category, query))
        .toList(growable: false);
    categories.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return categories;
  }

  Category _remoteCategoryToEntity(RemoteCategoryRecord remote) {
    return Category(
      id: _remotePlaceholderId(remote.remoteId),
      uuid: remote.localUuid,
      name: remote.name,
      description: remote.description,
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

  RemoteCategoryRecord _remoteCategoryFromInput(
    CategoryInput input, {
    String? localUuid,
    String remoteId = '',
    DateTime? createdAt,
  }) {
    final now = DateTime.now();
    return RemoteCategoryRecord(
      remoteId: remoteId,
      localUuid: localUuid ?? IdGenerator.next(),
      name: input.name,
      description: input.description,
      isActive: input.isActive,
      createdAt: createdAt ?? now,
      updatedAt: now,
      deletedAt: input.isActive ? null : now,
    );
  }

  bool _matchesQuery(Category category, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return category.name.toLowerCase().contains(normalized) ||
        (category.description?.toLowerCase().contains(normalized) ?? false);
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
