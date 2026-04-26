import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_sync_metadata_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_sync_queue_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sync_metadata.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_operation.dart';
import 'package:erp_pdv_app/modules/carrinho/domain/entities/cart_item.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_movement.dart';
import 'package:erp_pdv_app/modules/historico_vendas/data/sqlite_sale_return_repository.dart';
import 'package:erp_pdv_app/modules/vendas/data/sqlite_sale_repository.dart';

void initializeSaleInventoryTestSupport() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
}

Future<Database> openSaleInventoryTestDatabase({
  bool includeInventoryMovements = true,
}) {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await _createSchema(
          db,
          includeInventoryMovements: includeInventoryMovements,
        );
      },
    ),
  );
}

SqliteSaleRepository createSaleRepository(Database database) {
  return SqliteSaleRepository.forDatabase(
    databaseLoader: () async => database,
    operationalContext: AppOperationalContext(
      environment: const AppEnvironment.localDefault(),
      session: AppSession.localDefault(),
    ),
    syncMetadataRepository: _NoopSyncMetadataRepository(),
    syncQueueRepository: _NoopSyncQueueRepository(),
  );
}

SqliteSaleRepository createSaleRepositoryWithRecordingSync(
  Database database, {
  required RecordingSyncMetadataRepository syncMetadataRepository,
  required RecordingSyncQueueRepository syncQueueRepository,
}) {
  return SqliteSaleRepository.forDatabase(
    databaseLoader: () async => database,
    operationalContext: AppOperationalContext(
      environment: const AppEnvironment.localDefault(),
      session: AppSession.localDefault(),
    ),
    syncMetadataRepository: syncMetadataRepository,
    syncQueueRepository: syncQueueRepository,
  );
}

SqliteSaleReturnRepository createSaleReturnRepository(
  Database database, {
  SqliteSaleRepository? saleRepository,
}) {
  final resolvedSaleRepository =
      saleRepository ?? createSaleRepository(database);
  return SqliteSaleReturnRepository.forDatabase(
    databaseLoader: () async => database,
    operationalContext: AppOperationalContext(
      environment: const AppEnvironment.localDefault(),
      session: AppSession.localDefault(),
    ),
    saleRepository: resolvedSaleRepository,
  );
}

Future<void> insertClient(
  Database db, {
  required int customerId,
  int creditBalance = 0,
}) {
  return db.insert(TableNames.clientes, {
    'id': customerId,
    'nome': 'Cliente $customerId',
    'credit_balance': creditBalance,
    'saldo_devedor_centavos': 0,
    'deletado_em': null,
    'atualizado_em': _fixedNowIso,
  });
}

Future<void> insertSimpleProduct(
  Database db, {
  required int productId,
  required String name,
  required int stockMil,
  String? barcode,
  int costCents = 4000,
  int salePriceCents = 9000,
}) {
  return db.insert(TableNames.produtos, {
    'id': productId,
    'uuid': 'product-$productId',
    'nome': name,
    'codigo_barras': barcode,
    'estoque_mil': stockMil,
    'deletado_em': null,
    'custo_centavos': costCents,
    'unidade_medida': 'un',
    'tipo_produto': 'simples',
    'preco_venda_centavos': salePriceCents,
    'ativo': 1,
    'atualizado_em': _fixedNowIso,
  });
}

Future<void> insertVariantProduct(
  Database db, {
  required int productId,
  required String name,
  required int parentStockMil,
  required List<VariantSeed> variants,
  int costCents = 5000,
  int salePriceCents = 12000,
}) async {
  await db.insert(TableNames.produtos, {
    'id': productId,
    'uuid': 'product-$productId',
    'nome': name,
    'codigo_barras': 'BAR-$productId',
    'estoque_mil': parentStockMil,
    'deletado_em': null,
    'custo_centavos': costCents,
    'unidade_medida': 'un',
    'tipo_produto': 'grade',
    'preco_venda_centavos': salePriceCents,
    'ativo': 1,
    'atualizado_em': _fixedNowIso,
  });

  for (final variant in variants) {
    await db.insert(TableNames.produtoVariantes, {
      'id': variant.id,
      'produto_id': productId,
      'sku': variant.sku,
      'cor': variant.color,
      'tamanho': variant.size,
      'estoque_mil': variant.stockMil,
      'ativo': 1,
      'atualizado_em': _fixedNowIso,
      'ordem': variant.order,
      'preco_adicional_centavos': variant.additionalPriceCents,
    });
  }
}

