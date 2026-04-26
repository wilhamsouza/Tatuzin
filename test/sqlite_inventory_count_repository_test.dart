import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_inventory_count_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_count_item_input.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_count_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late SqliteInventoryCountRepository repository;

  tearDown(() async {
    await database.close();
  });

  test('cria sessao de inventario', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );

    final session = await repository.createSession(name: 'Inventario abril');

    expect(session.name, 'Inventario abril');
    expect(session.status, InventoryCountSessionStatus.open);
    expect(session.totalItems, 0);
    expect(session.itemsWithDifference, 0);
  });

  test('adiciona item simples e captura estoque do sistema', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Bone Trucker', stockMil: 3000);

    final session = await repository.createSession(name: 'Contagem loja');
    final item = await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 3500,
        notes: 'Contagem da arara principal',
      ),
    );

    expect(item.productId, 1);
    expect(item.productVariantId, isNull);
    expect(item.systemStockMil, 3000);
    expect(item.countedStockMil, 3500);
    expect(item.differenceMil, 500);
    expect(item.notes, 'Contagem da arara principal');

    final detail = await repository.getSessionDetail(session.id);
    expect(detail, isNotNull);
    expect(detail!.session.status, InventoryCountSessionStatus.counting);
    expect(detail.items, hasLength(1));
    expect(detail.items.single.currentStockMil, 3000);
    expect(detail.items.single.isStale, isFalse);
  });

  test('adiciona item variante', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Camisa Linho', stockMil: 5000);
    await _insertVariant(
      database,
      id: 10,
      productId: 1,
      sku: 'CL-PT-P',
      color: 'Preta',
      size: 'P',
      stockMil: 2000,
    );
    await _insertVariant(
      database,
      id: 11,
      productId: 1,
      sku: 'CL-PT-M',
      color: 'Preta',
      size: 'M',
      stockMil: 3000,
    );

    final session = await repository.createSession(name: 'Contagem grade');
    final item = await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: 10,
        countedStockMil: 1500,
      ),
    );

    expect(item.productVariantId, 10);
    expect(item.systemStockMil, 2000);
    expect(item.countedStockMil, 1500);
    expect(item.differenceMil, -500);

    final detail = await repository.getSessionDetail(session.id);
    expect(detail!.items.single.productVariantId, 10);
    expect(detail.items.single.currentStockMil, 2000);
  });

  test('calcula divergencia corretamente', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Vestido Midi', stockMil: 4000);

    final session = await repository.createSession(name: 'Conferencia');
    await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 2500,
      ),
    );

    final detail = await repository.getSessionDetail(session.id);
    expect(detail!.items.single.differenceMil, -1500);
    expect(detail.summary.itemsWithDifference, 1);
    expect(detail.summary.staleItems, 0);
    expect(detail.summary.readyItems, 1);
    expect(detail.summary.shortageMil, 1500);
    expect(detail.summary.surplusMil, 0);
  });

  test('sessao aplica normalmente quando saldo nao mudou', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Bone Trucker', stockMil: 1000);

    final session = await repository.createSession(name: 'Sobra de loja');
    await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 1500,
      ),
    );

    await repository.applySession(session.id);

    expect(await _productStock(database, 1), 1500);
    final movement = await _latestMovement(database);
    expect(movement['movement_type'], 'count_adjustment_in');
    expect(movement['quantity_delta_mil'], 500);
    expect(movement['stock_before_mil'], 1000);
    expect(movement['stock_after_mil'], 1500);
    expect(movement['reference_type'], 'inventory_count_session');
    expect(movement['reference_id'], session.id);

    final detail = await repository.getSessionDetail(session.id);
    expect(detail!.session.status, InventoryCountSessionStatus.applied);
    expect(detail.session.appliedAt, isNotNull);
    expect(detail.items.single.appliedFromSystemStockMil, 1000);
    expect(detail.items.single.staleAtApply, isFalse);
  });

  test('detecta item desatualizado quando saldo mudou', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Vestido Midi', stockMil: 2000);

    final session = await repository.createSession(name: 'Conferencia setor A');
    final item = await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 2500,
      ),
    );
    await _updateProductStock(database, productId: 1, stockMil: 2300);

    final detail = await repository.getSessionDetail(session.id);
    final staleItem = detail!.items.single;
    expect(staleItem.id, item.id);
    expect(staleItem.systemStockMil, 2000);
    expect(staleItem.currentStockMil, 2300);
    expect(staleItem.differenceMil, 500);
    expect(staleItem.isStale, isTrue);
    expect(staleItem.needsReview, isTrue);
    expect(detail.summary.staleItems, 1);
    expect(detail.summary.readyItems, 0);
  });

  test('aplicacao bloqueia se existir item desatualizado', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Vestido Midi', stockMil: 2000);

    final session = await repository.createSession(name: 'Falta setor A');
    await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 500,
      ),
    );
    await _updateProductStock(database, productId: 1, stockMil: 1700);

    await expectLater(
      () => repository.applySession(session.id),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          contains('desatualizado'),
        ),
      ),
    );

    expect(await _productStock(database, 1), 1700);
    expect(await _movementCount(database), 0);
    final detail = await repository.getSessionDetail(session.id);
    expect(detail!.session.status, InventoryCountSessionStatus.counting);
  });

  test(
    'recalcular item desatualizado atualiza diferenca corretamente',
    () async {
      database = await _openDatabase();
      repository = SqliteInventoryCountRepository.forDatabase(
        databaseLoader: () async => database,
      );
      await _insertProduct(
        database,
        id: 1,
        name: 'Vestido Midi',
        stockMil: 2000,
      );

      final session = await repository.createSession(name: 'Revisao estoque');
      final item = await repository.upsertItem(
        const InventoryCountItemInput(
          sessionId: 1,
          productId: 1,
          productVariantId: null,
          countedStockMil: 500,
        ),
      );
      await _updateProductStock(database, productId: 1, stockMil: 1700);

      final recalculated = await repository.recalculateItemFromCurrentStock(
        item.id,
      );

      expect(recalculated.countSessionId, session.id);
      expect(recalculated.systemStockMil, 1700);
      expect(recalculated.currentStockMil, 1700);
      expect(recalculated.countedStockMil, 500);
      expect(recalculated.differenceMil, -1200);
      expect(recalculated.isStale, isFalse);
      expect(recalculated.needsReview, isFalse);

      final detail = await repository.getSessionDetail(session.id);
      expect(detail!.summary.staleItems, 0);
      expect(detail.summary.readyItems, 1);
    },
  );

  test('sessao volta a aplicar normalmente apos revisao', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Camisa Linho', stockMil: 5000);
    await _insertVariant(
      database,
      id: 10,
      productId: 1,
      sku: 'CL-PT-P',
      color: 'Preta',
      size: 'P',
      stockMil: 3000,
    );
    await _insertVariant(
      database,
      id: 11,
      productId: 1,
      sku: 'CL-PT-M',
      color: 'Preta',
      size: 'M',
      stockMil: 2000,
    );

    final session = await repository.createSession(name: 'Grade provador');
    await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: 10,
        countedStockMil: 1000,
      ),
    );
    await _updateVariantStock(database, variantId: 10, stockMil: 2500);
    await _updateProductStock(database, productId: 1, stockMil: 4500);

    final detailBefore = await repository.getSessionDetail(session.id);
    expect(detailBefore!.items.single.isStale, isTrue);

    await repository.recalculateItemFromCurrentStock(
      detailBefore.items.single.id,
    );
    await repository.applySession(session.id);

    expect(await _variantStock(database, 10), 1000);
    expect(await _variantStock(database, 11), 2000);
    expect(await _productStock(database, 1), 3000);
    final movement = await _latestMovement(database);
    expect(movement['movement_type'], 'count_adjustment_out');
    expect(movement['quantity_delta_mil'], -1500);
    expect(movement['stock_before_mil'], 2500);
    expect(movement['stock_after_mil'], 1000);
  });

  test('permite manter a divergencia anterior conscientemente', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Bone Trucker', stockMil: 1000);

    final session = await repository.createSession(name: 'Conferencia visual');
    final item = await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 1500,
      ),
    );
    await _updateProductStock(database, productId: 1, stockMil: 1200);

    final kept = await repository.keepRecordedDifference(item.id);
    expect(kept.isStale, isTrue);
    expect(kept.staleOverride, isTrue);
    expect(kept.needsReview, isFalse);
    expect(kept.readyToApply, isTrue);

    await repository.applySession(session.id);

    expect(await _productStock(database, 1), 1700);
    final detail = await repository.getSessionDetail(session.id);
    expect(detail!.items.single.appliedFromSystemStockMil, 1200);
    expect(detail.items.single.staleAtApply, isTrue);
  });

  test('impede reaplicacao da sessao', () async {
    database = await _openDatabase();
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Bone Trucker', stockMil: 1000);

    final session = await repository.createSession(name: 'Sessao unica');
    await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 1500,
      ),
    );

    await repository.applySession(session.id);

    await expectLater(
      () => repository.applySession(session.id),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          contains('ja foi aplicada'),
        ),
      ),
    );
  });

  test('rollback transacional continua funcionando', () async {
    database = await _openDatabase(includeInventoryMovements: false);
    repository = SqliteInventoryCountRepository.forDatabase(
      databaseLoader: () async => database,
    );
    await _insertProduct(database, id: 1, name: 'Vestido Midi', stockMil: 2000);

    final session = await repository.createSession(name: 'Rollback teste');
    await repository.upsertItem(
      const InventoryCountItemInput(
        sessionId: 1,
        productId: 1,
        productVariantId: null,
        countedStockMil: 500,
      ),
    );

    await expectLater(
      () => repository.applySession(session.id),
      throwsA(isA<DatabaseException>()),
    );

    expect(await _productStock(database, 1), 2000);
    final detail = await repository.getSessionDetail(session.id);
    expect(detail!.session.status, InventoryCountSessionStatus.counting);
    expect(detail.items.single.appliedFromSystemStockMil, isNull);
    expect(detail.items.single.staleAtApply, isFalse);
    expect(await _movementCount(database), 0);
  });
}

