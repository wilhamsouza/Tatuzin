import '../../clientes/domain/entities/customer_credit_transaction.dart';
import '../domain/entities/report_customer_credit_summary.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/utils/payment_method_note_codec.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../domain/entities/report_payment_summary.dart';
import '../domain/entities/report_period.dart';
import '../domain/entities/report_sold_product_summary.dart';
import '../domain/entities/report_summary.dart';
import '../domain/repositories/report_repository.dart';

class SqliteReportRepository implements ReportRepository {
  SqliteReportRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<ReportSummary> fetchSummary({required ReportPeriod period}) async {
    final database = await _appDatabase.database;
    final range = period.resolveRange(DateTime.now());
    final startIso = range.start.toIso8601String();
    final endIso = range.endExclusive.toIso8601String();
    const soldAmountExpression = '''
      COALESCE(
        iv.subtotal_centavos,
        CAST(ROUND((iv.quantidade_mil * iv.valor_unitario_centavos) / 1000.0, 0) AS INTEGER)
      )
    ''';
    const costAmountExpression = '''
      COALESCE(
        iv.custo_total_centavos,
        CAST(ROUND((iv.quantidade_mil * iv.custo_unitario_centavos) / 1000.0, 0) AS INTEGER)
      )
    ''';

    final salesRows = await database.rawQuery(
      '''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_final_centavos), 0) AS total
      FROM ${TableNames.vendas}
      WHERE status = 'ativa'
        AND data_venda >= ?
        AND data_venda < ?
    ''',
      [startIso, endIso],
    );

    final cashProfitRows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM($soldAmountExpression - $costAmountExpression), 0) AS lucro
      FROM ${TableNames.itensVenda} iv
      INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
      WHERE v.status = 'ativa'
        AND v.tipo_venda = 'vista'
        AND v.data_venda >= ?
        AND v.data_venda < ?
    ''',
      [startIso, endIso],
    );

    final fiadoProfitRows = await database.rawQuery(
      '''
      WITH fiado_margens AS (
        SELECT
          f.id AS fiado_id,
          v.valor_final_centavos AS valor_final_centavos,
          COALESCE(SUM($soldAmountExpression - $costAmountExpression), 0) AS margem_total_centavos
        FROM ${TableNames.fiado} f
        INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
        INNER JOIN ${TableNames.itensVenda} iv ON iv.venda_id = v.id
        WHERE v.status = 'ativa'
          AND v.tipo_venda = 'fiado'
        GROUP BY f.id, v.valor_final_centavos
      ),
      pagamentos_periodo AS (
        SELECT
          lanc.fiado_id AS fiado_id,
          COALESCE(SUM(lanc.valor_centavos), 0) AS valor_pago_centavos
        FROM ${TableNames.fiadoLancamentos} lanc
        WHERE lanc.tipo_lancamento = 'pagamento'
          AND lanc.data_lancamento >= ?
          AND lanc.data_lancamento < ?
        GROUP BY lanc.fiado_id
      )
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN margem.valor_final_centavos <= 0 THEN 0
              ELSE CAST(
                ROUND(
                  (margem.margem_total_centavos * pagamentos.valor_pago_centavos) /
                  CAST(margem.valor_final_centavos AS REAL),
                  0
                ) AS INTEGER
              )
            END
          ),
          0
        ) AS lucro
      FROM fiado_margens margem
      INNER JOIN pagamentos_periodo pagamentos
        ON pagamentos.fiado_id = margem.fiado_id
    ''',
      [startIso, endIso],
    );

    final pendingFiadoRows = await database.rawQuery('''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_aberto_centavos), 0) AS total_aberto
      FROM ${TableNames.fiado}
      WHERE status IN ('pendente', 'parcial')
    ''');

    final cancelledRows = await database.rawQuery(
      '''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_final_centavos), 0) AS total
      FROM ${TableNames.vendas}
      WHERE status = 'cancelada'
        AND cancelada_em IS NOT NULL
        AND cancelada_em >= ?
        AND cancelada_em < ?
    ''',
      [startIso, endIso],
    );

    final purchaseRows = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(valor_final_centavos), 0) AS total_comprado,
        COALESCE(SUM(valor_pendente_centavos), 0) AS total_pendente
      FROM ${TableNames.compras}
      WHERE status != 'cancelada'
        AND data_compra >= ?
        AND data_compra < ?
    ''',
      [startIso, endIso],
    );

    final purchasePaymentRows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(valor_centavos), 0) AS total_pago
      FROM ${TableNames.compraPagamentos}
      WHERE data_hora >= ?
        AND data_hora < ?
    ''',
      [startIso, endIso],
    );

    final receivedRows = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN tipo_movimento = 'venda' THEN valor_centavos ELSE 0 END), 0) AS vendas_recebidas,
        COALESCE(SUM(CASE WHEN tipo_movimento = 'recebimento_fiado' THEN valor_centavos ELSE 0 END), 0) AS fiado_recebido,
        COALESCE(SUM(valor_centavos), 0) AS total_recebido
      FROM ${TableNames.caixaMovimentos}
      WHERE tipo_movimento IN ('venda', 'recebimento_fiado', 'cancelamento')
        AND criado_em >= ?
        AND criado_em < ?
    ''',
      [startIso, endIso],
    );

    final creditRows = await database.rawQuery(
      '''
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN type IN (
                '${CustomerCreditTransactionType.manualCredit}',
                '${CustomerCreditTransactionType.overpaymentCredit}',
                '${CustomerCreditTransactionType.saleReturnCredit}',
                '${CustomerCreditTransactionType.saleCancelCredit}',
                '${CustomerCreditTransactionType.changeLeftAsCredit}'
              ) AND amount > 0 THEN amount
              ELSE 0
            END
          ),
          0
        ) AS total_gerado,
        COALESCE(
          SUM(
            CASE
              WHEN type = '${CustomerCreditTransactionType.creditUsedInSale}'
              THEN ABS(amount)
              ELSE 0
            END
          ),
          0
        ) AS total_utilizado
      FROM ${TableNames.customerCreditTransactions}
      WHERE created_at >= ?
        AND created_at < ?
        AND is_reversed = 0
    ''',
      [startIso, endIso],
    );

    final outstandingCreditRows = await database.rawQuery('''
      SELECT COALESCE(SUM(credit_balance), 0) AS total_credito
      FROM ${TableNames.clientes}
      WHERE deletado_em IS NULL
    ''');

    final topCreditCustomerRows = await database.rawQuery('''
      SELECT
        id,
        nome,
        credit_balance
      FROM ${TableNames.clientes}
      WHERE deletado_em IS NULL
        AND credit_balance > 0
      ORDER BY credit_balance DESC, nome COLLATE NOCASE ASC
      LIMIT 5
    ''');

    final paymentRows = await database.rawQuery(
      '''
      SELECT
        mov.tipo_movimento,
        mov.valor_centavos,
        mov.descricao,
        sale.forma_pagamento AS sale_payment_method
      FROM ${TableNames.caixaMovimentos} mov
      LEFT JOIN ${TableNames.vendas} sale
        ON mov.referencia_tipo = 'venda'
        AND sale.id = mov.referencia_id
      WHERE mov.tipo_movimento IN ('venda', 'recebimento_fiado')
        AND mov.valor_centavos > 0
        AND mov.criado_em >= ?
        AND mov.criado_em < ?
      ORDER BY mov.criado_em DESC, mov.id DESC
    ''',
      [startIso, endIso],
    );

    final soldProductRows = await database.rawQuery(
      '''
      SELECT
        iv.produto_id AS product_id,
        COALESCE(iv.nome_produto_snapshot, p.nome, 'Produto') AS product_name,
        COALESCE(iv.unidade_medida_snapshot, p.unidade_medida, 'un') AS unit_measure,
        COALESCE(SUM(iv.quantidade_mil), 0) AS quantity_total_mil,
        COALESCE(
          SUM(
            COALESCE(
              iv.subtotal_centavos,
              CAST(ROUND((iv.quantidade_mil * iv.valor_unitario_centavos) / 1000.0, 0) AS INTEGER)
            )
          ),
          0
        ) AS sold_amount_cents,
        COALESCE(
          SUM(
            COALESCE(
              iv.custo_total_centavos,
              CAST(ROUND((iv.quantidade_mil * iv.custo_unitario_centavos) / 1000.0, 0) AS INTEGER)
            )
          ),
          0
        ) AS total_cost_cents
      FROM ${TableNames.itensVenda} iv
      INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
      LEFT JOIN ${TableNames.produtos} p ON p.id = iv.produto_id
      WHERE v.status = 'ativa'
        AND v.data_venda >= ?
        AND v.data_venda < ?
      GROUP BY
        iv.produto_id,
        COALESCE(iv.nome_produto_snapshot, p.nome, 'Produto'),
        COALESCE(iv.unidade_medida_snapshot, p.unidade_medida, 'un')
      ORDER BY quantity_total_mil DESC, product_name ASC
    ''',
      [startIso, endIso],
    );

    final paymentSummaryMap = <PaymentMethod, _PaymentAccumulator>{};
    for (final row in paymentRows) {
      final paymentMethod =
          PaymentMethodNoteCodec.parse(row['descricao'] as String?) ??
          _paymentMethodFromDb(row['sale_payment_method'] as String?);
      if (paymentMethod == null) {
        continue;
      }

      final current = paymentSummaryMap.putIfAbsent(
        paymentMethod,
        _PaymentAccumulator.new,
      );
      current.receivedCents += _toInt(row['valor_centavos']);
      current.operationsCount += 1;
    }

    final paymentSummaries =
        paymentSummaryMap.entries
            .map(
              (entry) => ReportPaymentSummary(
                paymentMethod: entry.key,
                receivedCents: entry.value.receivedCents,
                operationsCount: entry.value.operationsCount,
              ),
            )
            .toList()
          ..sort((a, b) => b.receivedCents.compareTo(a.receivedCents));

    final soldProducts = soldProductRows
        .map(
          (row) => ReportSoldProductSummary(
            productId: row['product_id'] as int?,
            productName: row['product_name'] as String? ?? 'Produto',
            quantityMil: _toInt(row['quantity_total_mil']),
            unitMeasure: row['unit_measure'] as String? ?? 'un',
            soldAmountCents: _toInt(row['sold_amount_cents']),
            totalCostCents: _toInt(row['total_cost_cents']),
          ),
        )
        .toList();

    final topCreditCustomers = topCreditCustomerRows
        .map(
          (row) => ReportCustomerCreditSummary(
            customerId: row['id'] as int,
            customerName: row['nome'] as String? ?? 'Cliente',
            balanceCents: _toInt(row['credit_balance']),
          ),
        )
        .toList(growable: false);

    final costOfGoodsSoldCents = soldProducts.fold<int>(
      0,
      (total, product) => total + product.totalCostCents,
    );

    return ReportSummary(
      period: period,
      range: range,
      totalSalesCents: _toInt(salesRows.first['total']),
      totalReceivedCents: _toInt(receivedRows.first['total_recebido']),
      costOfGoodsSoldCents: costOfGoodsSoldCents,
      realizedProfitCents:
          _toInt(cashProfitRows.first['lucro']) +
          _toInt(fiadoProfitRows.first['lucro']),
      salesCount: _toInt(salesRows.first['quantidade']),
      pendingFiadoCents: _toInt(pendingFiadoRows.first['total_aberto']),
      pendingFiadoCount: _toInt(pendingFiadoRows.first['quantidade']),
      cancelledSalesCount: _toInt(cancelledRows.first['quantidade']),
      cancelledSalesCents: _toInt(cancelledRows.first['total']),
      totalPurchasedCents: _toInt(purchaseRows.first['total_comprado']),
      totalPurchasePaymentsCents: _toInt(
        purchasePaymentRows.first['total_pago'],
      ),
      totalPurchasePendingCents: _toInt(purchaseRows.first['total_pendente']),
      cashSalesReceivedCents: _toInt(receivedRows.first['vendas_recebidas']),
      fiadoReceiptsCents: _toInt(receivedRows.first['fiado_recebido']),
      totalCreditGeneratedCents: _toInt(creditRows.first['total_gerado']),
      totalCreditUsedCents: _toInt(creditRows.first['total_utilizado']),
      totalOutstandingCreditCents: _toInt(
        outstandingCreditRows.first['total_credito'],
      ),
      topCreditCustomers: topCreditCustomers,
      paymentSummaries: paymentSummaries,
      soldProducts: soldProducts,
    );
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  PaymentMethod? _paymentMethodFromDb(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return PaymentMethodX.fromDb(value);
  }
}

class _PaymentAccumulator {
  int receivedCents = 0;
  int operationsCount = 0;
}
