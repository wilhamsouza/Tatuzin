import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/app_context/data_access_policy.dart';
import '../../../app/core/utils/app_logger.dart';
import '../../produtos/data/datasources/products_remote_datasource.dart';
import '../../produtos/data/sqlite_product_repository.dart';
import '../domain/entities/inventory_adjustment_input.dart';
import '../domain/entities/inventory_item.dart';
import '../domain/entities/inventory_movement.dart';
import '../domain/repositories/inventory_repository.dart';
import 'sqlite_inventory_repository.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  const InventoryRepositoryImpl({
    required SqliteInventoryRepository localRepository,
    SqliteProductRepository? localProductRepository,
    ProductsRemoteDatasource? productsRemoteDatasource,
    AppOperationalContext? operationalContext,
    DataAccessPolicy? dataAccessPolicy,
  }) : _localRepository = localRepository,
       _localProductRepository = localProductRepository,
       _productsRemoteDatasource = productsRemoteDatasource,
       _operationalContext = operationalContext,
       _dataAccessPolicy = dataAccessPolicy;

  final SqliteInventoryRepository _localRepository;
  final SqliteProductRepository? _localProductRepository;
  final ProductsRemoteDatasource? _productsRemoteDatasource;
  final AppOperationalContext? _operationalContext;
  final DataAccessPolicy? _dataAccessPolicy;

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) {
    return _localRepository.adjustStock(input);
  }

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) async {
    await _refreshRemoteProductStockSnapshotIfAvailable();
    return _localRepository
        .findItem(productId: productId, productVariantId: productVariantId)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) async {
    await _refreshRemoteProductStockSnapshotIfAvailable();
    return _localRepository
        .listItems(query: query, filter: filter)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) {
    return _localRepository.listMovements(
      productId: productId,
      productVariantId: productVariantId,
      includeVariantsForProduct: includeVariantsForProduct,
      movementType: movementType,
      createdFrom: createdFrom,
      createdTo: createdTo,
      limit: limit,
    );
  }

  bool get _shouldUseErpRemoteRead {
    final policy = _dataAccessPolicy;
    final context = _operationalContext;
    return policy != null &&
        context != null &&
        policy.strategyFor(AppModule.erp) == DataSourceStrategy.serverFirst &&
        context.canUseCloudReads;
  }

  Future<void> _refreshRemoteProductStockSnapshotIfAvailable() async {
    if (!_shouldUseErpRemoteRead ||
        _productsRemoteDatasource == null ||
        _localProductRepository == null) {
      return;
    }

    try {
      final remoteProducts = await _productsRemoteDatasource.listAll().timeout(
        const Duration(seconds: 15),
      );
      for (final remoteProduct in remoteProducts) {
        await _localProductRepository
            .upsertFromRemote(remoteProduct)
            .timeout(const Duration(seconds: 8));
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'Estoque ERP server-first sem endpoint dedicado; falha ao atualizar snapshot remoto de produtos. Usando cache local.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