Future<Database> _openDatabase({bool includeInventoryMovements = true}) {
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

Future<void> _createSchema(
  Database db, {
  required bool includeInventoryMovements,
}) async {
  await db.execute('''
    CREATE TABLE ${TableNames.produtos} (
      id INTEGER PRIMARY KEY,
      nome TEXT NOT NULL,
      codigo_barras TEXT,
      unidade_medida TEXT NOT NULL DEFAULT 'un',
      estoque_mil INTEGER NOT NULL DEFAULT 0,
      custo_centavos INTEGER NOT NULL DEFAULT 0,
      preco_venda_centavos INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      deletado_em TEXT,
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
      preco_adicional_centavos INTEGER NOT NULL DEFAULT 0,
      ordem INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE ${TableNames.inventoryCountSessions} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      applied_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE ${TableNames.inventoryCountItems} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      count_session_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_variant_id INTEGER,
      system_stock_mil INTEGER NOT NULL,
      counted_stock_mil INTEGER NOT NULL,
      difference_mil INTEGER NOT NULL,
      stale_override INTEGER NOT NULL DEFAULT 0,
      applied_from_system_stock_mil INTEGER,
      stale_at_apply INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
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

Future<void> _insertProduct(
  Database db, {
  required int id,
  required String name,
  required int stockMil,
}) {
  return db.insert(TableNames.produtos, {
    'id': id,
    'nome': name,
    'codigo_barras': null,
    'unidade_medida': 'un',
    'estoque_mil': stockMil,
    'custo_centavos': 2500,
    'preco_venda_centavos': 5000,
    'ativo': 1,
    'deletado_em': null,
    'atualizado_em': _nowIso,
  });
}

Future<void> _insertVariant(
  Database db, {
  required int id,
  required int productId,
  required String sku,
  required String color,
  required String size,
  required int stockMil,
}) {
  return db.insert(TableNames.produtoVariantes, {
    'id': id,
    'produto_id': productId,
    'sku': sku,
    'cor': color,
    'tamanho': size,
    'estoque_mil': stockMil,
    'preco_adicional_centavos': 0,
    'ordem': 0,
    'ativo': 1,
    'atualizado_em': _nowIso,
  });
}

Future<int> _productStock(Database db, int productId) async {
  final rows = await db.query(
    TableNames.produtos,
    columns: const ['estoque_mil'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  return rows.first['estoque_mil'] as int? ?? 0;
}

Future<int> _variantStock(Database db, int variantId) async {
  final rows = await db.query(
    TableNames.produtoVariantes,
    columns: const ['estoque_mil'],
    where: 'id = ?',
    whereArgs: [variantId],
    limit: 1,
  );
  return rows.first['estoque_mil'] as int? ?? 0;
}

Future<void> _updateProductStock(
  Database db, {
  required int productId,
  required int stockMil,
}) {
  return db.update(
    TableNames.produtos,
    {'estoque_mil': stockMil, 'atualizado_em': _nowIso},
    where: 'id = ?',
    whereArgs: [productId],
  );
}

Future<void> _updateVariantStock(
  Database db, {
  required int variantId,
  required int stockMil,
}) {
  return db.update(
    TableNames.produtoVariantes,
    {'estoque_mil': stockMil, 'atualizado_em': _nowIso},
    where: 'id = ?',
    whereArgs: [variantId],
  );
}

Future<Map<String, Object?>> _latestMovement(Database db) async {
  final rows = await db.query(
    TableNames.inventoryMovements,
    orderBy: 'id DESC',
    limit: 1,
  );
  return rows.first;
}

Future<int> _movementCount(Database db) async {
  final rows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS total
    FROM sqlite_master
    WHERE type = 'table' AND name = ?
    ''',
    [TableNames.inventoryMovements],
  );
  final tableExists = rows.first['total'] as int? ?? 0;
  if (tableExists == 0) {
    return 0;
  }

  final countRows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM ${TableNames.inventoryMovements}',
  );
  return Sqflite.firstIntValue(countRows) ?? 0;
}

final _nowIso = DateTime.parse('2026-04-17T12:00:00Z').toIso8601String();
