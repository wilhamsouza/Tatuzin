import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/modules/relatorios/data/sqlite_report_repository.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_period.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late SqliteReportRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await _createSchema(db);
        },
      ),
    );
    repository = SqliteReportRepository.forDatabase(() async => database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'relatorio por variante separa grade e consolida venda, compra e estoque atual',
    () async {
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      await database.insert(TableNames.produtos, {
        'id': 1,
        'nome': 'Camiseta Basic',
        'model_name': 'Camiseta Basic',
        'unidade_medida': 'un',
        'deletado_em': null,
      });

      await database.insert(TableNames.produtoVariantes, {
        'id': 10,
        'produto_id': 1,
        'sku': 'CAM-BASIC-PRETA-P',
        'cor': 'Preta',
        'tamanho': 'P',
        'estoque_mil': 4000,
        'ordem': 1,
      });
      await database.insert(TableNames.produtoVariantes, {
        'id': 11,
        'produto_id': 1,
        'sku': 'CAM-BASIC-PRETA-M',
        'cor': 'Preta',
        'tamanho': 'M',
        'estoque_mil': 2000,
        'ordem': 2,
      });

      await database.insert(TableNames.vendas, {
        'id': 1,
        'status': 'ativa',
        'tipo_venda': 'vista',
        'forma_pagamento': 'pix',
        'valor_final_centavos': 15000,
        'data_venda': nowIso,
        'cancelada_em': null,
      });

      await database.insert(TableNames.itensVenda, {
        'id': 1,
        'venda_id': 1,
        'produto_id': 1,
        'produto_variante_id': 10,
        'nome_produto_snapshot': 'Camiseta Basic',
        'sku_variante_snapshot': 'CAM-BASIC-PRETA-P',
        'cor_variante_snapshot': 'Preta',
        'tamanho_variante_snapshot': 'P',
        'unidade_medida_snapshot': 'un',
        'quantidade_mil': 2000,
        'valor_unitario_centavos': 5000,
        'subtotal_centavos': 10000,
        'custo_unitario_centavos': 2500,
        'custo_total_centavos': 5000,
      });
      await database.insert(TableNames.itensVenda, {
        'id': 2,
        'venda_id': 1,
        'produto_id': 1,
        'produto_variante_id': 11,
        'nome_produto_snapshot': 'Camiseta Basic',
        'sku_variante_snapshot': 'CAM-BASIC-PRETA-M',
        'cor_variante_snapshot': 'Preta',
        'tamanho_variante_snapshot': 'M',
        'unidade_medida_snapshot': 'un',
        'quantidade_mil': 1000,
        'valor_unitario_centavos': 5000,
        'subtotal_centavos': 5000,
        'custo_unitario_centavos': 2500,
        'custo_total_centavos': 2500,
      });

      await database.insert(TableNames.compras, {
        'id': 1,
        'status': 'recebida',
        'valor_final_centavos': 7500,
        'valor_pendente_centavos': 0,
        'data_compra': nowIso,
      });

      await database.insert(TableNames.itensCompra, {
        'id': 1,
        'compra_id': 1,
        'item_type': 'product',
        'produto_id': 1,
        'produto_variante_id': 10,
        'nome_item_snapshot': 'Camiseta Basic',
        'sku_variante_snapshot': 'CAM-BASIC-PRETA-P',
        'cor_variante_snapshot': 'Preta',
        'tamanho_variante_snapshot': 'P',
        'quantidade_mil': 3000,
      });

      final summary = await repository.fetchSummary(period: ReportPeriod.daily);

      expect(summary.variantSummaries, hasLength(2));

      final variantP = summary.variantSummaries.first;
      final variantM = summary.variantSummaries.last;

      expect(variantP.variantId, 10);
      expect(variantP.modelName, 'Camiseta Basic');
      expect(variantP.variantSku, 'CAM-BASIC-PRETA-P');
      expect(variantP.variantSummary, 'Preta / P');
      expect(variantP.soldQuantityMil, 2000);
      expect(variantP.purchasedQuantityMil, 3000);
      expect(variantP.grossRevenueCents, 10000);
      expect(variantP.currentStockMil, 4000);

      expect(variantM.variantId, 11);
      expect(variantM.variantSummary, 'Preta / M');
      expect(variantM.soldQuantityMil, 1000);
      expect(variantM.purchasedQuantityMil, 0);
      expect(variantM.grossRevenueCents, 5000);
      expect(variantM.currentStockMil, 2000);
    },
  );
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE ${TableNames.vendas} (
      id INTEGER PRIMARY KEY,
      status TEXT NOT NULL,
      tipo_venda TEXT NOT NULL,
      forma_pagamento TEXT,
      valor_final_centavos INTEGER NOT NULL,
      data_venda TEXT NOT NULL,
      cancelada_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensVenda} (
      id INTEGER PRIMARY KEY,
      venda_id INTEGER NOT NULL,
      produto_id INTEGER,
      produto_variante_id INTEGER,
      nome_produto_snapshot TEXT,
      sku_variante_snapshot TEXT,
      cor_variante_snapshot TEXT,
      tamanho_variante_snapshot TEXT,
      unidade_medida_snapshot TEXT,
      quantidade_mil INTEGER NOT NULL,
      valor_unitario_centavos INTEGER NOT NULL,
      subtotal_centavos INTEGER,
      custo_unitario_centavos INTEGER,
      custo_total_centavos INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.produtos} (
      id INTEGER PRIMARY KEY,
      nome TEXT,
      model_name TEXT,
      unidade_medida TEXT,
      deletado_em TEXT
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
      ordem INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.compras} (
      id INTEGER PRIMARY KEY,
      status TEXT NOT NULL,
      valor_final_centavos INTEGER NOT NULL,
      valor_pendente_centavos INTEGER NOT NULL,
      data_compra TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensCompra} (
      id INTEGER PRIMARY KEY,
      compra_id INTEGER NOT NULL,
      item_type TEXT NOT NULL,
      produto_id INTEGER,
      produto_variante_id INTEGER,
      nome_item_snapshot TEXT,
      sku_variante_snapshot TEXT,
      cor_variante_snapshot TEXT,
      tamanho_variante_snapshot TEXT,
      quantidade_mil INTEGER NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.compraPagamentos} (
      id INTEGER PRIMARY KEY,
      valor_centavos INTEGER NOT NULL,
      data_hora TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fiado} (
      id INTEGER PRIMARY KEY,
      venda_id INTEGER,
      valor_aberto_centavos INTEGER,
      status TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fiadoLancamentos} (
      id INTEGER PRIMARY KEY,
      fiado_id INTEGER,
      tipo_lancamento TEXT,
      valor_centavos INTEGER,
      data_lancamento TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.caixaMovimentos} (
      id INTEGER PRIMARY KEY,
      tipo_movimento TEXT,
      valor_centavos INTEGER,
      descricao TEXT,
      referencia_tipo TEXT,
      referencia_id INTEGER,
      criado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.clientes} (
      id INTEGER PRIMARY KEY,
      nome TEXT,
      credit_balance INTEGER,
      deletado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.customerCreditTransactions} (
      id INTEGER PRIMARY KEY,
      customer_id INTEGER,
      type TEXT,
      amount INTEGER,
      is_reversed INTEGER,
      created_at TEXT
    )
  ''');
}
