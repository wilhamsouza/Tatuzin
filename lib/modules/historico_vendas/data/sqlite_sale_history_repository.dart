import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../vendas/domain/entities/sale_detail.dart';
import '../../vendas/domain/entities/sale_enums.dart';
import '../../vendas/domain/entities/sale_item_detail.dart';
import '../../vendas/domain/entities/sale_record.dart';
import '../domain/repositories/sale_history_repository.dart';

class SqliteSaleHistoryRepository implements SaleHistoryRepository {
  SqliteSaleHistoryRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<SaleDetail> fetchDetail(int saleId) async {
    final database = await _appDatabase.database;
    final saleRows = await database.rawQuery(
      '''
      SELECT
        v.*,
        c.nome AS cliente_nome,
        f.id AS fiado_id,
        f.status AS fiado_status,
        f.valor_aberto_centavos AS fiado_valor_aberto_centavos,
        f.vencimento AS fiado_vencimento
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.clientes} c ON c.id = v.cliente_id
      LEFT JOIN ${TableNames.fiado} f ON f.venda_id = v.id
      WHERE v.id = ?
      LIMIT 1
    ''',
      [saleId],
    );

    if (saleRows.isEmpty) {
      throw StateError('Venda nao encontrada para detalhamento.');
    }

    final itemRows = await database.query(
      TableNames.itensVenda,
      where: 'venda_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );

    return SaleDetail(
      sale: _mapSaleRecord(saleRows.first),
      items: itemRows.map(_mapItemDetail).toList(),
    );
  }

  @override
  Future<List<SaleRecord>> search({
    String query = '',
    SaleStatus? status,
    SaleType? type,
    DateTime? from,
    DateTime? to,
  }) async {
    final database = await _appDatabase.database;
    final args = <Object?>[];
    final buffer = StringBuffer('''
      SELECT DISTINCT
        v.*,
        c.nome AS cliente_nome,
        f.id AS fiado_id,
        f.status AS fiado_status,
        f.valor_aberto_centavos AS fiado_valor_aberto_centavos,
        f.vencimento AS fiado_vencimento
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.clientes} c ON c.id = v.cliente_id
      LEFT JOIN ${TableNames.fiado} f ON f.venda_id = v.id
      LEFT JOIN ${TableNames.itensVenda} iv ON iv.venda_id = v.id
      WHERE 1 = 1
    ''');

    if (status != null) {
      buffer.write(' AND v.status = ?');
      args.add(status.dbValue);
    }

    if (type != null) {
      buffer.write(' AND v.tipo_venda = ?');
      args.add(type.dbValue);
    }

    if (from != null) {
      buffer.write(' AND v.data_venda >= ?');
      args.add(from.toIso8601String());
    }

    if (to != null) {
      buffer.write(' AND v.data_venda <= ?');
      args.add(to.toIso8601String());
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      buffer.write('''
         AND (
           c.nome LIKE ? COLLATE NOCASE
           OR iv.nome_produto_snapshot LIKE ? COLLATE NOCASE
           OR v.numero_cupom LIKE ? COLLATE NOCASE
         )
      ''');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
      args.add('%$trimmedQuery%');
    }

    buffer.write(' ORDER BY v.data_venda DESC, v.id DESC');

    final rows = await database.rawQuery(buffer.toString(), args);
    return rows.map(_mapSaleRecord).toList();
  }

  SaleRecord _mapSaleRecord(Map<String, Object?> row) {
    return SaleRecord(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      receiptNumber: row['numero_cupom'] as String,
      saleType: SaleTypeX.fromDb(row['tipo_venda'] as String),
      paymentMethod: PaymentMethodX.fromDb(row['forma_pagamento'] as String),
      status: SaleStatusX.fromDb(row['status'] as String),
      totalCents: row['valor_total_centavos'] as int,
      finalCents: row['valor_final_centavos'] as int,
      discountCents: row['desconto_centavos'] as int? ?? 0,
      surchargeCents: row['acrescimo_centavos'] as int? ?? 0,
      soldAt: DateTime.parse(row['data_venda'] as String),
      clientId: row['cliente_id'] as int?,
      clientName: row['cliente_nome'] as String?,
      notes: row['observacao'] as String?,
      cancelledAt: row['cancelada_em'] == null
          ? null
          : DateTime.parse(row['cancelada_em'] as String),
      fiadoId: row['fiado_id'] as int?,
      fiadoStatus: row['fiado_status'] as String?,
      fiadoOpenCents: row['fiado_valor_aberto_centavos'] as int?,
      fiadoDueDate: row['fiado_vencimento'] == null
          ? null
          : DateTime.parse(row['fiado_vencimento'] as String),
    );
  }

  SaleItemDetail _mapItemDetail(Map<String, Object?> row) {
    return SaleItemDetail(
      id: row['id'] as int,
      productId: row['produto_id'] as int,
      productName: row['nome_produto_snapshot'] as String,
      quantityMil: row['quantidade_mil'] as int,
      unitPriceCents: row['valor_unitario_centavos'] as int,
      subtotalCents: row['subtotal_centavos'] as int,
      costUnitCents: row['custo_unitario_centavos'] as int,
      costTotalCents: row['custo_total_centavos'] as int,
      unitMeasure: row['unidade_medida_snapshot'] as String,
      productType: row['tipo_produto_snapshot'] as String,
    );
  }
}
