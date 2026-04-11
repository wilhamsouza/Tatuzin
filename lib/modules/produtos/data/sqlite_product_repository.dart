import 'package:sqflite/sqflite.dart';

import '../../../app/core/app_context/record_identity.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sqlite_sync_queue_repository.dart';
import '../../../app/core/sync/sync_error_type.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/sync/sync_queue_item.dart';
import '../../../app/core/sync/sync_queue_operation.dart';
import '../../../app/core/sync/sync_remote_identity_recovery.dart';
import '../../../app/core/sync/sync_status.dart';
import '../../../app/core/utils/id_generator.dart';
import '../../categorias/data/sqlite_category_repository.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/product_repository.dart';
import 'models/remote_product_record.dart';

class SqliteProductRepository implements ProductRepository {
  SqliteProductRepository(
    this._appDatabase, {
    SqliteCategoryRepository? categoryRepository,
  }) : _syncMetadataRepository = SqliteSyncMetadataRepository(_appDatabase),
       _syncQueueRepository = SqliteSyncQueueRepository(_appDatabase),
       _remoteIdentityRecovery = SyncRemoteIdentityRecovery(_appDatabase),
       _categoryRepository =
           categoryRepository ?? SqliteCategoryRepository(_appDatabase);

  static const String featureKey = SyncFeatureKeys.products;

  final AppDatabase _appDatabase;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final SyncRemoteIdentityRecovery _remoteIdentityRecovery;
  final SqliteCategoryRepository _categoryRepository;

