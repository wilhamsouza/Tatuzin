import 'dart:io';

import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/modules/compras/data/models/purchase_item_model.dart';
import 'package:erp_pdv_app/modules/compras/data/support/purchase_stock_support.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE ${TableNames.produtos} (
              id INTEGER PRIMARY KEY,
              nome TEXT NOT NULL,
              estoque_mil INTEGER,
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
              ativo INTEGER NOT NULL DEFAULT 1,
              atualizado_em TEXT
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
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('compra simples atualiza saldo e grava movimento', () async {
    await database.insert(TableNames.produtos, {
      'id': 1,
      'nome': 'Vestido Midi',
      'estoque_mil': 1500,
      'atualizado_em': _nowIso,
    });

    await PurchaseStockSupport.applyStockEntries(
      database,
      [
        const PurchaseItemModel(
          id: 1,
          uuid: 'purchase-item-simple',
          purchaseId: 12,
          itemType: PurchaseItemType.product,
          productId: 1,
          productVariantId: null,
          supplyId: null,
          itemNameSnapshot: 'Vestido Midi',
          variantSkuSnapshot: null,
          variantColorLabelSnapshot: null,
          variantSizeLabelSnapshot: null,
          unitMeasureSnapshot: 'un',
          quantityMil: 2500,
          unitCostCents: 4200,
          subtotalCents: 10500,
        ),
      ],
      factor: 1,
      referenceId: 12,
      occurredAt: DateTime.parse(_nowIso),
    );

    expect(await _productStock(database, 1), 4000);

    final movement = await _latestMovement(database);
    expect(movement['product_id'], 1);
    expect(movement['product_variant_id'], null);
    expect(movement['movement_type'], 'purchase_in');
    expect(movement['quantity_delta_mil'], 2500);
    expect(movement['stock_before_mil'], 1500);
    expect(movement['stock_after_mil'], 4000);
    expect(movement['reference_type'], 'purchase');
    expect(movement['reference_id'], 12);
  });

  test(
    'compra com variante atualiza variante, recompone pai e grava movimento',
    () async {
      await database.insert(TableNames.produtos, {
        'id': 1,
        'nome': 'Camiseta Basic',
        'estoque_mil': 5000,
        'atualizado_em': _nowIso,
      });
      await database.insert(TableNames.produtoVariantes, {
        'id': 10,
        'produto_id': 1,
        'sku': 'CAM-BASIC-PRETA-P',
        'cor': 'Preta',
        'tamanho': 'P',
        'estoque_mil': 2000,
        'ativo': 1,
        'atualizado_em': _nowIso,
      });
      await database.insert(TableNames.produtoVariantes, {
        'id': 11,
        'produto_id': 1,
        'sku': 'CAM-BASIC-PRETA-M',
        'cor': 'Preta',
        'tamanho': 'M',
        'estoque_mil': 3000,
        'ativo': 1,
        'atualizado_em': _nowIso,
      });

      await PurchaseStockSupport.applyStockEntries(
        database,
        [
          const PurchaseItemModel(
            id: 1,
            uuid: 'purchase-item-1',
            purchaseId: 1,
            itemType: PurchaseItemType.product,
            productId: 1,
            productVariantId: 10,
            supplyId: null,
            itemNameSnapshot: 'Camiseta Basic',
            variantSkuSnapshot: 'CAM-BASIC-PRETA-P',
            variantColorLabelSnapshot: 'Preta',
            variantSizeLabelSnapshot: 'P',
            unitMeasureSnapshot: 'un',
            quantityMil: 4000,
            unitCostCents: 2500,
            subtotalCents: 10000,
          ),
        ],
        factor: 1,
        referenceId: 1,
        occurredAt: DateTime.parse(_nowIso),
      );

      expect(await _variantStock(database, 10), 6000);
      expect(await _variantStock(database, 11), 3000);
      expect(await _productStock(database, 1), 9000);

      final movement = await _latestMovement(database);
      expect(movement['product_id'], 1);
      expect(movement['product_variant_id'], 10);
      expect(movement['movement_type'], 'purchase_in');
      expect(movement['quantity_delta_mil'], 4000);
      expect(movement['stock_before_mil'], 2000);
      expect(movement['stock_after_mil'], 6000);
    },
  );

  test('reversao bloqueia quando o saldo ficaria negativo', () async {
    await database.insert(TableNames.produtos, {
      'id': 1,
      'nome': 'Vestido Midi',
      'estoque_mil': 1000,
      'atualizado_em': _nowIso,
    });
    await database.insert(TableNames.produtoVariantes, {
      'id': 20,
      'produto_id': 1,
      'sku': 'VEST-MIDI-AZUL-P',
      'cor': 'Azul',
      'tamanho': 'P',
      'estoque_mil': 1000,
      'ativo': 1,
      'atualizado_em': _nowIso,
    });

    await expectLater(
      () => PurchaseStockSupport.applyStockEntries(
        database,
        [
          const PurchaseItemModel(
            id: 1,
            uuid: 'purchase-item-2',
            purchaseId: 1,
            itemType: PurchaseItemType.product,
            productId: 1,
            productVariantId: 20,
            supplyId: null,
            itemNameSnapshot: 'Vestido Midi',
            variantSkuSnapshot: 'VEST-MIDI-AZUL-P',
            variantColorLabelSnapshot: 'Azul',
            variantSizeLabelSnapshot: 'P',
            unitMeasureSnapshot: 'un',
            quantityMil: 2000,
            unitCostCents: 3000,
            subtotalCents: 6000,
          ),
        ],
        factor: -1,
        referenceId: 1,
        occurredAt: DateTime.parse(_nowIso),
      ),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Vestido Midi'), contains('P / Azul')),
        ),
      ),
    );

    expect(await _variantStock(database, 20), 1000);
    expect(await _productStock(database, 1), 1000);
    expect(await _movementCount(database), 0);
  });

  test(
    'compra faz rollback do saldo se a gravacao do movimento falhar',
    () async {
      final failurePath =
          '${Directory.systemTemp.path}\\purchase-stock-rollback-${DateTime.now().microsecondsSinceEpoch}.db';
      final failureDatabase = await databaseFactoryFfi.openDatabase(
        failurePath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE ${TableNames.produtos} (
              id INTEGER PRIMARY KEY,
              nome TEXT NOT NULL,
              estoque_mil INTEGER,
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
              ativo INTEGER NOT NULL DEFAULT 1,
              atualizado_em TEXT
            )
          ''');
          },
        ),
      );
      addTearDown(() async {
        await failureDatabase.close();
        await databaseFactoryFfi.deleteDatabase(failurePath);
      });

      await failureDatabase.insert(TableNames.produtos, {
        'id': 1,
        'nome': 'Saia Midi',
        'estoque_mil': 1500,
        'atualizado_em': _nowIso,
      });

      await expectLater(
        () => PurchaseStockSupport.applyStockEntries(
          failureDatabase,
          [
            const PurchaseItemModel(
              id: 99,
              uuid: 'purchase-item-rollback',
              purchaseId: 22,
              itemType: PurchaseItemType.product,
              productId: 1,
              productVariantId: null,
              supplyId: null,
              itemNameSnapshot: 'Saia Midi',
              variantSkuSnapshot: null,
              variantColorLabelSnapshot: null,
              variantSizeLabelSnapshot: null,
              unitMeasureSnapshot: 'un',
              quantityMil: 2500,
              unitCostCents: 3000,
              subtotalCents: 7500,
            ),
          ],
          factor: 1,
          referenceId: 22,
          occurredAt: DateTime.parse(_nowIso),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await _productStock(failureDatabase, 1), 1500);
    },
  );
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

final _nowIso = DateTime.parse('2026-04-16T12:00:00Z').toIso8601String();