CartItem buildSimpleCartItem({
  required int productId,
  required String productName,
  required int quantityMil,
  required int availableStockMil,
  int unitPriceCents = 9000,
  String? barcode,
}) {
  return CartItem(
    id: 'cart-$productId-$quantityMil',
    productId: productId,
    productName: productName,
    baseProductId: null,
    baseProductName: null,
    variantSku: barcode,
    quantityMil: quantityMil,
    availableStockMil: availableStockMil,
    unitPriceCents: unitPriceCents,
    unitMeasure: 'un',
    productType: 'simples',
  );
}

CartItem buildVariantCartItem({
  required int productId,
  required int variantId,
  required String productName,
  required String sku,
  required String color,
  required String size,
  required int quantityMil,
  required int availableStockMil,
  int unitPriceCents = 12000,
}) {
  return CartItem(
    id: 'cart-$productId-$variantId-$quantityMil',
    productId: productId,
    productVariantId: variantId,
    productName: productName,
    baseProductId: null,
    baseProductName: null,
    variantSku: sku,
    variantColorLabel: color,
    variantSizeLabel: size,
    quantityMil: quantityMil,
    availableStockMil: availableStockMil,
    unitPriceCents: unitPriceCents,
    unitMeasure: 'un',
    productType: 'grade',
  );
}

Future<int> loadProductStock(Database db, int productId) async {
  final rows = await db.query(
    TableNames.produtos,
    columns: const ['estoque_mil'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  return rows.first['estoque_mil'] as int? ?? 0;
}

Future<int> loadVariantStock(Database db, int variantId) async {
  final rows = await db.query(
    TableNames.produtoVariantes,
    columns: const ['estoque_mil'],
    where: 'id = ?',
    whereArgs: [variantId],
    limit: 1,
  );
  return rows.first['estoque_mil'] as int? ?? 0;
}

Future<List<Map<String, Object?>>> loadInventoryMovementRows(
  Database db, {
  InventoryMovementType? movementType,
}) {
  return db.query(
    TableNames.inventoryMovements,
    where: movementType == null ? null : 'movement_type = ?',
    whereArgs: movementType == null ? null : [movementType.storageValue],
    orderBy: 'id ASC',
  );
}

Future<int> loadLatestSaleItemId(Database db, int saleId) async {
  final rows = await db.query(
    TableNames.itensVenda,
    columns: const ['id'],
    where: 'venda_id = ?',
    whereArgs: [saleId],
    orderBy: 'id DESC',
    limit: 1,
  );
  return rows.first['id'] as int;
}

Future<int> countRows(Database db, String tableName) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $tableName');
  return rows.first['total'] as int? ?? 0;
}

class VariantSeed {
  const VariantSeed({
    required this.id,
    required this.sku,
    required this.color,
    required this.size,
    required this.stockMil,
    this.order = 0,
    this.additionalPriceCents = 0,
  });

  final int id;
  final String sku;
  final String color;
  final String size;
  final int stockMil;
  final int order;
  final int additionalPriceCents;
}

class RecordingSyncMetadataEntry {
  const RecordingSyncMetadataEntry({
    required this.featureKey,
    required this.localId,
    required this.localUuid,
  });

  final String featureKey;
  final int localId;
  final String localUuid;
}

class RecordingSyncMutation {
  const RecordingSyncMutation({
    required this.featureKey,
    required this.entityType,
    required this.localEntityId,
    required this.localUuid,
    required this.remoteId,
    required this.operation,
  });

  final String featureKey;
  final String entityType;
  final int localEntityId;
  final String? localUuid;
  final String? remoteId;
  final SyncQueueOperation operation;
}

class RecordingSyncMetadataRepository extends SqliteSyncMetadataRepository {
  RecordingSyncMetadataRepository() : super(AppDatabase.instance);

  final entries = <RecordingSyncMetadataEntry>[];

  @override
  Future<SyncMetadata?> findByLocalId(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
  }) async {
    return null;
  }

  @override
  Future<void> markPendingUpload(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    entries.add(
      RecordingSyncMetadataEntry(
        featureKey: featureKey,
        localId: localId,
        localUuid: localUuid,
      ),
    );
  }

  @override
  Future<void> markPendingUpdate(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    entries.add(
      RecordingSyncMetadataEntry(
        featureKey: featureKey,
        localId: localId,
        localUuid: localUuid,
      ),
    );
  }
}

class RecordingSyncQueueRepository extends SqliteSyncQueueRepository {
  RecordingSyncQueueRepository() : super(AppDatabase.instance);

  final mutations = <RecordingSyncMutation>[];