  @override
  Future<int> create(ProductInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    final uuid = IdGenerator.next();

    final resolvedStockMil = _resolveProductStockMil(
      input.stockMil,
      input.variants,
    );

    return database.transaction((txn) async {
      final id = await txn.insert(TableNames.produtos, {
        'uuid': uuid,
        'nome': input.name.trim(),
        'descricao': _cleanNullable(input.description),
        'categoria_id': input.categoryId,
        'foto_path': _resolvePrimaryPhotoPath(input.photos),
        'codigo_barras': _cleanNullable(input.barcode),
        'tipo_produto': input.productType,
        'nicho': _normalizeNiche(input.niche),
        'catalog_type': _normalizeCatalogType(input.catalogType),
        'model_name': _cleanNullable(input.modelName),
        'variant_label': _cleanNullable(input.variantLabel),
        'unidade_medida': input.unitMeasure.trim().isEmpty
            ? 'un'
            : input.unitMeasure.trim(),
        'custo_centavos': input.costCents,
        'preco_venda_centavos': input.salePriceCents,
        'estoque_mil': resolvedStockMil,
        'ativo': input.isActive ? 1 : 0,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'deletado_em': null,
      });

      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: uuid,
        createdAt: now,
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'product',
        localEntityId: id,
        localUuid: uuid,
        remoteId: null,
        operation: SyncQueueOperation.create,
        localUpdatedAt: now,
      );

      await _persistLocalCatalogStructure(
        txn: txn,
        productId: id,
        productUuid: uuid,
        input: input,
      );
      await _replaceProductPhotos(
        txn: txn,
        productId: id,
        photos: input.photos,
      );
      await _replaceProductVariants(
        txn: txn,
        productId: id,
        variants: input.variants,
      );
      return id;
    });
  }

  @override
  Future<void> delete(int id) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        return;
      }

      await txn.update(
        TableNames.produtos,
        {
          'ativo': 0,
          'deletado_em': now.toIso8601String(),
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: id,
      );

      if (metadata?.identity.remoteId == null) {
        await _syncMetadataRepository.removeByLocalId(
          txn,
          featureKey: featureKey,
          localId: id,
        );
        await _syncQueueRepository.removeForEntity(
          txn,
          featureKey: featureKey,
          localEntityId: id,
        );
        return;
      }

      final remoteId = metadata!.identity.remoteId;

      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: existing['uuid'] as String,
        remoteId: remoteId,
        createdAt: DateTime.parse(existing['criado_em'] as String),
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'product',
        localEntityId: id,
        localUuid: existing['uuid'] as String,
        remoteId: remoteId,
        operation: SyncQueueOperation.delete,
        localUpdatedAt: now,
      );
    });
  }

  @override
  Future<List<Product>> search({String query = ''}) {
    return _searchInternal(
      query: query,
      onlyAvailable: false,
      includeDeleted: false,
    );
  }

  @override
  Future<List<Product>> searchAvailable({String query = ''}) {
    return _searchInternal(
      query: query,
      onlyAvailable: true,
      includeDeleted: false,
      flattenSellableVariants: true,
    );
  }

  @override
  Future<void> update(int id, ProductInput input) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    final resolvedStockMil = _resolveProductStockMil(
      input.stockMil,
      input.variants,
    );

    await database.transaction((txn) async {
      final existing = await _findRowById(txn, id);
      if (existing == null) {
        return;
      }

      await txn.update(
        TableNames.produtos,
        {
          'nome': input.name.trim(),
          'descricao': _cleanNullable(input.description),
          'categoria_id': input.categoryId,
          'foto_path': _resolvePrimaryPhotoPath(input.photos),
          'codigo_barras': _cleanNullable(input.barcode),
          'nicho': _normalizeNiche(input.niche),
          'catalog_type': _normalizeCatalogType(input.catalogType),
          'model_name': _cleanNullable(input.modelName),
          'variant_label': _cleanNullable(input.variantLabel),
          'unidade_medida': input.unitMeasure.trim().isEmpty
              ? 'un'
              : input.unitMeasure.trim(),
          'custo_centavos': input.costCents,
          'preco_venda_centavos': input.salePriceCents,
          'estoque_mil': resolvedStockMil,
          'ativo': input.isActive ? 1 : 0,
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final metadata = await _syncMetadataRepository.findByLocalId(
        txn,
        featureKey: featureKey,
        localId: id,
      );

      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: featureKey,
        localId: id,
        localUuid: existing['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        createdAt: DateTime.parse(existing['criado_em'] as String),
        updatedAt: now,
      );
      await _syncQueueRepository.enqueueMutation(
        txn,
        featureKey: featureKey,
        entityType: 'product',
        localEntityId: id,
        localUuid: existing['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        operation: metadata?.identity.remoteId == null
            ? SyncQueueOperation.create
            : SyncQueueOperation.update,
        localUpdatedAt: now,
      );

      await _persistLocalCatalogStructure(
        txn: txn,
        productId: id,
        productUuid: existing['uuid'] as String,
        input: input,
      );
      await _replaceProductPhotos(
        txn: txn,
        productId: id,
        photos: input.photos,
      );
      await _replaceProductVariants(
        txn: txn,
        productId: id,
        variants: input.variants,
      );
    });
  }

  Future<List<Product>> listForSync() {
    return _searchInternal(
      query: '',
      onlyAvailable: false,
      includeDeleted: true,
    );
  }

  Future<Product?> findById(int id, {bool includeDeleted = true}) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectQuery(includeDeleted: includeDeleted)}'
      '''
        AND p.id = ?
        LIMIT 1
      ''',
      [id],
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapProduct(database, rows.first);
  }

  Future<List<ProductPhoto>> listProductPhotos(int productId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.produtoFotos,
      where: 'produto_id = ?',
      whereArgs: [productId],
      orderBy: 'ordem ASC, id ASC',
    );
    return rows.map(_mapProductPhoto).toList(growable: false);
  }

  Future<List<ProductVariant>> listProductVariants(int productId) async {
    final database = await _appDatabase.database;
    return _loadProductVariants(database, productId);
  }

  Future<Product?> findByRemoteId(String remoteId) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      '${_selectQuery(includeDeleted: true)}'
      '''
        AND sync.remote_id = ?
        LIMIT 1
      ''',
      [remoteId],
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapProduct(database, rows.first);
  }

  Future<void> upsertFromRemote(RemoteProductRecord remote) async {
    final database = await _appDatabase.database;
    await database.transaction((txn) async {
      final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
        txn,
        featureKey: featureKey,
        remoteId: remote.remoteId,
      );
      final metadataByLocalUuid = await _syncMetadataRepository.findByLocalUuid(
        txn,
        featureKey: featureKey,
        localUuid: remote.localUuid,
      );
      final metadata = metadataByRemoteId ?? metadataByLocalUuid;

      final mappedCategoryId = await _resolveLocalCategoryId(remote);

      int localId;
      String localUuid;
      DateTime createdAt;
      final syncedAt = DateTime.now();
      Map<String, Object?>? existing;

      if (metadata != null && metadata.identity.localId != null) {
        localId = metadata.identity.localId!;
        existing = await _findRowById(txn, localId);
      } else {
        existing = await _findRowByUuid(txn, remote.localUuid);
        localId = (existing?['id'] as int?) ?? -1;
      }

      if (existing != null) {
        final localUpdatedAt = DateTime.parse(
          existing['atualizado_em'] as String,
        );
        if (localUpdatedAt.isAfter(remote.updatedAt)) {
          await _syncMetadataRepository.markPendingUpdate(
            txn,
            featureKey: featureKey,
            localId: existing['id'] as int,
            localUuid: existing['uuid'] as String,
            remoteId: remote.remoteId,
            createdAt: DateTime.parse(existing['criado_em'] as String),
            updatedAt: localUpdatedAt,
          );
          await _syncQueueRepository.enqueueMutation(
            txn,
            featureKey: featureKey,
            entityType: 'product',
            localEntityId: existing['id'] as int,
            localUuid: existing['uuid'] as String,
            remoteId: remote.remoteId,
            operation: SyncQueueOperation.update,
            localUpdatedAt: localUpdatedAt,
          );
          return;
        }

        localUuid = existing['uuid'] as String;
        createdAt = DateTime.parse(existing['criado_em'] as String);
        localId = existing['id'] as int;

        await txn.update(
          TableNames.produtos,
          {
            'nome': remote.displayName,
            'descricao': remote.description,
            'categoria_id': mappedCategoryId,
            'codigo_barras': remote.barcode,
            'tipo_produto': remote.productType,
            'nicho': _normalizeNiche(remote.niche),
            'catalog_type': remote.catalogType,
            'model_name': remote.modelName,
            'variant_label': remote.variantLabel,
            'unidade_medida': remote.unitMeasure,
            'custo_centavos': remote.costCents,
            'preco_venda_centavos': remote.salePriceCents,
            'estoque_mil': _resolveRemoteStockMil(remote),
            'ativo': remote.isActive ? 1 : 0,
            'atualizado_em': remote.updatedAt.toIso8601String(),
            'deletado_em': remote.deletedAt?.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      } else {
        localUuid = remote.localUuid;
        createdAt = remote.createdAt;
        localId = await txn.insert(TableNames.produtos, {
          'uuid': localUuid,
          'nome': remote.displayName,
          'descricao': remote.description,
          'categoria_id': mappedCategoryId,
          'foto_path': null,
          'codigo_barras': remote.barcode,
          'tipo_produto': remote.productType,
          'nicho': _normalizeNiche(remote.niche),
          'catalog_type': remote.catalogType,
          'model_name': remote.modelName,
          'variant_label': remote.variantLabel,
          'unidade_medida': remote.unitMeasure,
          'custo_centavos': remote.costCents,
          'preco_venda_centavos': remote.salePriceCents,
          'estoque_mil': _resolveRemoteStockMil(remote),
          'ativo': remote.isActive ? 1 : 0,
          'criado_em': remote.createdAt.toIso8601String(),
          'atualizado_em': remote.updatedAt.toIso8601String(),
          'deletado_em': remote.deletedAt?.toIso8601String(),
        });
      }

      final remoteInput = _buildRemoteInput(remote, mappedCategoryId);
      await _persistLocalCatalogStructure(
        txn: txn,
        productId: localId,
        productUuid: localUuid,
        input: remoteInput,
      );
      await _replaceProductVariants(
        txn: txn,
        productId: localId,
        variants: remoteInput.variants,
      );
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: localId,
        localUuid: localUuid,
        remoteId: remote.remoteId,
        origin: existing == null ? RecordOrigin.remote : RecordOrigin.merged,
        createdAt: createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: syncedAt,
      );
    });
  }

  Future<void> applyPushResult({
    required Product product,
    required RemoteProductRecord remote,
  }) async {
    final database = await _appDatabase.database;
    final metadataByRemoteId = await _syncMetadataRepository.findByRemoteId(
      database,
      featureKey: featureKey,
      remoteId: remote.remoteId,
    );

    if (metadataByRemoteId != null &&
        metadataByRemoteId.identity.localId != null &&
        metadataByRemoteId.identity.localId != product.id) {
      await upsertFromRemote(remote);
      return;
    }

    final mappedCategoryId = await _resolveLocalCategoryId(remote);

    await database.transaction((txn) async {
      await txn.update(
        TableNames.produtos,
        {
          'nome': remote.displayName,
          'descricao': remote.description,
          'categoria_id': mappedCategoryId,
          'codigo_barras': remote.barcode,
          'tipo_produto': remote.productType,
          'nicho': _normalizeNiche(remote.niche),
          'catalog_type': remote.catalogType,
          'model_name': remote.modelName,
          'variant_label': remote.variantLabel,
          'unidade_medida': remote.unitMeasure,
          'custo_centavos': remote.costCents,
          'preco_venda_centavos': remote.salePriceCents,
          'estoque_mil': _resolveRemoteStockMil(remote),
          'ativo': remote.isActive ? 1 : 0,
          'atualizado_em': remote.updatedAt.toIso8601String(),
          'deletado_em': remote.deletedAt?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [product.id],
      );

      final remoteInput = _buildRemoteInput(remote, mappedCategoryId);
      await _persistLocalCatalogStructure(
        txn: txn,
        productId: product.id,
        productUuid: product.uuid,
        input: remoteInput,
      );
      await _replaceProductVariants(
        txn: txn,
        productId: product.id,
        variants: remoteInput.variants,
      );
      await _syncMetadataRepository.markSynced(
        txn,
        featureKey: featureKey,
        localId: product.id,
        localUuid: product.uuid,
        remoteId: remote.remoteId,
        origin: RecordOrigin.merged,
        createdAt: product.createdAt,
        updatedAt: remote.updatedAt,
        syncedAt: DateTime.now(),
      );
    });
  }

  Future<void> markSyncError({
    required Product product,
    required String message,
    required SyncErrorType errorType,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now();

    await database.transaction((txn) async {
      await _syncMetadataRepository.markSyncError(
        txn,
        featureKey: featureKey,
        localId: product.id,
        localUuid: product.uuid,
        remoteId: product.remoteId,
        createdAt: product.createdAt,
        updatedAt: now,
        message: message,
        errorType: errorType,
      );
    });
  }

  Future<void> markConflict({
    required Product product,
    required String message,
    required DateTime detectedAt,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((txn) async {
      await _syncMetadataRepository.markConflict(
        txn,
        featureKey: featureKey,
        localId: product.id,
        localUuid: product.uuid,
        remoteId: product.remoteId,
        createdAt: product.createdAt,
        updatedAt: detectedAt,
        message: message,
      );
    });
  }

  Future<void> recoverMissingRemoteIdentity({
    required Product product,
    SyncQueueItem? queueItem,
  }) async {
    await _remoteIdentityRecovery.recoverForReupload(
      featureKey: featureKey,
      entityType: queueItem?.entityType ?? 'product',
      localEntityId: product.id,
      localUuid: product.uuid,
      staleRemoteId: product.remoteId ?? queueItem?.remoteId,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
      queueItem: queueItem,
      entityLabel: 'produto "${product.displayName}"',
    );
  }

  Future<List<Product>> _searchInternal({
    required String query,
    required bool onlyAvailable,
    required bool includeDeleted,
    bool flattenSellableVariants = false,
  }) async {
    final database = await _appDatabase.database;
    final trimmedQuery = query.trim();
    final args = <Object?>[];
    final buffer = StringBuffer(_selectQuery(includeDeleted: includeDeleted));

    if (onlyAvailable) {
      buffer.write(' AND p.ativo = 1 AND p.estoque_mil > 0');
    }

    if (trimmedQuery.isNotEmpty) {
      buffer.write(
        ' AND ('
        'p.nome LIKE ? COLLATE NOCASE '
        'OR COALESCE(p.model_name, \'\') LIKE ? COLLATE NOCASE '
        'OR COALESCE(p.variant_label, \'\') LIKE ? COLLATE NOCASE '
        'OR COALESCE(pb.nome, \'\') LIKE ? COLLATE NOCASE '
        'OR COALESCE(variant_attrs.serialized_attrs, \'\') LIKE ? COLLATE NOCASE '
        'OR COALESCE(variant_index.serialized_variants, \'\') LIKE ? COLLATE NOCASE '
        'OR COALESCE(p.codigo_barras, \'\') LIKE ? COLLATE NOCASE'
        ')',
      );
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
    }

    buffer.write(
      ' ORDER BY '
      'COALESCE(NULLIF(pb.nome, \'\'), NULLIF(p.model_name, \'\'), p.nome) COLLATE NOCASE ASC, '
      'COALESCE(NULLIF(p.variant_label, \'\'), p.nome) COLLATE NOCASE ASC, '
      'p.nome COLLATE NOCASE ASC, '
      'p.id ASC',
    );

    final rows = await database.rawQuery(buffer.toString(), args);
    final products = <Product>[];
    for (final row in rows) {
      products.add(await _mapProduct(database, row));
    }

    if (!flattenSellableVariants) {
      return products;
    }

    return _flattenSellableProducts(products);
  }

  String _selectQuery({required bool includeDeleted}) {
    final buffer = StringBuffer('''
      SELECT
        p.*,
        c.nome AS categoria_nome,
        pb.id AS produto_base_id,
        pb.nome AS produto_base_nome,
        COALESCE(variant_attrs.serialized_attrs, '') AS variant_attributes_serialized,
        COALESCE(variant_index.serialized_variants, '') AS variant_index_serialized,
        COALESCE(mod_groups.serialized_groups, '') AS modifier_groups_serialized,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at
      FROM ${TableNames.produtos} p
      LEFT JOIN ${TableNames.categorias} c
        ON c.id = p.categoria_id
        AND c.deletado_em IS NULL
      LEFT JOIN ${TableNames.produtosBaseVariantes} pbv
        ON pbv.produto_id = p.id
      LEFT JOIN ${TableNames.produtosBase} pb
        ON pb.id = pbv.produto_base_id
      LEFT JOIN (
        SELECT
          a.produto_id,
          GROUP_CONCAT(a.chave || '=' || a.valor, '||') AS serialized_attrs
        FROM ${TableNames.produtoVarianteAtributos} a
        GROUP BY a.produto_id
      ) variant_attrs
        ON variant_attrs.produto_id = p.id
      LEFT JOIN (
        SELECT
          v.produto_id,
          GROUP_CONCAT(
            COALESCE(v.sku, '') || ' ' || COALESCE(v.tamanho, '') || ' ' || COALESCE(v.cor, ''),
            '||'
          ) AS serialized_variants
        FROM ${TableNames.produtoVariantes} v
        WHERE v.ativo = 1
        GROUP BY v.produto_id
      ) variant_index
        ON variant_index.produto_id = p.id
      LEFT JOIN (
        SELECT
          g.produto_base_id,
          GROUP_CONCAT(
            g.nome || '::' || g.obrigatorio || '::' || g.min_selecoes || '::' ||
            COALESCE(g.max_selecoes, '') || '::' || COALESCE(group_option_counts.total_opcoes, 0),
            '||'
          ) AS serialized_groups
        FROM ${TableNames.gruposModificadores} g
        LEFT JOIN (
          SELECT
            o.grupo_modificador_id,
            COUNT(*) AS total_opcoes
          FROM ${TableNames.opcoesModificadores} o
          GROUP BY o.grupo_modificador_id
        ) group_option_counts
          ON group_option_counts.grupo_modificador_id = g.id
        WHERE g.ativo = 1
        GROUP BY g.produto_base_id
      ) mod_groups
        ON mod_groups.produto_base_id = pb.id
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = p.id
      WHERE 1 = 1
    ''');

    if (!includeDeleted) {
      buffer.write(' AND p.deletado_em IS NULL');
    }

    return buffer.toString();
  }

  Future<Map<String, Object?>?> _findRowById(
    DatabaseExecutor db,
    int id,
  ) async {
    final rows = await db.query(
      TableNames.produtos,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<Map<String, Object?>?> _findRowByUuid(
    DatabaseExecutor db,
    String uuid,
  ) async {
    final rows = await db.query(
      TableNames.produtos,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<int?> _resolveLocalCategoryId(RemoteProductRecord remote) async {
    if (remote.remoteCategoryId == null || remote.remoteCategoryId!.isEmpty) {
      return null;
    }

    final category = await _categoryRepository.findByRemoteId(
      remote.remoteCategoryId!,
    );
    return category?.id;
  }

  int _resolveProductStockMil(
    int fallbackStockMil,
    List<ProductVariantInput> variants,
  ) {
    if (variants.isEmpty) {
      return fallbackStockMil;
    }

    return variants.fold<int>(
      0,
      (total, variant) => total + (variant.isActive ? variant.stockMil : 0),
    );
  }

  int _resolveRemoteStockMil(RemoteProductRecord remote) {
    if (remote.variants.isEmpty) {
      return remote.stockMil;
    }

    return remote.variants.fold<int>(
      0,
      (total, variant) => total + (variant.isActive ? variant.stockMil : 0),
    );
  }

  ProductInput _buildRemoteInput(RemoteProductRecord remote, int? categoryId) {
    final variantInputs = remote.variants
        .map(
          (variant) => ProductVariantInput(
            sku: variant.sku,
            colorLabel: variant.colorLabel,
            sizeLabel: variant.sizeLabel,
            priceAdditionalCents: variant.priceAdditionalCents,
            stockMil: variant.stockMil,
            sortOrder: variant.sortOrder,
            isActive: variant.isActive,
          ),
        )
        .toList(growable: false);

    final modifierGroups = remote.modifierGroups
        .map(
          (group) => ProductModifierGroupInput(
            name: group.name,
            isRequired: group.isRequired,
            minSelections: group.minSelections,
            maxSelections: group.maxSelections,
            options: group.options
                .map(
                  (option) => ProductModifierOptionInput(
                    name: option.name,
                    adjustmentType: option.adjustmentType,
                    priceDeltaCents: option.priceDeltaCents,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    return ProductInput(
      name: remote.name,
      description: remote.description,
      categoryId: categoryId,
      barcode: remote.barcode,
      photos: const <ProductPhotoInput>[],
      variants: variantInputs,
      niche: remote.niche,
      catalogType: remote.catalogType,
      modelName: remote.modelName,
      variantLabel: remote.variantLabel,
      variantAttributes: const <ProductVariantAttributeInput>[],
      modifierGroups: modifierGroups,
      unitMeasure: remote.unitMeasure,
      costCents: remote.costCents,
      salePriceCents: remote.salePriceCents,
      stockMil: _resolveRemoteStockMil(remote),
      isActive: remote.isActive,
    );
  }

  Future<void> _persistLocalCatalogStructure({
    required DatabaseExecutor txn,
    required int productId,
    required String productUuid,
    required ProductInput input,
  }) async {
    final baseProductId = await _resolveOrCreateBaseProductId(
      txn: txn,
      productUuid: productUuid,
      input: input,
    );
    if (baseProductId == null) {
      return;
    }

    await _upsertBaseVariantLink(
      txn: txn,
      productId: productId,
      productUuid: productUuid,
      baseProductId: baseProductId,
    );
    await _replaceVariantAttributes(
      txn: txn,
      productId: productId,
      productUuid: productUuid,
      input: input,
    );

    if (input.modifierGroups != null) {
      await _replaceModifierGroups(
        txn: txn,
        baseProductId: baseProductId,
        modifierGroups: input.modifierGroups!,
      );
    }
  }

  Future<int?> _resolveOrCreateBaseProductId({
    required DatabaseExecutor txn,
    required String productUuid,
    required ProductInput input,
  }) async {
    if (input.baseProductId != null) {
      return input.baseProductId;
    }

    final modelName = _cleanNullable(input.modelName);
    final explicitBaseName = _cleanNullable(modelName ?? input.name);
    if (explicitBaseName == null) {
      return null;
    }

    final existing = await txn.query(
      TableNames.produtosBase,
      columns: const ['id'],
      where: 'nome = ? AND categoria_id IS ?',
      whereArgs: [explicitBaseName, input.categoryId],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }

    final now = DateTime.now().toIso8601String();
    return txn.insert(TableNames.produtosBase, {
      'uuid': 'base:$productUuid',
      'nome': explicitBaseName,
      'descricao': _cleanNullable(input.description),
      'categoria_id': input.categoryId,
      'ativo': input.isActive ? 1 : 0,
      'criado_em': now,
      'atualizado_em': now,
    });
  }

  Future<void> _upsertBaseVariantLink({
    required DatabaseExecutor txn,
    required int productId,
    required String productUuid,
    required int baseProductId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await txn.delete(
      TableNames.produtosBaseVariantes,
      where: 'produto_id = ?',
      whereArgs: [productId],
    );
    await txn.insert(TableNames.produtosBaseVariantes, {
      'uuid': 'link:$productUuid',
      'produto_base_id': baseProductId,
      'produto_id': productId,
      'criado_em': now,
      'atualizado_em': now,
    });
  }

  Future<void> _replaceVariantAttributes({
    required DatabaseExecutor txn,
    required int productId,
    required String productUuid,
    required ProductInput input,
  }) async {
    final now = DateTime.now().toIso8601String();
    await txn.delete(
      TableNames.produtoVarianteAtributos,
      where: 'produto_id = ?',
      whereArgs: [productId],
    );

    final attributes = _normalizeVariantAttributes(input);
    for (final attribute in attributes) {
      await txn.insert(
        TableNames.produtoVarianteAtributos,
        {
          'uuid': 'attr:${attribute.key}:$productUuid',
          'produto_id': productId,
          'chave': attribute.key,
          'valor': attribute.value,
          'criado_em': now,
          'atualizado_em': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  List<ProductVariantAttributeInput> _normalizeVariantAttributes(
    ProductInput input,
  ) {
    final normalized = <ProductVariantAttributeInput>[];
    final keys = <String>{};

    void addAttribute(String key, String? value) {
      final normalizedKey = key.trim().toLowerCase();
      final normalizedValue = _cleanNullable(value);
      if (normalizedKey.isEmpty || normalizedValue == null) {
        return;
      }
      if (!keys.add(normalizedKey)) {
        return;
      }
      normalized.add(
        ProductVariantAttributeInput(
          key: normalizedKey,
          value: normalizedValue,
        ),
      );
    }

    for (final attribute in input.variantAttributes) {
      addAttribute(attribute.key, attribute.value);
    }

    addAttribute('model', input.modelName);
    addAttribute('variant', input.variantLabel);

    return normalized;
  }

  Future<void> _replaceModifierGroups({
    required DatabaseExecutor txn,
    required int baseProductId,
    required List<ProductModifierGroupInput> modifierGroups,
  }) async {
    final now = DateTime.now().toIso8601String();

    final existing = await txn.query(
      TableNames.gruposModificadores,
      columns: const ['id'],
      where: 'produto_base_id = ?',
      whereArgs: [baseProductId],
    );

    final existingGroupIds = existing
        .map((row) => row['id'])
        .whereType<int>()
        .toList(growable: false);

    if (existingGroupIds.isNotEmpty) {
      final placeholders = List.filled(existingGroupIds.length, '?').join(',');
      await txn.delete(
        TableNames.opcoesModificadores,
        where: 'grupo_modificador_id IN ($placeholders)',
        whereArgs: existingGroupIds,
      );
      await txn.delete(
        TableNames.gruposModificadores,
        where: 'id IN ($placeholders)',
        whereArgs: existingGroupIds,
      );
    }

    for (final group in modifierGroups) {
      final groupName = group.name.trim();
      if (groupName.isEmpty) {
        continue;
      }

      final groupId = await txn.insert(TableNames.gruposModificadores, {
        'uuid': IdGenerator.next(),
        'produto_base_id': baseProductId,
        'nome': groupName,
        'obrigatorio': group.isRequired ? 1 : 0,
        'min_selecoes': group.minSelections,
        'max_selecoes': group.maxSelections,
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });

      var order = 0;
      for (final option in group.options) {
        final optionName = option.name.trim();
        if (optionName.isEmpty) {
          continue;
        }
        await txn.insert(TableNames.opcoesModificadores, {
          'uuid': IdGenerator.next(),
          'grupo_modificador_id': groupId,
          'nome': optionName,
          'tipo_ajuste': option.adjustmentType == 'remove' ? 'remove' : 'add',
          'preco_delta_centavos': option.priceDeltaCents,
          'linked_produto_id': null,
          'ativo': 1,
          'ordem': order,
          'criado_em': now,
          'atualizado_em': now,
        });
        order++;
      }
    }
  }

  Future<Product> _mapProduct(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final variantAttributes = _parseVariantAttributes(
      row['variant_attributes_serialized'] as String?,
    );
    final modifierGroups = await _loadProductModifierGroups(
      db,
      row['produto_base_id'] as int?,
    );
    final variants = await _loadProductVariants(db, row['id'] as int);

    return Product(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      name: row['nome'] as String,
      description: row['descricao'] as String?,
      categoryId: row['categoria_id'] as int?,
      categoryName: row['categoria_nome'] as String?,
      barcode: row['codigo_barras'] as String?,
      primaryPhotoPath: row['foto_path'] as String?,
      productType: row['tipo_produto'] as String,
      niche: _normalizeNiche(row['nicho'] as String?),
      catalogType:
          (row['catalog_type'] as String?) ?? ProductCatalogTypes.simple,
      modelName: row['model_name'] as String?,
      variantLabel: row['variant_label'] as String?,
      baseProductId: row['produto_base_id'] as int?,
      baseProductName: row['produto_base_nome'] as String?,
      variantAttributes: variantAttributes,
      variants: variants,
      modifierGroups: modifierGroups,
      unitMeasure: row['unidade_medida'] as String,
      costCents: row['custo_centavos'] as int,
      salePriceCents: row['preco_venda_centavos'] as int,
      stockMil: row['estoque_mil'] as int,
      isActive: (row['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
      deletedAt: row['deletado_em'] == null
          ? null
          : DateTime.parse(row['deletado_em'] as String),
      remoteId: row['sync_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(row['sync_status'] as String?),
      lastSyncedAt: row['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(row['sync_last_synced_at'] as String),
    );
  }

  Future<List<ProductVariant>> _loadProductVariants(
    DatabaseExecutor db,
    int productId,
  ) async {
    final rows = await db.query(
      TableNames.produtoVariantes,
      where: 'produto_id = ?',
      whereArgs: [productId],
      orderBy: 'ordem ASC, id ASC',
    );

    return rows.map(_mapProductVariant).toList(growable: false);
  }

  ProductVariant _mapProductVariant(Map<String, Object?> row) {
    return ProductVariant(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      productId: row['produto_id'] as int,
      sku: row['sku'] as String? ?? '',
      colorLabel: row['cor'] as String? ?? '',
      sizeLabel: row['tamanho'] as String? ?? '',
      priceAdditionalCents: row['preco_adicional_centavos'] as int? ?? 0,
      stockMil: row['estoque_mil'] as int? ?? 0,
      sortOrder: row['ordem'] as int? ?? 0,
      isActive: (row['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }

  Future<List<ProductModifierGroup>> _loadProductModifierGroups(
    DatabaseExecutor db,
    int? baseProductId,
  ) async {
    if (baseProductId == null) {
      return const <ProductModifierGroup>[];
    }

    final groupRows = await db.query(
      TableNames.gruposModificadores,
      where: 'produto_base_id = ? AND ativo = 1',
      whereArgs: [baseProductId],
      orderBy: 'id ASC',
    );

    final groups = <ProductModifierGroup>[];
    for (final groupRow in groupRows) {
      final groupId = groupRow['id'] as int;
      final optionRows = await db.query(
        TableNames.opcoesModificadores,
        where: 'grupo_modificador_id = ? AND ativo = 1',
        whereArgs: [groupId],
        orderBy: 'ordem ASC, id ASC',
      );
      groups.add(
        ProductModifierGroup(
          name: groupRow['nome'] as String? ?? '',
          isRequired: (groupRow['obrigatorio'] as int? ?? 0) == 1,
          minSelections: groupRow['min_selecoes'] as int? ?? 0,
          maxSelections: groupRow['max_selecoes'] as int?,
          options: optionRows
              .map(
                (optionRow) => ProductModifierOption(
                  name: optionRow['nome'] as String? ?? '',
                  adjustmentType: optionRow['tipo_ajuste'] as String? ?? 'add',
                  priceDeltaCents:
                      optionRow['preco_delta_centavos'] as int? ?? 0,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    return groups;
  }

  List<Product> _flattenSellableProducts(List<Product> products) {
    final sellable = <Product>[];
    for (final product in products) {
      final activeVariants = product.variants
          .where((variant) => variant.isActive && variant.stockMil > 0)
          .toList(growable: false);
      if (activeVariants.isEmpty) {
        if (product.stockMil > 0) {
          sellable.add(product);
        }
        continue;
      }

      for (final variant in activeVariants) {
        sellable.add(
          Product(
            id: product.id,
            uuid: product.uuid,
            name: product.name,
            description: product.description,
            categoryId: product.categoryId,
            categoryName: product.categoryName,
            barcode: product.barcode,
            primaryPhotoPath: product.primaryPhotoPath,
            productType: product.productType,
            niche: product.niche,
            catalogType: product.catalogType,
            modelName: product.modelName,
            variantLabel: product.variantLabel,
            baseProductId: product.baseProductId,
            baseProductName: product.baseProductName,
            variantAttributes: product.variantAttributes,
            variants: product.variants,
            modifierGroups: product.modifierGroups,
            sellableVariantId: variant.id,
            sellableVariantSku: variant.sku,
            sellableVariantColorLabel: variant.colorLabel,
            sellableVariantSizeLabel: variant.sizeLabel,
            sellableVariantPriceAdditionalCents: variant.priceAdditionalCents,
            unitMeasure: product.unitMeasure,
            costCents: product.costCents,
            salePriceCents:
                product.salePriceCents + variant.priceAdditionalCents,
            stockMil: variant.stockMil,
            isActive: product.isActive,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            deletedAt: product.deletedAt,
            remoteId: product.remoteId,
            syncStatus: product.syncStatus,
            lastSyncedAt: product.lastSyncedAt,
          ),
        );
      }
    }

    return sellable;
  }

  List<ProductVariantAttribute> _parseVariantAttributes(String? serialized) {
    if (serialized == null || serialized.trim().isEmpty) {
      return const <ProductVariantAttribute>[];
    }

    final attributes = <ProductVariantAttribute>[];
    final entries = serialized.split('||');
    for (final entry in entries) {
      final separator = entry.indexOf('=');
      if (separator <= 0 || separator >= entry.length - 1) {
        continue;
      }
      final key = entry.substring(0, separator).trim();
      final value = entry.substring(separator + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      attributes.add(ProductVariantAttribute(key: key, value: value));
    }
    return attributes;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _resolvePrimaryPhotoPath(List<ProductPhotoInput> photos) {
    if (photos.isEmpty) {
      return null;
    }

    for (final photo in photos) {
      final cleanedPath = _cleanNullable(photo.localPath);
      if (photo.isPrimary && cleanedPath != null) {
        return cleanedPath;
      }
    }

    return _cleanNullable(photos.first.localPath);
  }

  String _normalizeCatalogType(String? value) {
    return ProductCatalogTypes.normalize(value);
  }

  String _normalizeNiche(String? value) {
    return ProductNiches.normalize(value);
  }

  Future<void> _replaceProductPhotos({
    required DatabaseExecutor txn,
    required int productId,
    required List<ProductPhotoInput> photos,
  }) async {
    await txn.delete(
      TableNames.produtoFotos,
      where: 'produto_id = ?',
      whereArgs: [productId],
    );

    final normalized = <ProductPhotoInput>[];
    for (var index = 0; index < photos.length; index++) {
      final cleanedPath = _cleanNullable(photos[index].localPath);
      if (cleanedPath == null) {
        continue;
      }
      normalized.add(
        ProductPhotoInput(
          localPath: cleanedPath,
          isPrimary: photos[index].isPrimary,
          sortOrder: index,
        ),
      );
    }

    for (var index = 0; index < normalized.length; index++) {
      final photo = normalized[index];
      await txn.insert(TableNames.produtoFotos, {
        'uuid': IdGenerator.next(),
        'produto_id': productId,
        'caminho_local': photo.localPath,
        'e_principal': (photo.isPrimary || index == 0) ? 1 : 0,
        'ordem': index,
        'criado_em': DateTime.now().toIso8601String(),
        'atualizado_em': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _replaceProductVariants({
    required DatabaseExecutor txn,
    required int productId,
    required List<ProductVariantInput> variants,
  }) async {
    await txn.delete(
      TableNames.produtoVariantes,
      where: 'produto_id = ?',
      whereArgs: [productId],
    );

    for (var index = 0; index < variants.length; index++) {
      final variant = variants[index];
      final sizeLabel = _cleanNullable(variant.sizeLabel);
      final colorLabel = _cleanNullable(variant.colorLabel);
      final sku = _cleanNullable(variant.sku);
      if (sizeLabel == null || colorLabel == null || sku == null) {
        continue;
      }
      final now = DateTime.now().toIso8601String();
      await txn.insert(TableNames.produtoVariantes, {
        'uuid': IdGenerator.next(),
        'produto_id': productId,
        'sku': sku.toUpperCase(),
        'cor': colorLabel,
        'tamanho': sizeLabel,
        'preco_adicional_centavos': variant.priceAdditionalCents,
        'estoque_mil': variant.stockMil,
        'ordem': variant.sortOrder == 0 ? index : variant.sortOrder,
        'ativo': variant.isActive ? 1 : 0,
        'criado_em': now,
        'atualizado_em': now,
      });
    }
  }

  ProductPhoto _mapProductPhoto(Map<String, Object?> row) {
    return ProductPhoto(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      productId: row['produto_id'] as int,
      localPath: row['caminho_local'] as String,
      isPrimary: (row['e_principal'] as int? ?? 0) == 1,
      sortOrder: row['ordem'] as int? ?? 0,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }
}
