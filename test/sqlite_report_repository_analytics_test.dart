import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/utils/payment_method_note_codec.dart';
import 'package:erp_pdv_app/modules/clientes/domain/entities/customer_credit_transaction.dart';
import 'package:erp_pdv_app/modules/relatorios/data/sqlite_report_repository.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late SqliteReportRepository repository;
  late ReportFilter dailyFilter;

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
    await _seedAnalyticsScenario(database);
    dailyFilter = ReportFilter(
      start: DateTime(2026, 4, 17),
      endExclusive: DateTime(2026, 4, 18),
      grouping: ReportGrouping.day,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('overview respeita cancelamentos excluidos e incluidos', () async {
    final defaultOverview = await repository.fetchOverview(filter: dailyFilter);
    final inclusiveOverview = await repository.fetchOverview(
      filter: dailyFilter.copyWith(includeCanceled: true),
    );

    expect(defaultOverview.salesCount, 3);
    expect(defaultOverview.netSalesCents, 26000);
    expect(defaultOverview.grossSalesCents, 29000);
    expect(defaultOverview.totalDiscountCents, 3000);
    expect(defaultOverview.cancelledSalesCount, 1);
    expect(defaultOverview.cancelledSalesCents, 5000);

    expect(inclusiveOverview.salesCount, 4);
    expect(inclusiveOverview.netSalesCents, 31000);
    expect(inclusiveOverview.grossSalesCents, 34000);
  });

  test('sales trend agrupa por dia e usa intervalo exclusivo', () async {
    final points = await repository.fetchSalesTrend(filter: dailyFilter);

    expect(points, hasLength(1));
    expect(points.first.salesCount, 3);
    expect(points.first.netSalesCents, 26000);
    expect(points.first.bucketStart, DateTime(2026, 4, 17));
    expect(points.first.bucketEndExclusive, DateTime(2026, 4, 18));
  });

  test('top products ordena por receita e ignora venda cancelada', () async {
    final products = await repository.fetchTopProducts(
      filter: dailyFilter,
      limit: 10,
    );

    expect(products, hasLength(2));
    expect(products.first.productName, 'Camiseta Basic');
    expect(products.first.soldAmountCents, 17000);
    expect(products.first.totalCostCents, 9500);
    expect(products.last.productName, 'Moletom Urban');
    expect(products.last.soldAmountCents, 9000);
  });

  test(
    'profitability traz receita, custo, lucro e margem por produto',
    () async {
      final rows = await repository.fetchProfitability(filter: dailyFilter);

      expect(rows, isNotEmpty);
      expect(rows.first.label, 'Camiseta Basic');
      expect(rows.first.revenueCents, 17000);
      expect(rows.first.costCents, 9500);
      expect(rows.first.profitCents, 7500);
      expect(rows.first.marginBasisPoints, 4412);
    },
  );

  test('cashflow resume entradas, saidas e linha do tempo', () async {
    final cashflow = await repository.fetchCashflow(filter: dailyFilter);

    expect(cashflow.totalReceivedCents, 23000);
    expect(cashflow.fiadoReceiptsCents, 6000);
    expect(cashflow.manualEntriesCents, 1500);
    expect(cashflow.outflowsCents, 7500);
    expect(cashflow.withdrawalsCents, 2000);
    expect(cashflow.netFlowCents, 17000);
    expect(cashflow.timeline, hasLength(1));
    expect(cashflow.timeline.first.netCents, 17000);
  });

  test('inventory health aponta estoque critico e divergencia', () async {
    final summary = await repository.fetchInventoryHealth(filter: dailyFilter);

    expect(summary.zeroedItemsCount, 1);
    expect(summary.belowMinimumItemsCount, 2);
    expect(summary.divergenceItemsCount, 1);
    expect(summary.criticalItems, isNotEmpty);
    expect(summary.mostMovedItems.first.quantityMil, 5000);
  });

  test('customer ranking combina compra, fiado e haver', () async {
    final rows = await repository.fetchCustomerRanking(
      filter: dailyFilter,
      limit: 10,
    );

    expect(rows, hasLength(3));
    expect(rows.first.customerName, 'Alice');
    expect(rows.first.totalPurchasedCents, 19000);
    expect(rows.first.pendingFiadoCents, 3000);
    expect(rows.first.creditBalanceCents, 500);
    expect(rows.any((row) => row.customerName == 'Carla'), isTrue);
  });

  test('purchase summary agrega por fornecedor e variante', () async {
    final summary = await repository.fetchPurchaseSummary(
      filter: dailyFilter,
      limit: 10,
    );

    expect(summary.purchasesCount, 2);
    expect(summary.totalPurchasedCents, 15000);
    expect(summary.totalPendingCents, 2000);
    expect(summary.totalPaidCents, 8000);
    expect(summary.supplierRows.first.label, 'Fornecedor A');
    expect(summary.supplierRows.first.amountCents, 10000);
    expect(summary.replenishmentRows.first.secondaryId, 10);
    expect(summary.replenishmentRows.first.quantityMil, 3000);
  });
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE ${TableNames.clientes} (
      id INTEGER PRIMARY KEY,
      nome TEXT,
      ativo INTEGER,
      credit_balance INTEGER,
      deletado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.vendas} (
      id INTEGER PRIMARY KEY,
      cliente_id INTEGER,
      tipo_venda TEXT,
      forma_pagamento TEXT,
      status TEXT,
      desconto_centavos INTEGER,
      acrescimo_centavos INTEGER,
      valor_total_centavos INTEGER,
      valor_final_centavos INTEGER,
      data_venda TEXT,
      cancelada_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensVenda} (
      id INTEGER PRIMARY KEY,
      venda_id INTEGER,
      produto_id INTEGER,
      produto_variante_id INTEGER,
      nome_produto_snapshot TEXT,
      sku_variante_snapshot TEXT,
      cor_variante_snapshot TEXT,
      tamanho_variante_snapshot TEXT,
      unidade_medida_snapshot TEXT,
      quantidade_mil INTEGER,
      valor_unitario_centavos INTEGER,
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
      categoria_id INTEGER,
      custo_centavos INTEGER,
      preco_venda_centavos INTEGER,
      estoque_mil INTEGER,
      ativo INTEGER,
      atualizado_em TEXT,
      deletado_em TEXT,
      codigo_barras TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.produtoVariantes} (
      id INTEGER PRIMARY KEY,
      produto_id INTEGER,
      sku TEXT,
      cor TEXT,
      tamanho TEXT,
      estoque_mil INTEGER,
      ordem INTEGER,
      ativo INTEGER,
      atualizado_em TEXT,
      preco_adicional_centavos INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fiado} (
      id INTEGER PRIMARY KEY,
      venda_id INTEGER,
      cliente_id INTEGER,
      valor_aberto_centavos INTEGER,
      status TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fiadoLancamentos} (
      id INTEGER PRIMARY KEY,
      fiado_id INTEGER,
      cliente_id INTEGER,
      tipo_lancamento TEXT,
      valor_centavos INTEGER,
      data_lancamento TEXT,
      caixa_movimento_id INTEGER
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
    CREATE TABLE ${TableNames.customerCreditTransactions} (
      id INTEGER PRIMARY KEY,
      customer_id INTEGER,
      type TEXT,
      amount INTEGER,
      is_reversed INTEGER,
      created_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.fornecedores} (
      id INTEGER PRIMARY KEY,
      nome TEXT,
      nome_fantasia TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.compras} (
      id INTEGER PRIMARY KEY,
      fornecedor_id INTEGER,
      status TEXT,
      valor_final_centavos INTEGER,
      valor_pendente_centavos INTEGER,
      data_compra TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensCompra} (
      id INTEGER PRIMARY KEY,
      compra_id INTEGER,
      item_type TEXT,
      produto_id INTEGER,
      produto_variante_id INTEGER,
      supply_id INTEGER,
      nome_item_snapshot TEXT,
      unidade_medida_snapshot TEXT,
      quantidade_mil INTEGER,
      custo_unitario_centavos INTEGER,
      subtotal_centavos INTEGER,
      sku_variante_snapshot TEXT,
      cor_variante_snapshot TEXT,
      tamanho_variante_snapshot TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.compraPagamentos} (
      id INTEGER PRIMARY KEY,
      compra_id INTEGER,
      valor_centavos INTEGER,
      data_hora TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.inventorySettings} (
      id INTEGER PRIMARY KEY,
      product_id INTEGER,
      product_variant_id INTEGER,
      minimum_stock_mil INTEGER,
      reorder_point_mil INTEGER,
      allow_negative_stock INTEGER,
      updated_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.inventoryMovements} (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      product_id INTEGER,
      product_variant_id INTEGER,
      movement_type TEXT,
      quantity_delta_mil INTEGER,
      stock_before_mil INTEGER,
      stock_after_mil INTEGER,
      reference_type TEXT,
      reference_id INTEGER,
      reason TEXT,
      notes TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.inventoryCountSessions} (
      id INTEGER PRIMARY KEY,
      uuid TEXT,
      name TEXT,
      status TEXT,
      created_at TEXT,
      updated_at TEXT,
      applied_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.inventoryCountItems} (
      id INTEGER PRIMARY KEY,
      count_session_id INTEGER,
      product_id INTEGER,
      product_variant_id INTEGER,
      system_stock_mil INTEGER,
      counted_stock_mil INTEGER,
      difference_mil INTEGER,
      notes TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''');
}

Future<void> _seedAnalyticsScenario(Database database) async {
  const day = '2026-04-17T10:00:00.000';
  const later = '2026-04-17T12:00:00.000';
  const previousDay = '2026-04-16T10:00:00.000';

  await database.insert(TableNames.clientes, {
    'id': 1,
    'nome': 'Alice',
    'ativo': 1,
    'credit_balance': 500,
    'deletado_em': null,
  });
  await database.insert(TableNames.clientes, {
    'id': 2,
    'nome': 'Bruno',
    'ativo': 1,
    'credit_balance': 0,
    'deletado_em': null,
  });
  await database.insert(TableNames.clientes, {
    'id': 3,
    'nome': 'Carla',
    'ativo': 0,
    'credit_balance': 200,
    'deletado_em': null,
  });

  await database.insert(TableNames.produtos, {
    'id': 1,
    'nome': 'Camiseta Basic',
    'model_name': 'Camiseta Basic',
    'unidade_medida': 'un',
    'categoria_id': null,
    'custo_centavos': 3000,
    'preco_venda_centavos': 6000,
    'estoque_mil': 0,
    'ativo': 1,
    'atualizado_em': day,
    'deletado_em': null,
    'codigo_barras': null,
  });
  await database.insert(TableNames.produtos, {
    'id': 2,
    'nome': 'Moletom Urban',
    'model_name': 'Moletom Urban',
    'unidade_medida': 'un',
    'categoria_id': null,
    'custo_centavos': 4000,
    'preco_venda_centavos': 9000,
    'estoque_mil': 5000,
    'ativo': 1,
    'atualizado_em': day,
    'deletado_em': null,
    'codigo_barras': null,
  });
  await database.insert(TableNames.produtos, {
    'id': 3,
    'nome': 'Boné Zero',
    'model_name': 'Boné Zero',
    'unidade_medida': 'un',
    'categoria_id': null,
    'custo_centavos': 2000,
    'preco_venda_centavos': 5000,
    'estoque_mil': 0,
    'ativo': 1,
    'atualizado_em': day,
    'deletado_em': null,
    'codigo_barras': null,
  });

  await database.insert(TableNames.produtoVariantes, {
    'id': 10,
    'produto_id': 1,
    'sku': 'CAM-P',
    'cor': 'Preta',
    'tamanho': 'P',
    'estoque_mil': 4000,
    'ordem': 1,
    'ativo': 1,
    'atualizado_em': day,
    'preco_adicional_centavos': 0,
  });
  await database.insert(TableNames.produtoVariantes, {
    'id': 11,
    'produto_id': 1,
    'sku': 'CAM-M',
    'cor': 'Preta',
    'tamanho': 'M',
    'estoque_mil': 2000,
    'ordem': 2,
    'ativo': 1,
    'atualizado_em': day,
    'preco_adicional_centavos': 0,
  });

  await database.insert(TableNames.vendas, {
    'id': 1,
    'cliente_id': 1,
    'tipo_venda': 'vista',
    'forma_pagamento': 'pix',
    'status': 'ativa',
    'desconto_centavos': 2000,
    'acrescimo_centavos': 0,
    'valor_total_centavos': 12000,
    'valor_final_centavos': 10000,
    'data_venda': day,
    'cancelada_em': null,
  });
  await database.insert(TableNames.vendas, {
    'id': 2,
    'cliente_id': 1,
    'tipo_venda': 'fiado',
    'forma_pagamento': 'fiado',
    'status': 'ativa',
    'desconto_centavos': 1000,
    'acrescimo_centavos': 0,
    'valor_total_centavos': 10000,
    'valor_final_centavos': 9000,
    'data_venda': day,
    'cancelada_em': null,
  });
  await database.insert(TableNames.vendas, {
    'id': 3,
    'cliente_id': 2,
    'tipo_venda': 'vista',
    'forma_pagamento': 'cartao',
    'status': 'cancelada',
    'desconto_centavos': 0,
    'acrescimo_centavos': 0,
    'valor_total_centavos': 5000,
    'valor_final_centavos': 5000,
    'data_venda': day,
    'cancelada_em': later,
  });
  await database.insert(TableNames.vendas, {
    'id': 4,
    'cliente_id': 2,
    'tipo_venda': 'vista',
    'forma_pagamento': 'cartao',
    'status': 'ativa',
    'desconto_centavos': 0,
    'acrescimo_centavos': 0,
    'valor_total_centavos': 7000,
    'valor_final_centavos': 7000,
    'data_venda': day,
    'cancelada_em': null,
  });
  await database.insert(TableNames.vendas, {
    'id': 5,
    'cliente_id': 2,
    'tipo_venda': 'vista',
    'forma_pagamento': 'dinheiro',
    'status': 'ativa',
    'desconto_centavos': 0,
    'acrescimo_centavos': 0,
    'valor_total_centavos': 2000,
    'valor_final_centavos': 2000,
    'data_venda': previousDay,
    'cancelada_em': null,
  });

  await database.insert(TableNames.itensVenda, {
    'id': 1,
    'venda_id': 1,
    'produto_id': 1,
    'produto_variante_id': 10,
    'nome_produto_snapshot': 'Camiseta Basic',
    'sku_variante_snapshot': 'CAM-P',
    'cor_variante_snapshot': 'Preta',
    'tamanho_variante_snapshot': 'P',
    'unidade_medida_snapshot': 'un',
    'quantidade_mil': 2000,
    'valor_unitario_centavos': 5000,
    'subtotal_centavos': 10000,
    'custo_unitario_centavos': 3000,
    'custo_total_centavos': 6000,
  });
  await database.insert(TableNames.itensVenda, {
    'id': 2,
    'venda_id': 2,
    'produto_id': 2,
    'produto_variante_id': null,
    'nome_produto_snapshot': 'Moletom Urban',
    'sku_variante_snapshot': null,
    'cor_variante_snapshot': null,
    'tamanho_variante_snapshot': null,
    'unidade_medida_snapshot': 'un',
    'quantidade_mil': 1000,
    'valor_unitario_centavos': 9000,
    'subtotal_centavos': 9000,
    'custo_unitario_centavos': 4000,
    'custo_total_centavos': 4000,
  });
  await database.insert(TableNames.itensVenda, {
    'id': 3,
    'venda_id': 3,
    'produto_id': 1,
    'produto_variante_id': 10,
    'nome_produto_snapshot': 'Camiseta Basic',
    'sku_variante_snapshot': 'CAM-P',
    'cor_variante_snapshot': 'Preta',
    'tamanho_variante_snapshot': 'P',
    'unidade_medida_snapshot': 'un',
    'quantidade_mil': 1000,
    'valor_unitario_centavos': 5000,
    'subtotal_centavos': 5000,
    'custo_unitario_centavos': 3000,
    'custo_total_centavos': 3000,
  });
  await database.insert(TableNames.itensVenda, {
    'id': 4,
    'venda_id': 4,
    'produto_id': 1,
    'produto_variante_id': 11,
    'nome_produto_snapshot': 'Camiseta Basic',
    'sku_variante_snapshot': 'CAM-M',
    'cor_variante_snapshot': 'Preta',
    'tamanho_variante_snapshot': 'M',
    'unidade_medida_snapshot': 'un',
    'quantidade_mil': 1000,
    'valor_unitario_centavos': 7000,
    'subtotal_centavos': 7000,
    'custo_unitario_centavos': 3500,
    'custo_total_centavos': 3500,
  });

  await database.insert(TableNames.fiado, {
    'id': 1,
    'venda_id': 2,
    'cliente_id': 1,
    'valor_aberto_centavos': 3000,
    'status': 'parcial',
  });

  await database.insert(TableNames.caixaMovimentos, {
    'id': 1,
    'tipo_movimento': 'venda',
    'valor_centavos': 10000,
    'descricao': '',
    'referencia_tipo': 'venda',
    'referencia_id': 1,
    'criado_em': day,
  });
  await database.insert(TableNames.caixaMovimentos, {
    'id': 2,
    'tipo_movimento': 'recebimento_fiado',
    'valor_centavos': 6000,
    'descricao': PaymentMethodNoteCodec.withPaymentMethod(
      'Recebimento parcial',
      paymentMethod: PaymentMethod.cash,
    ),
    'referencia_tipo': 'fiado',
    'referencia_id': 1,
    'criado_em': later,
  });
  await database.insert(TableNames.caixaMovimentos, {
    'id': 3,
    'tipo_movimento': 'venda',
    'valor_centavos': 7000,
    'descricao': '',
    'referencia_tipo': 'venda',
    'referencia_id': 4,
    'criado_em': day,
  });
  await database.insert(TableNames.caixaMovimentos, {
    'id': 4,
    'tipo_movimento': 'cancelamento',
    'valor_centavos': -5000,
    'descricao': 'Estorno venda 3',
    'referencia_tipo': 'venda',
    'referencia_id': 3,
    'criado_em': later,
  });
  await database.insert(TableNames.caixaMovimentos, {
    'id': 5,
    'tipo_movimento': 'sangria',
    'valor_centavos': -2000,
    'descricao': 'Retirada',
    'referencia_tipo': null,
    'referencia_id': null,
    'criado_em': later,
  });
  await database.insert(TableNames.caixaMovimentos, {
    'id': 6,
    'tipo_movimento': 'suprimento',
    'valor_centavos': 1500,
    'descricao': 'Entrada manual',
    'referencia_tipo': null,
    'referencia_id': null,
    'criado_em': later,
  });
  await database.insert(TableNames.caixaMovimentos, {
    'id': 7,
    'tipo_movimento': 'ajuste',
    'valor_centavos': -500,
    'descricao': 'Ajuste manual',
    'referencia_tipo': null,
    'referencia_id': null,
    'criado_em': later,
  });

  await database.insert(TableNames.fiadoLancamentos, {
    'id': 1,
    'fiado_id': 1,
    'cliente_id': 1,
    'tipo_lancamento': 'pagamento',
    'valor_centavos': 6000,
    'data_lancamento': later,
    'caixa_movimento_id': 2,
  });

  await database.insert(TableNames.customerCreditTransactions, {
    'id': 1,
    'customer_id': 1,
    'type': CustomerCreditTransactionType.manualCredit,
    'amount': 500,
    'is_reversed': 0,
    'created_at': day,
  });

  await database.insert(TableNames.fornecedores, {
    'id': 1,
    'nome': 'Fornecedor A',
    'nome_fantasia': null,
  });
  await database.insert(TableNames.fornecedores, {
    'id': 2,
    'nome': 'Fornecedor B',
    'nome_fantasia': null,
  });

  await database.insert(TableNames.compras, {
    'id': 1,
    'fornecedor_id': 1,
    'status': 'recebida',
    'valor_final_centavos': 10000,
    'valor_pendente_centavos': 2000,
    'data_compra': day,
  });
  await database.insert(TableNames.compras, {
    'id': 2,
    'fornecedor_id': 2,
    'status': 'paga',
    'valor_final_centavos': 5000,
    'valor_pendente_centavos': 0,
    'data_compra': day,
  });

  await database.insert(TableNames.itensCompra, {
    'id': 1,
    'compra_id': 1,
    'item_type': 'product',
    'produto_id': 1,
    'produto_variante_id': 10,
    'supply_id': null,
    'nome_item_snapshot': 'Camiseta Basic',
    'unidade_medida_snapshot': 'un',
    'quantidade_mil': 3000,
    'custo_unitario_centavos': 2000,
    'subtotal_centavos': 6000,
    'sku_variante_snapshot': 'CAM-P',
    'cor_variante_snapshot': 'Preta',
    'tamanho_variante_snapshot': 'P',
  });
  await database.insert(TableNames.itensCompra, {
    'id': 2,
    'compra_id': 1,
    'item_type': 'supply',
    'produto_id': null,
    'produto_variante_id': null,
    'supply_id': 1,
    'nome_item_snapshot': 'Queijo',
    'unidade_medida_snapshot': 'kg',
    'quantidade_mil': 5000,
    'custo_unitario_centavos': 800,
    'subtotal_centavos': 4000,
    'sku_variante_snapshot': null,
    'cor_variante_snapshot': null,
    'tamanho_variante_snapshot': null,
  });
  await database.insert(TableNames.itensCompra, {
    'id': 3,
    'compra_id': 2,
    'item_type': 'product',
    'produto_id': 2,
    'produto_variante_id': null,
    'supply_id': null,
    'nome_item_snapshot': 'Moletom Urban',
    'unidade_medida_snapshot': 'un',
    'quantidade_mil': 2000,
    'custo_unitario_centavos': 2500,
    'subtotal_centavos': 5000,
    'sku_variante_snapshot': null,
    'cor_variante_snapshot': null,
    'tamanho_variante_snapshot': null,
  });

  await database.insert(TableNames.compraPagamentos, {
    'id': 1,
    'compra_id': 1,
    'valor_centavos': 5000,
    'data_hora': day,
  });
  await database.insert(TableNames.compraPagamentos, {
    'id': 2,
    'compra_id': 2,
    'valor_centavos': 3000,
    'data_hora': later,
  });

  await database.insert(TableNames.inventorySettings, {
    'id': 1,
    'product_id': 1,
    'product_variant_id': 10,
    'minimum_stock_mil': 5000,
    'reorder_point_mil': 7000,
    'allow_negative_stock': 0,
    'updated_at': day,
  });
  await database.insert(TableNames.inventorySettings, {
    'id': 2,
    'product_id': 2,
    'product_variant_id': null,
    'minimum_stock_mil': 6000,
    'reorder_point_mil': 7000,
    'allow_negative_stock': 0,
    'updated_at': day,
  });
  await database.insert(TableNames.inventorySettings, {
    'id': 3,
    'product_id': 3,
    'product_variant_id': null,
    'minimum_stock_mil': 0,
    'reorder_point_mil': 0,
    'allow_negative_stock': 0,
    'updated_at': day,
  });

  await database.insert(TableNames.inventoryMovements, {
    'id': 1,
    'uuid': 'mov-1',
    'product_id': 1,
    'product_variant_id': 10,
    'movement_type': 'sale_out',
    'quantity_delta_mil': -2000,
    'stock_before_mil': 6000,
    'stock_after_mil': 4000,
    'reference_type': 'sale',
    'reference_id': 1,
    'reason': null,
    'notes': null,
    'created_at': day,
    'updated_at': day,
  });
  await database.insert(TableNames.inventoryMovements, {
    'id': 2,
    'uuid': 'mov-2',
    'product_id': 1,
    'product_variant_id': 10,
    'movement_type': 'purchase_in',
    'quantity_delta_mil': 3000,
    'stock_before_mil': 1000,
    'stock_after_mil': 4000,
    'reference_type': 'purchase',
    'reference_id': 1,
    'reason': null,
    'notes': null,
    'created_at': later,
    'updated_at': later,
  });
  await database.insert(TableNames.inventoryMovements, {
    'id': 3,
    'uuid': 'mov-3',
    'product_id': 1,
    'product_variant_id': 11,
    'movement_type': 'sale_out',
    'quantity_delta_mil': -1000,
    'stock_before_mil': 3000,
    'stock_after_mil': 2000,
    'reference_type': 'sale',
    'reference_id': 4,
    'reason': null,
    'notes': null,
    'created_at': later,
    'updated_at': later,
  });
  await database.insert(TableNames.inventoryMovements, {
    'id': 4,
    'uuid': 'mov-4',
    'product_id': 3,
    'product_variant_id': null,
    'movement_type': 'adjustment_out',
    'quantity_delta_mil': -100,
    'stock_before_mil': 100,
    'stock_after_mil': 0,
    'reference_type': 'manual_adjustment',
    'reference_id': null,
    'reason': 'quebra',
    'notes': null,
    'created_at': later,
    'updated_at': later,
  });

  await database.insert(TableNames.inventoryCountSessions, {
    'id': 1,
    'uuid': 'count-1',
    'name': 'Inventario Abril',
    'status': 'reviewed',
    'created_at': day,
    'updated_at': later,
    'applied_at': null,
  });

  await database.insert(TableNames.inventoryCountItems, {
    'id': 1,
    'count_session_id': 1,
    'product_id': 3,
    'product_variant_id': null,
    'system_stock_mil': 500,
    'counted_stock_mil': 0,
    'difference_mil': -500,
    'notes': null,
    'created_at': day,
    'updated_at': later,
  });
}