  @override
  Future<void> enqueueMutation(
    DatabaseExecutor db, {
    required String featureKey,
    required String entityType,
    required int localEntityId,
    required String? localUuid,
    required String? remoteId,
    required SyncQueueOperation operation,
    required DateTime localUpdatedAt,
  }) async {
    mutations.add(
      RecordingSyncMutation(
        featureKey: featureKey,
        entityType: entityType,
        localEntityId: localEntityId,
        localUuid: localUuid,
        remoteId: remoteId,
        operation: operation,
      ),
    );
  }
}

class _NoopSyncMetadataRepository extends SqliteSyncMetadataRepository {
  _NoopSyncMetadataRepository() : super(AppDatabase.instance);

  @override
  Future<SyncMetadata?> findByLocalId(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
  }) async {
    return null;
  }

  @override
  Future<void> markPendingUpload(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {}

  @override
  Future<void> markPendingUpdate(
    DatabaseExecutor db, {
    required String featureKey,
    required int localId,
    required String localUuid,
    required String? remoteId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {}
}

class _NoopSyncQueueRepository extends SqliteSyncQueueRepository {
  _NoopSyncQueueRepository() : super(AppDatabase.instance);

  @override
  Future<void> enqueueMutation(
    DatabaseExecutor db, {
    required String featureKey,
    required String entityType,
    required int localEntityId,
    required String? localUuid,
    required String? remoteId,
    required SyncQueueOperation operation,
    required DateTime localUpdatedAt,
  }) async {}
}

Future<void> _createSchema(
  Database db, {
  required bool includeInventoryMovements,
}) async {
  await db.execute('''
    CREATE TABLE ${TableNames.produtos} (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      nome TEXT NOT NULL,
      codigo_barras TEXT,
      estoque_mil INTEGER NOT NULL DEFAULT 0,
      deletado_em TEXT,
      custo_centavos INTEGER NOT NULL DEFAULT 0,
      unidade_medida TEXT NOT NULL DEFAULT 'un',
      tipo_produto TEXT NOT NULL DEFAULT 'simples',
      preco_venda_centavos INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.produtoVariantes} (
      id INTEGER PRIMARY KEY,
      produto_id INTEGER NOT NULL,
      sku TEXT,
      cor TEXT,
      tamanho TEXT,
      estoque_mil INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT,
      ordem INTEGER NOT NULL DEFAULT 0,
      preco_adicional_centavos INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.vendas} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      cliente_id INTEGER,
      tipo_venda TEXT,
      forma_pagamento TEXT,
      status TEXT NOT NULL,
      desconto_centavos INTEGER NOT NULL DEFAULT 0,
      acrescimo_centavos INTEGER NOT NULL DEFAULT 0,
      valor_total_centavos INTEGER NOT NULL DEFAULT 0,
      valor_final_centavos INTEGER NOT NULL DEFAULT 0,
      haver_utilizado_centavos INTEGER,
      haver_gerado_centavos INTEGER,
      valor_recebido_imediato_centavos INTEGER,
      numero_cupom TEXT,
      data_venda TEXT,
      usuario_id INTEGER,
      observacao TEXT,
      cancelada_em TEXT,
      venda_origem_id INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensVenda} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT,
      venda_id INTEGER NOT NULL,
      produto_id INTEGER NOT NULL,
      produto_variante_id INTEGER,
      nome_produto_snapshot TEXT,
      sku_variante_snapshot TEXT,
      cor_variante_snapshot TEXT,
      tamanho_variante_snapshot TEXT,
      quantidade_mil INTEGER NOT NULL,
      valor_unitario_centavos INTEGER NOT NULL,
      subtotal_centavos INTEGER NOT NULL,
      custo_unitario_centavos INTEGER,
      custo_total_centavos INTEGER,
      unidade_medida_snapshot TEXT,
      tipo_produto_snapshot TEXT,
      observacao_item_snapshot TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensVendaModificadores} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT,
      item_venda_id INTEGER NOT NULL,
      grupo_modificador_id INTEGER,
      opcao_modificador_id INTEGER,
      nome_grupo_snapshot TEXT,
      nome_opcao_snapshot TEXT,
      tipo_ajuste_snapshot TEXT,
      preco_delta_centavos INTEGER NOT NULL DEFAULT 0,
      quantidade INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT,
      atualizado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.saleReturns} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      sale_id INTEGER NOT NULL,
      client_id INTEGER,
      exchange_mode TEXT NOT NULL,
      reason TEXT,
      refund_amount_cents INTEGER NOT NULL,
      credited_amount_cents INTEGER NOT NULL,
      applied_discount_cents INTEGER NOT NULL,
      replacement_sale_id INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.saleReturnItems} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      sale_return_id INTEGER NOT NULL,
      sale_item_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_variant_id INTEGER,
      product_name_snapshot TEXT NOT NULL,
      variant_sku_snapshot TEXT,
      variant_color_snapshot TEXT,
      variant_size_snapshot TEXT,
      quantity_mil INTEGER NOT NULL,
      unit_price_cents INTEGER NOT NULL,
      subtotal_cents INTEGER NOT NULL,
      reason TEXT,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.clientes} (
      id INTEGER PRIMARY KEY,
      nome TEXT NOT NULL,
      credit_balance INTEGER NOT NULL DEFAULT 0,
      saldo_devedor_centavos INTEGER NOT NULL DEFAULT 0,
      deletado_em TEXT,
      atualizado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.customerCreditTransactions} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      description TEXT,
      sale_id INTEGER,
      fiado_id INTEGER,
      cash_session_id INTEGER,
      origin_payment_id INTEGER,
      reversed_transaction_id INTEGER,
      is_reversed INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.caixaSessoes} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      usuario_id INTEGER,
      aberta_em TEXT NOT NULL,
      fechada_em TEXT,
      troco_inicial_centavos INTEGER NOT NULL DEFAULT 0,
      aguardando_confirmacao_troco_inicial INTEGER NOT NULL DEFAULT 1,
      total_entradas_dinheiro_centavos INTEGER NOT NULL DEFAULT 0,
      total_suprimentos_centavos INTEGER NOT NULL DEFAULT 0,
      total_sangrias_centavos INTEGER NOT NULL DEFAULT 0,
      total_vendas_centavos INTEGER NOT NULL DEFAULT 0,
      total_recebimentos_fiado_centavos INTEGER NOT NULL DEFAULT 0,
      total_recebimentos_fiado_dinheiro_centavos INTEGER NOT NULL DEFAULT 0,
      total_recebimentos_fiado_pix_centavos INTEGER NOT NULL DEFAULT 0,
      total_recebimentos_fiado_cartao_centavos INTEGER NOT NULL DEFAULT 0,
      saldo_esperado_centavos INTEGER NOT NULL DEFAULT 0,
      saldo_contado_centavos INTEGER,
      diferenca_centavos INTEGER,
      saldo_final_centavos INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      observacao TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.caixaMovimentos} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      sessao_id INTEGER NOT NULL,
      tipo_movimento TEXT NOT NULL,
      referencia_tipo TEXT,
      referencia_id INTEGER,
      valor_centavos INTEGER NOT NULL,
      descricao TEXT,
      criado_em TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fiado} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT,
      venda_id INTEGER,
      cliente_id INTEGER,
      valor_original_centavos INTEGER,
      valor_aberto_centavos INTEGER,
      vencimento TEXT,
      status TEXT,
      criado_em TEXT,
      atualizado_em TEXT,
      quitado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fiadoLancamentos} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT,
      fiado_id INTEGER,
      cliente_id INTEGER,
      tipo_lancamento TEXT,
      valor_centavos INTEGER,
      data_lancamento TEXT,
      observacao TEXT,
      caixa_movimento_id INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.supplies} (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      name TEXT,
      unit_type TEXT,
      conversion_factor INTEGER,
      current_stock_mil INTEGER,
      created_at TEXT,
      updated_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.productRecipeItems} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      supply_id INTEGER NOT NULL,
      quantity_used_mil INTEGER NOT NULL DEFAULT 0,
      waste_basis_points INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.supplyInventoryMovements} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL,
      remote_id TEXT,
      supply_id INTEGER NOT NULL,
      movement_type TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_local_uuid TEXT,
      source_remote_id TEXT,
      dedupe_key TEXT,
      quantity_delta_mil INTEGER NOT NULL,
      unit_type TEXT NOT NULL,
      balance_after_mil INTEGER,
      notes TEXT,
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  if (includeInventoryMovements) {
    await db.execute('''
      CREATE TABLE ${TableNames.inventoryMovements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        product_id INTEGER NOT NULL,
        product_variant_id INTEGER,
        movement_type TEXT NOT NULL,
        quantity_delta_mil INTEGER NOT NULL,
        stock_before_mil INTEGER NOT NULL,
        stock_after_mil INTEGER NOT NULL,
        reference_type TEXT NOT NULL,
        reference_id INTEGER,
        reason TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
}

const String _fixedNowIso = '2026-04-16T12:00:00.000Z';
