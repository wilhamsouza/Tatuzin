import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/compras/data/models/purchase_item_model.dart';
import 'package:erp_pdv_app/modules/compras/data/support/purchase_stock_support.dart';
import 'package:erp_pdv_app/modules/compras/domain/entities/purchase_item.dart';

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
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'compra por variante atualiza apenas a variante comprada e recompõe o pai',
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

      await PurchaseStockSupport.applyStockEntries(database, [
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
      ], factor: 1);

      final variantP = await _variantStock(database, 10);
      final variantM = await _variantStock(database, 11);
      final parentStock = await _productStock(database, 1);

      expect(variantP, 6000);
      expect(variantM, 3000);
      expect(parentStock, 9000);
    },
  );

  test('reversao valida o estoque da variante correta', () async {
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
      () => PurchaseStockSupport.validateStockReversal(database, [
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
      ]),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Vestido Midi'),
        ),
      ),
    );
  });
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

final _nowIso = DateTime.parse('2026-04-16T12:00:00Z').toIso8601String();
