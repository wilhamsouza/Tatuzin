import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/migrations.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/pedidos/data/sqlite_operational_order_repository.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'migration v34 adiciona campos de variante sem alterar pedidos antigos',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => AppMigrations.runCreate(db, 33),
        ),
      );
      addTearDown(database.close);

      await _insertProduct(database);
      final orderId = await _insertLegacyOrder(database);
      await database.insert(TableNames.pedidosOperacionaisItens, {
        'uuid': 'legacy-order-item',
        'pedido_operacional_id': orderId,
        'produto_id': 1,
        'nome_produto_snapshot': 'Camiseta Basic',
        'quantidade_mil': 1000,
        'valor_unitario_centavos': 9900,
        'subtotal_centavos': 9900,
        'observacao': null,
        'criado_em': _fixedNowIso,
        'atualizado_em': _fixedNowIso,
      });

      await AppMigrations.runUpgrade(database, 33, 34);

      final columns = await database.rawQuery(
        'PRAGMA table_info(${TableNames.pedidosOperacionaisItens})',
      );
      final columnNames = columns.map((row) => row['name']).toSet();
      expect(columnNames, contains('produto_variante_id'));
      expect(columnNames, contains('sku_variante_snapshot'));
      expect(columnNames, contains('cor_variante_snapshot'));
      expect(columnNames, contains('tamanho_variante_snapshot'));

      final itemRows = await database.query(
        TableNames.pedidosOperacionaisItens,
        where: 'uuid = ?',
        whereArgs: ['legacy-order-item'],
      );
      expect(itemRows.single['produto_variante_id'], isNull);
      expect(itemRows.single['sku_variante_snapshot'], isNull);
      expect(itemRows.single['cor_variante_snapshot'], isNull);
      expect(itemRows.single['tamanho_variante_snapshot'], isNull);

      final indexRows = await database.rawQuery(
        'PRAGMA index_list(${TableNames.pedidosOperacionaisItens})',
      );
      expect(
        indexRows.map((row) => row['name']),
        contains('idx_pedidos_operacionais_itens_produto_variante'),
      );
    },
  );

  test('repository preserva variante em item de pedido', () async {
    final fixture = await _openRepositoryFixture();
    addTearDown(fixture.dispose);

    await _insertProduct(fixture.database);
    await _insertProductVariant(fixture.database);

    final orderId = await fixture.repository.create(
      const OperationalOrderInput(status: OperationalOrderStatus.open),
    );
    await fixture.repository.addItem(
      orderId,
      const OperationalOrderItemInput(
        productId: 1,
        productVariantId: 10,
        variantSkuSnapshot: 'CAM-BASIC-PRETA-P',
        variantColorSnapshot: 'Preta',
        variantSizeSnapshot: 'P',
        productNameSnapshot: 'Camiseta Basic - P / Preta',
        quantityMil: 2000,
        unitPriceCents: 9900,
        subtotalCents: 19800,
      ),
    );

    final items = await fixture.repository.listItems(orderId);

    expect(items, hasLength(1));
    expect(items.single.productVariantId, 10);
    expect(items.single.variantSkuSnapshot, 'CAM-BASIC-PRETA-P');
    expect(items.single.variantColorSnapshot, 'Preta');
    expect(items.single.variantSizeSnapshot, 'P');
  });

  test('repository continua salvando item antigo sem variante', () async {
    final fixture = await _openRepositoryFixture();
    addTearDown(fixture.dispose);

    await _insertProduct(fixture.database);

    final orderId = await fixture.repository.create(
      const OperationalOrderInput(status: OperationalOrderStatus.open),
    );
    await fixture.repository.addItem(
      orderId,
      const OperationalOrderItemInput(
        productId: 1,
        productNameSnapshot: 'Camiseta Basic',
        quantityMil: 1000,
        unitPriceCents: 9900,
        subtotalCents: 9900,
      ),
    );

    final items = await fixture.repository.listItems(orderId);

    expect(items, hasLength(1));
    expect(items.single.productVariantId, isNull);
    expect(items.single.variantSkuSnapshot, isNull);
    expect(items.single.variantColorSnapshot, isNull);
    expect(items.single.variantSizeSnapshot, isNull);
  });
}

const _fixedNowIso = '2026-01-01T00:00:00.000';

Future<_RepositoryFixture> _openRepositoryFixture() async {
  final isolationKey =
      'remote:order-variant-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  final database = await appDatabase.database;
  return _RepositoryFixture(
    isolationKey: isolationKey,
    appDatabase: appDatabase,
    database: database,
    repository: SqliteOperationalOrderRepository(appDatabase),
  );
}

Future<void> _insertProduct(DatabaseExecutor db) {
  return db.insert(TableNames.produtos, {
    'id': 1,
    'uuid': 'product-1',
    'nome': 'Camiseta Basic',
    'descricao': null,
    'categoria_id': null,
    'foto_path': null,
    'codigo_barras': '789000000001',
    'tipo_produto': 'unidade',
    'unidade_medida': 'un',
    'custo_centavos': 4000,
    'preco_venda_centavos': 9900,
    'estoque_mil': 3000,
    'ativo': 1,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
    'deletado_em': null,
  });
}

Future<void> _insertProductVariant(DatabaseExecutor db) {
  return db.insert(TableNames.produtoVariantes, {
    'id': 10,
    'uuid': 'variant-10',
    'produto_id': 1,
    'sku': 'CAM-BASIC-PRETA-P',
    'cor': 'Preta',
    'tamanho': 'P',
    'preco_adicional_centavos': 0,
    'estoque_mil': 3000,
    'ordem': 0,
    'ativo': 1,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
  });
}

Future<int> _insertLegacyOrder(DatabaseExecutor db) {
  return db.insert(TableNames.pedidosOperacionais, {
    'uuid': 'legacy-order',
    'status': 'open',
    'observacao': null,
    'criado_em': _fixedNowIso,
    'atualizado_em': _fixedNowIso,
    'fechado_em': null,
  });
}

class _RepositoryFixture {
  const _RepositoryFixture({
    required this.isolationKey,
    required this.appDatabase,
    required this.database,
    required this.repository,
  });

  final String isolationKey;
  final AppDatabase appDatabase;
  final Database database;
  final SqliteOperationalOrderRepository repository;

  Future<void> dispose() async {
    await appDatabase.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}
