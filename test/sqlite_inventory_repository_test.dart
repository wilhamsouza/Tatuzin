import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_inventory_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_adjustment_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late SqliteInventoryRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await _createInventorySchema(db);
        },
      ),
    );
    repository = SqliteInventoryRepository.forDatabase(
      databaseLoader: () async => database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'ajuste manual de saida bloqueia estoque negativo quando nao ha configuracao',
    () async {
      await _insertProduct(
        database,
        id: 1,
        name: 'Blazer Alfaiataria',
        stockMil: 1000,
      );

      await expectLater(
        () => repository.adjustStock(
          const InventoryAdjustmentInput(
            productId: 1,
            productVariantId: null,
            direction: InventoryAdjustmentDirection.outbound,
            quantityMil: 1500,
            reason: InventoryAdjustmentReason.loss,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );

      expect(await _productStock(database, 1), 1000);
      expect(await _movementCount(database), 0);
    },
  );

  test(
    'ajuste manual de saida em variante recompone o pai e respeita allow_negative_stock',
    () async {
      await _insertProduct(
        database,
        id: 1,
        name: 'Camisa Linho',
        stockMil: 5000,
      );
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
      await database.insert(TableNames.inventorySettings, {
        'id': 1,
        'product_id': 1,
        'product_variant_id': 10,
        'minimum_stock_mil': 0,
        'reorder_point_mil': null,
        'allow_negative_stock': 1,
        'updated_at': _nowIso,
      });

      await repository.adjustStock(
        const InventoryAdjustmentInput(
          productId: 1,
          productVariantId: 10,
          direction: InventoryAdjustmentDirection.outbound,
          quantityMil: 4000,
          reason: InventoryAdjustmentReason.damage,
          notes: 'Ajuste de conferencia',
        ),
      );

      expect(await _variantStock(database, 10), -1000);
      expect(await _variantStock(database, 11), 2000);
      expect(await _productStock(database, 1), 1000);

      final movement = await _latestMovement(database);
      expect(movement['product_id'], 1);
      expect(movement['product_variant_id'], 10);
      expect(movement['movement_type'], 'adjustment_out');
      expect(movement['quantity_delta_mil'], -4000);
      expect(movement['stock_before_mil'], 3000);
      expect(movement['stock_after_mil'], -1000);
      expect(movement['reason'], 'avaria');
      expect(movement['notes'], 'Ajuste de conferencia');
    },
  );

  test(
    'listMovements permite buscar apenas movimentos diretos ou incluir variantes do produto pai',
    () async {
      await _insertProduct(
        database,
        id: 1,
        name: 'Vestido Midi',
        stockMil: 1500,
      );
      await _insertProduct(
        database,
        id: 2,
        name: 'Camisa Linho',
        stockMil: 5000,
      );
      await _insertVariant(
        database,
        id: 20,
        productId: 2,
        sku: 'CL-PT-P',
        color: 'Preta',
        size: 'P',
        stockMil: 3000,
      );
      await _insertVariant(
        database,
        id: 21,
        productId: 2,
        sku: 'CL-PT-M',
        color: 'Preta',
        size: 'M',
        stockMil: 2000,
      );

      await _insertMovement(
        database,
        uuid: 'movement-simple-1',
        productId: 1,
        productVariantId: null,
        movementType: 'purchase_in',
        createdAt: '2026-04-16T09:00:00Z',
      );
      await _insertMovement(
        database,
        uuid: 'movement-parent-1',
        productId: 2,
        productVariantId: null,
        movementType: 'adjustment_in',
        createdAt: '2026-04-16T10:00:00Z',
      );
      await _insertMovement(
        database,
        uuid: 'movement-variant-20',
        productId: 2,
        productVariantId: 20,
        movementType: 'purchase_in',
        createdAt: '2026-04-16T11:00:00Z',
      );
      await _insertMovement(
        database,
        uuid: 'movement-variant-21',
        productId: 2,
        productVariantId: 21,
        movementType: 'adjustment_out',
        createdAt: '2026-04-16T12:00:00Z',
      );

      final simpleMovements = await repository.listMovements(productId: 1);
      final parentDirectMovements = await repository.listMovements(
        productId: 2,
      );
      final parentMovementsWithVariants = await repository.listMovements(
        productId: 2,
        includeVariantsForProduct: true,
      );

      expect(simpleMovements.map((movement) => movement.uuid), [
        'movement-simple-1',
      ]);
      expect(parentDirectMovements.map((movement) => movement.uuid), [
        'movement-parent-1',
      ]);
      expect(parentMovementsWithVariants.map((movement) => movement.uuid), [
        'movement-variant-21',
        'movement-variant-20',
        'movement-parent-1',
      ]);
    },
  );
}

Future<void> _createInventorySchema(Database db) async {
  await db.execute('''
    CREATE TABLE ${TableNames.produtos} (
      id INTEGER PRIMARY KEY,
      nome TEXT NOT NULL,
      codigo_barras TEXT,
      unidade_medida TEXT NOT NULL DEFAULT 'un',
      estoque_mil INTEGER,
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
      estoque_mil INTEGER,
      preco_adicional_centavos INTEGER NOT NULL DEFAULT 0,
      ordem INTEGER NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE ${TableNames.inventorySettings} (
      id INTEGER PRIMARY KEY,
      product_id INTEGER NOT NULL,
      product_variant_id INTEGER,
      minimum_stock_mil INTEGER NOT NULL DEFAULT 0,
      reorder_point_mil INTEGER,
      allow_negative_stock INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
  ''');
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

Future<int?> _productStock(Database db, int productId) async {
  final rows = await db.query(
    TableNames.produtos,
    columns: const ['estoque_mil'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  return rows.first['estoque_mil'] as int?;
}

Future<int?> _variantStock(Database db, int variantId) async {
  final rows = await db.query(
    TableNames.produtoVariantes,
    columns: const ['estoque_mil'],
    where: 'id = ?',
    whereArgs: [variantId],
    limit: 1,
  );
  return rows.first['estoque_mil'] as int?;
}

Future<int> _movementCount(Database db) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS total FROM ${TableNames.inventoryMovements}',
  );
  return Sqflite.firstIntValue(rows) ?? 0;
}

Future<Map<String, Object?>> _latestMovement(Database db) async {
  final rows = await db.query(
    TableNames.inventoryMovements,
    orderBy: 'id DESC',
    limit: 1,
  );
  return rows.first;
}

Future<void> _insertMovement(
  Database db, {
  required String uuid,
  required int productId,
  required int? productVariantId,
  required String movementType,
  required String createdAt,
}) {
  return db.insert(TableNames.inventoryMovements, {
    'uuid': uuid,
    'product_id': productId,
    'product_variant_id': productVariantId,
    'movement_type': movementType,
    'quantity_delta_mil': 1000,
    'stock_before_mil': 0,
    'stock_after_mil': 1000,
    'reference_type': 'test',
    'reference_id': null,
    'reason': null,
    'notes': null,
    'created_at': createdAt,
    'updated_at': createdAt,
  });
}

final _nowIso = DateTime.parse('2026-04-16T12:00:00Z').toIso8601String();
