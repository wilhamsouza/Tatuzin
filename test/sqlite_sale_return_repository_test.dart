import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/modules/carrinho/domain/entities/cart_item.dart';
import 'package:erp_pdv_app/modules/clientes/domain/entities/customer_credit_transaction.dart';
import 'package:erp_pdv_app/modules/historico_vendas/data/sqlite_sale_return_repository.dart';
import 'package:erp_pdv_app/modules/historico_vendas/domain/entities/sale_return.dart';
import 'package:erp_pdv_app/modules/insumos/domain/entities/supply_inventory.dart';
import 'package:erp_pdv_app/modules/vendas/data/sqlite_sale_repository.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/checkout_input.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/completed_sale.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late _FakeSaleRepository fakeSaleRepository;
  late SqliteSaleReturnRepository repository;

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
    fakeSaleRepository = _FakeSaleRepository();
    repository = SqliteSaleReturnRepository.forDatabase(
      databaseLoader: () async => database,
      operationalContext: AppOperationalContext(
        environment: const AppEnvironment.localDefault(),
        session: AppSession.localDefault(),
      ),
      saleRepository: fakeSaleRepository,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('devolucao simples com cliente recompõe estoque e gera haver', () async {
    await _insertClient(database, customerId: 1, creditBalance: 0);
    await _insertFashionProduct(database, variantMStockMil: 0);
    await _insertSale(database, saleId: 1, customerId: 1);
    await _insertSoldItem(database, saleId: 1, saleItemId: 1, variantId: 10);

    final result = await repository.registerReturn(
      const SaleReturnInput(
        saleId: 1,
        mode: SaleReturnMode.returnOnly,
        reason: 'Cliente preferiu outro tamanho',
        returnedItems: [SaleReturnItemInput(saleItemId: 1, quantityMil: 1000)],
      ),
    );

    expect(result.mode, SaleReturnMode.returnOnly);
    expect(result.creditedAmountCents, 12000);
    expect(result.refundAmountCents, 0);
    expect(await _variantStock(database, 10), 1000);
    expect(await _productStock(database, 1), 1000);
    expect(await _customerCreditBalance(database, 1), 12000);

    final returns = await repository.listForSale(1);
    expect(returns, hasLength(1));
    expect(returns.single.items, hasLength(1));
    expect(returns.single.items.single.variantSummary, 'Preta / P');
    expect(returns.single.creditedAmountCents, 12000);

    final creditRows = await database.query(
      TableNames.customerCreditTransactions,
      where: 'customer_id = ?',
      whereArgs: const [1],
    );
    expect(creditRows, hasLength(1));
    expect(
      creditRows.single['type'],
      CustomerCreditTransactionType.saleReturnCredit,
    );
  });

  test(
    'troca com nova venda aplica credito na nova venda e preserva trilha',
    () async {
      await _insertClient(database, customerId: 1, creditBalance: 0);
      await _insertFashionProduct(database, variantMStockMil: 2000);
      await _insertSale(database, saleId: 1, customerId: 1);
      await _insertSoldItem(database, saleId: 1, saleItemId: 1, variantId: 10);

      final result = await repository.registerReturn(
        const SaleReturnInput(
          saleId: 1,
          mode: SaleReturnMode.exchangeWithNewSale,
          reason: 'Troca de tamanho',
          returnedItems: [
            SaleReturnItemInput(saleItemId: 1, quantityMil: 1000),
          ],
          replacementItems: [
            CartItem(
              id: 'replacement-1',
              productId: 1,
              productVariantId: 11,
              productName: 'Camiseta Basic',
              baseProductId: null,
              baseProductName: null,
              variantSku: 'CAM-BASIC-PRETA-M',
              variantColorLabel: 'Preta',
              variantSizeLabel: 'M',
              quantityMil: 1000,
              availableStockMil: 2000,
              unitPriceCents: 9000,
              unitMeasure: 'un',
              productType: 'grade',
            ),
          ],
          replacementPaymentMethod: PaymentMethod.pix,
        ),
      );

      expect(result.mode, SaleReturnMode.exchangeWithNewSale);
      expect(result.appliedDiscountCents, 9000);
      expect(result.creditedAmountCents, 3000);
      expect(result.refundAmountCents, 0);
      expect(result.replacementSaleId, 900);
      expect(result.replacementReceiptNumber, 'TR-900');
      expect(fakeSaleRepository.lastCheckoutInput, isNotNull);
      expect(fakeSaleRepository.lastCheckoutInput!.discountCents, 9000);
      expect(
        fakeSaleRepository.lastCheckoutInput!.paymentMethod,
        PaymentMethod.pix,
      );
      expect(await _variantStock(database, 10), 1000);
      expect(await _productStock(database, 1), 3000);
      expect(await _customerCreditBalance(database, 1), 3000);

      final replacementRows = await database.query(
        TableNames.vendas,
        columns: const ['venda_origem_id', 'numero_cupom'],
        where: 'id = ?',
        whereArgs: const [900],
        limit: 1,
      );
      expect(replacementRows.single['venda_origem_id'], 1);
      expect(replacementRows.single['numero_cupom'], 'TR-900');

      final returns = await repository.listForSale(1);
      expect(returns.single.replacementSaleId, 900);
      expect(returns.single.replacementSaleReceiptNumber, 'TR-900');
    },
  );

  test('nao permite devolver o mesmo item acima do saldo restante', () async {
    await _insertClient(database, customerId: 1, creditBalance: 0);
    await _insertFashionProduct(database, variantMStockMil: 0);
    await _insertSale(database, saleId: 1, customerId: 1);
    await _insertSoldItem(database, saleId: 1, saleItemId: 1, variantId: 10);

    await repository.registerReturn(
      const SaleReturnInput(
        saleId: 1,
        mode: SaleReturnMode.returnOnly,
        reason: 'Primeira devolucao',
        returnedItems: [SaleReturnItemInput(saleItemId: 1, quantityMil: 1000)],
      ),
    );

    await expectLater(
      () => repository.registerReturn(
        const SaleReturnInput(
          saleId: 1,
          mode: SaleReturnMode.returnOnly,
          reason: 'Tentativa duplicada',
          returnedItems: [
            SaleReturnItemInput(saleItemId: 1, quantityMil: 1000),
          ],
        ),
      ),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.message,
          'message',
          contains('excede o saldo disponivel'),
        ),
      ),
    );
  });
}

