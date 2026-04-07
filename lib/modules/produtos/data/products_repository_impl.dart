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
import '../../categorias/data/sqlite_category_repository.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/product_repository.dart';
import 'datasources/products_remote_datasource.dart';
import 'models/remote_product_record.dart';
import 'sqlite_product_repository.dart';

class ProductsRepositoryImpl
    implements ProductRepository, SyncFeatureProcessor {
  const ProductsRepositoryImpl({
    required SqliteProductRepository localRepository,
    required SqliteCategoryRepository localCategoryRepository,
    required ProductsRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _localCategoryRepository = localCategoryRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteProductRepository _localRepository;
  final SqliteCategoryRepository _localCategoryRepository;
  final ProductsRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteProductRepository.featureKey;

  @override
  String get displayName => 'Produtos';

  @override
  Future<int> create(ProductInput input) {
    return _localRepository.create(input);
  }

  @override
  Future<void> delete(int id) {
    return _localRepository.delete(id);
  }

  @override
  Future<List<Product>> search({String query = ''}) {
    return _localRepository.search(query: query);
  }

  @override
  Future<List<Product>> searchAvailable({String query = ''}) {
    return _localRepository.searchAvailable(query: query);
  }

  Future<SyncActionResult> syncNow({bool retryOnly = false}) async {
    _ensureSyncIsAllowed();

    final startedAt = DateTime.now();
    var pushedCount = 0;
    var pulledCount = 0;
    var failedCount = 0;
    String? message;

    await _remoteDatasource.canReachRemote();

    final localProducts = await _localRepository.listForSync();
    for (final product in localProducts.where(
      (product) => _shouldPush(product, retryOnly: retryOnly),
    )) {
      try {
        if (product.deletedAt != null && product.remoteId != null) {
          await _remoteDatasource.delete(product.remoteId!);
          await _localRepository.upsertFromRemote(
            await _toRemoteRecord(product),
          );
        } else {
          final remoteRecord = await _toRemoteRecord(product);
          final persisted = product.remoteId == null
              ? await _remoteDatasource.create(remoteRecord)
              : await _remoteDatasource.update(product.remoteId!, remoteRecord);

          await _localRepository.applyPushResult(
            product: product,
            remote: persisted,
          );
        }
        pushedCount++;
      } on NetworkRequestException catch (error) {
        final canRecover =
            product.remoteId != null &&
            SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
        if (canRecover) {
          await _localRepository.recoverMissingRemoteIdentity(product: product);
          failedCount++;
          continue;
        }

        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          product: product,
          message: syncError.message,
          errorType: syncError.type,
        );
      } catch (error) {
        final syncError = resolveSyncError(error);
        failedCount++;
        await _localRepository.markSyncError(
          product: product,
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
        .where((product) => product.syncStatus == SyncStatus.synced)
        .length;

    return SyncActionResult(
      featureKey: SqliteProductRepository.featureKey,
      displayName: 'Produtos',
      pushedCount: pushedCount,
      pulledCount: pulledCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      message:
          message ??
          (failedCount == 0
              ? 'Produtos sincronizados com sucesso.'
              : 'Sincronizacao de produtos concluida com falhas parciais.'),
    );
  }

  @override
  Future<void> update(int id, ProductInput input) {
    return _localRepository.update(id, input);
  }

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final product = await _localRepository.findById(
      item.localEntityId,
      includeDeleted: true,
    );
    if (product == null) {
      return const SyncFeatureProcessResult.synced();
    }

    if (item.operation != SyncQueueOperation.delete &&
        product.deletedAt == null) {
      final dependencyReason = await _dependencyBlockReason(product);
      if (dependencyReason != null) {
        return SyncFeatureProcessResult.blocked(reason: dependencyReason);
      }
    }

    try {
      if (item.operation == SyncQueueOperation.update &&
          product.remoteId != null) {
        final conflict = await _detectConflict(product);
        if (conflict != null) {
          await _localRepository.markConflict(
            product: product,
            message: conflict.reason,
            detectedAt: DateTime.now(),
          );
          return SyncFeatureProcessResult.conflict(conflict: conflict);
        }
      }

      if (item.operation == SyncQueueOperation.delete ||
          product.deletedAt != null) {
        final remoteId = product.remoteId ?? item.remoteId;
        if (remoteId == null) {
          return const SyncFeatureProcessResult.synced();
        }

        await _remoteDatasource.delete(remoteId);
        await _localRepository.upsertFromRemote(await _toRemoteRecord(product));
        return SyncFeatureProcessResult.synced(remoteId: remoteId);
      }

      final remoteRecord = await _toRemoteRecord(product);
      final remoteId = product.remoteId ?? item.remoteId;
      final persisted =
          (remoteId == null || item.operation == SyncQueueOperation.create)
          ? await _remoteDatasource.create(remoteRecord)
          : await _remoteDatasource.update(remoteId, remoteRecord);

      await _localRepository.applyPushResult(
        product: product,
        remote: persisted,
      );
      return SyncFeatureProcessResult.synced(remoteId: persisted.remoteId);
    } on NetworkRequestException catch (error) {
      final canRecover =
          item.operation == SyncQueueOperation.update &&
          product.remoteId != null &&
          SyncRemoteIdentityRecovery.isRemoteIdentityMissing(error);
      if (!canRecover) {
        rethrow;
      }

      await _localRepository.recoverMissingRemoteIdentity(
        product: product,
        queueItem: item,
      );
      return const SyncFeatureProcessResult.requeued(
        reason:
            'Registro remoto antigo nao existe mais; o produto sera reenviado como criacao.',
      );
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remoteProducts = await _remoteDatasource.listAll();
    for (final remoteProduct in remoteProducts) {
      await _localRepository.upsertFromRemote(remoteProduct);
    }
    return remoteProducts.length;
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual de produtos.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar os produtos.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  bool _shouldPush(Product product, {required bool retryOnly}) {
    if (product.deletedAt != null && product.remoteId == null) {
      return false;
    }

    if (retryOnly) {
      return product.syncStatus == SyncStatus.pendingUpload ||
          product.syncStatus == SyncStatus.pendingUpdate ||
          product.syncStatus == SyncStatus.syncError;
    }

    return product.remoteId == null ||
        product.syncStatus == SyncStatus.localOnly ||
        product.syncStatus == SyncStatus.pendingUpload ||
        product.syncStatus == SyncStatus.pendingUpdate ||
        product.syncStatus == SyncStatus.syncError;
  }

  Future<RemoteProductRecord> _toRemoteRecord(Product product) async {
    String? remoteCategoryId;
    if (product.categoryId != null) {
      final category = await _localCategoryRepository.findById(
        product.categoryId!,
      );
      remoteCategoryId = category?.remoteId;
    }

    return RemoteProductRecord.fromLocalProduct(
      product,
      remoteCategoryId: remoteCategoryId,
    );
  }

  Future<String?> _dependencyBlockReason(Product product) async {
    if (product.categoryId == null) {
      return null;
    }

    final category = await _localCategoryRepository.findById(
      product.categoryId!,
      includeDeleted: true,
    );
    if (category == null) {
      return 'Dependencia remota ausente: a categoria local do produto nao esta mais disponivel.';
    }
    if (category.remoteId == null) {
      return 'Dependencia remota ausente: aguardando a categoria ser recriada no backend.';
    }

    return null;
  }

  Future<SyncConflictInfo?> _detectConflict(Product product) async {
    final lastSyncedAt = product.lastSyncedAt;
    if (lastSyncedAt == null || product.remoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchById(product.remoteId!);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = product.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason: 'Produto alterado localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: product.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }
}
