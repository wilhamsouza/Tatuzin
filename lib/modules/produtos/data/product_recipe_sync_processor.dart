import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sync_conflict_info.dart';
import '../../../app/core/sync/sync_error_info.dart';
import '../../../app/core/sync/sync_feature_processor.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import 'datasources/product_recipes_remote_datasource.dart';
import 'models/remote_product_recipe_record.dart';
import 'models/product_recipe_sync_payload.dart';
import 'sqlite_product_repository.dart';

class ProductRecipeSyncProcessor implements SyncFeatureProcessor {
  const ProductRecipeSyncProcessor({
    required SqliteProductRepository localRepository,
    required ProductRecipesRemoteDatasource remoteDatasource,
    required AppOperationalContext operationalContext,
    required DataAccessPolicy dataAccessPolicy,
  }) : _localRepository = localRepository,
       _remoteDatasource = remoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteProductRepository _localRepository;
  final ProductRecipesRemoteDatasource _remoteDatasource;
  final AppOperationalContext _operationalContext;
  final DataAccessPolicy _dataAccessPolicy;

  @override
  String get featureKey => SqliteProductRepository.recipeFeatureKey;

  @override
  String get displayName => 'Fichas tecnicas';

  @override
  Future<void> ensureSyncAllowed() async {
    _ensureSyncIsAllowed();
    await _localRepository.seedPendingRecipeSyncIfNeeded();
    await _remoteDatasource.canReachRemote();
  }

  @override
  Future<SyncFeatureProcessResult> processQueueItem(SyncQueueItem item) async {
    final recipe = await _localRepository.findProductRecipeForSync(
      item.localEntityId,
    );
    if (recipe == null) {
      return const SyncFeatureProcessResult.synced();
    }

    final dependencyReason = _dependencyBlockReason(recipe);
    if (dependencyReason != null) {
      return SyncFeatureProcessResult.blocked(reason: dependencyReason);
    }

    if (item.operation == SyncQueueOperation.update &&
        recipe.productRemoteId != null &&
        recipe.productRemoteId!.isNotEmpty) {
      final conflict = await _detectConflict(recipe);
      if (conflict != null) {
        await _localRepository.markProductRecipeConflict(
          recipe: recipe,
          message: conflict.reason,
          detectedAt: DateTime.now(),
        );
        return SyncFeatureProcessResult.conflict(conflict: conflict);
      }
    }

    try {
      final remoteProductId = recipe.productRemoteId ?? item.remoteId;
      if (item.operation == SyncQueueOperation.delete || !recipe.hasItems) {
        if (remoteProductId == null || remoteProductId.isEmpty) {
          await _localRepository.clearProductRecipeSyncState(recipe.productId);
          return const SyncFeatureProcessResult.synced();
        }

        await _remoteDatasource.delete(remoteProductId);
        await _localRepository.clearProductRecipeSyncState(recipe.productId);
        return SyncFeatureProcessResult.synced(remoteId: remoteProductId);
      }

      if (remoteProductId == null || remoteProductId.isEmpty) {
        return const SyncFeatureProcessResult.blocked(
          reason:
              'Ficha tecnica aguardando o produto correspondente receber remoteId.',
        );
      }

      final persisted = await _remoteDatasource.upsert(
        remoteProductId,
        RemoteProductRecipeRecord.fromSyncPayload(recipe),
      );
      await _localRepository.applyProductRecipePushResult(
        recipe: recipe,
        remote: persisted,
      );
      return SyncFeatureProcessResult.synced(
        remoteId: persisted.productRemoteId,
      );
    } catch (error) {
      final syncError = resolveSyncError(error);
      await _localRepository.markProductRecipeSyncError(
        recipe: recipe,
        message: syncError.message,
        errorType: syncError.type,
      );
      rethrow;
    }
  }

  @override
  Future<int> pullRemoteSnapshot() async {
    final remoteRecipes = await _remoteDatasource.listAll();
    for (final remoteRecipe in remoteRecipes) {
      await _localRepository.upsertRecipeFromRemote(remoteRecipe);
    }
    return remoteRecipes.length;
  }

  void _ensureSyncIsAllowed() {
    if (!_dataAccessPolicy.allowRemoteWrite) {
      throw const ValidationException(
        'Ative o modo hibrido pronto para executar a sincronizacao manual das fichas tecnicas.',
      );
    }

    if (!_operationalContext.session.isRemoteAuthenticated ||
        _operationalContext.currentRemoteCompanyId == null) {
      throw const AuthenticationException(
        'Faca login remoto antes de sincronizar as fichas tecnicas.',
      );
    }

    final licenseRestriction = _operationalContext.cloudSyncRestrictionReason;
    if (licenseRestriction != null) {
      throw ValidationException(licenseRestriction);
    }
  }

  String? _dependencyBlockReason(ProductRecipeSyncPayload recipe) {
    final productRemoteId = recipe.productRemoteId;
    if (productRemoteId == null || productRemoteId.isEmpty) {
      return 'Ficha tecnica aguardando o produto correspondente ser recriado no backend.';
    }

    for (final item in recipe.items) {
      if (item.supplyRemoteId == null || item.supplyRemoteId!.isEmpty) {
        return 'Ficha tecnica aguardando o insumo vinculado receber remoteId.';
      }
    }

    return null;
  }

  Future<SyncConflictInfo?> _detectConflict(
    ProductRecipeSyncPayload recipe,
  ) async {
    final lastSyncedAt = recipe.lastSyncedAt;
    final productRemoteId = recipe.productRemoteId;
    if (lastSyncedAt == null || productRemoteId == null) {
      return null;
    }

    final remote = await _remoteDatasource.fetchByProductId(productRemoteId);
    final remoteIsNewer = remote.updatedAt.isAfter(lastSyncedAt);
    final localChangedSinceSync = recipe.updatedAt.isAfter(lastSyncedAt);
    if (!remoteIsNewer || !localChangedSinceSync) {
      return null;
    }

    return SyncConflictInfo(
      reason:
          'Ficha tecnica alterada localmente e remotamente desde o ultimo sync.',
      localUpdatedAt: recipe.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
  }
}