class _FakeSaleRepository implements SqliteSaleRepository {
  CheckoutInput? lastCheckoutInput;

  @override
  Future<CompletedSale> completeCashSaleWithinTransaction(
    DatabaseExecutor txn, {
    required CheckoutInput input,
  }) async {
    lastCheckoutInput = input;
    const saleId = 900;
    const soldAt = '2026-04-16T13:00:00Z';
    await txn.insert(TableNames.vendas, {
      'id': saleId,
      'uuid': 'sale:return:$saleId',
      'cliente_id': input.clientId,
      'status': SaleStatus.active.dbValue,
      'forma_pagamento': input.paymentMethod.dbValue,
      'numero_cupom': 'TR-900',
      'venda_origem_id': null,
    });
    return CompletedSale(
      saleId: saleId,
      receiptNumber: 'TR-900',
      totalCents: input.finalTotalCents,
      itemsCount: input.items.length,
      soldAt: DateTime.parse(soldAt),
      saleType: SaleType.cash,
      paymentMethod: input.paymentMethod,
      supplyConsumption: const SupplySaleConsumptionResult.empty(),
      clientId: input.clientId,
    );
  }

  @override
  Future<void> registerCashEventForSyncWithinTransaction(
    DatabaseExecutor txn, {
    required int movementId,
    required String movementUuid,
    required DateTime createdAt,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE ${TableNames.produtos} (
      id INTEGER PRIMARY KEY,
      estoque_mil INTEGER,
      atualizado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.produtoVariantes} (
      id INTEGER PRIMARY KEY,
      produto_id INTEGER NOT NULL,
      estoque_mil INTEGER,
      ativo INTEGER NOT NULL DEFAULT 1,
      atualizado_em TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.vendas} (
      id INTEGER PRIMARY KEY,
      uuid TEXT NOT NULL,
      cliente_id INTEGER,
      status TEXT NOT NULL,
      forma_pagamento TEXT,
      numero_cupom TEXT,
      venda_origem_id INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE ${TableNames.itensVenda} (
      id INTEGER PRIMARY KEY,
      venda_id INTEGER NOT NULL,
      produto_id INTEGER NOT NULL,
      produto_variante_id INTEGER,
      quantidade_mil INTEGER NOT NULL,
      subtotal_centavos INTEGER NOT NULL,
      valor_unitario_centavos INTEGER NOT NULL,
      nome_produto_snapshot TEXT,
      sku_variante_snapshot TEXT,
      cor_variante_snapshot TEXT,
      tamanho_variante_snapshot TEXT
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
}

Future<void> _insertClient(
  Database db, {
  required int customerId,
  required int creditBalance,
}) async {
  await db.insert(TableNames.clientes, {
    'id': customerId,
    'nome': 'Cliente Teste',
    'credit_balance': creditBalance,
    'deletado_em': null,
    'atualizado_em': _nowIso,
  });
}

Future<void> _insertFashionProduct(
  Database db, {
  required int variantMStockMil,
}) async {
  await db.insert(TableNames.produtos, {
    'id': 1,
    'estoque_mil': variantMStockMil,
    'atualizado_em': _nowIso,
  });
  await db.insert(TableNames.produtoVariantes, {
    'id': 10,
    'produto_id': 1,
    'estoque_mil': 0,
    'ativo': 1,
    'atualizado_em': _nowIso,
  });
  await db.insert(TableNames.produtoVariantes, {
    'id': 11,
    'produto_id': 1,
    'estoque_mil': variantMStockMil,
    'ativo': 1,
    'atualizado_em': _nowIso,
  });
}

Future<void> _insertSale(
  Database db, {
  required int saleId,
  required int customerId,
}) async {
  await db.insert(TableNames.vendas, {
    'id': saleId,
    'uuid': 'sale-$saleId',
    'cliente_id': customerId,
    'status': SaleStatus.active.dbValue,
    'forma_pagamento': PaymentMethod.pix.dbValue,
    'numero_cupom': 'CP-$saleId',
    'venda_origem_id': null,
  });
}

Future<void> _insertSoldItem(
  Database db, {
  required int saleId,
  required int saleItemId,
  required int variantId,
}) async {
  final sizeLabel = variantId == 10 ? 'P' : 'M';
  final sku = variantId == 10 ? 'CAM-BASIC-PRETA-P' : 'CAM-BASIC-PRETA-M';
  await db.insert(TableNames.itensVenda, {
    'id': saleItemId,
    'venda_id': saleId,
    'produto_id': 1,
    'produto_variante_id': variantId,
    'quantidade_mil': 1000,
    'subtotal_centavos': 12000,
    'valor_unitario_centavos': 12000,
    'nome_produto_snapshot': 'Camiseta Basic',
    'sku_variante_snapshot': sku,
    'cor_variante_snapshot': 'Preta',
    'tamanho_variante_snapshot': sizeLabel,
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

Future<int?> _customerCreditBalance(Database db, int customerId) async {
  final rows = await db.query(
    TableNames.clientes,
    columns: const ['credit_balance'],
    where: 'id = ?',
    whereArgs: [customerId],
    limit: 1,
  );
  return rows.first['credit_balance'] as int?;
}

final _nowIso = DateTime.parse('2026-04-16T12:00:00Z').toIso8601String();
