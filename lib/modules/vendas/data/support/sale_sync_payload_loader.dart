import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/sync/sync_feature_keys.dart';
import '../../../../app/core/sync/sync_status.dart';
import '../../domain/entities/sale_enums.dart';
import '../models/sale_cancellation_sync_payload.dart';
import '../models/sale_sync_payload.dart';

class SaleSyncPayloadLoader {
  const SaleSyncPayloadLoader._();

  static Future<SaleSyncPayload?> loadSale(
    DatabaseExecutor db, {
    required int saleId,
    required String featureKey,
  }) async {
    final saleRows = await db.rawQuery(
      '''
      SELECT
        v.id,
        v.uuid,
        v.cliente_id,
        v.tipo_venda,
        v.forma_pagamento,
        v.status,
        v.valor_final_centavos,
        v.numero_cupom,
        v.data_venda,
        v.observacao,
        COALESCE(v.cancelada_em, v.data_venda) AS venda_atualizada_em,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_synced_at AS sync_last_synced_at,
        client_sync.remote_id AS cliente_remote_id
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = v.id
      LEFT JOIN ${TableNames.syncRegistros} client_sync
        ON client_sync.feature_key = '${SyncFeatureKeys.customers}'
        AND client_sync.local_id = v.cliente_id
      WHERE v.id = ?
      LIMIT 1
    ''',
      [saleId],
    );

    if (saleRows.isEmpty) {
      return null;
    }

    final itemRows = await db.rawQuery(
      '''
      SELECT
        iv.id,
        iv.produto_id,
        iv.nome_produto_snapshot,
        iv.quantidade_mil,
        iv.valor_unitario_centavos,
        iv.subtotal_centavos,
        iv.custo_unitario_centavos,
        iv.custo_total_centavos,
        iv.unidade_medida_snapshot,
        iv.tipo_produto_snapshot,
        product_sync.remote_id AS produto_remote_id
      FROM ${TableNames.itensVenda} iv
      LEFT JOIN ${TableNames.syncRegistros} product_sync
        ON product_sync.feature_key = '${SyncFeatureKeys.products}'
        AND product_sync.local_id = iv.produto_id
      WHERE iv.venda_id = ?
      ORDER BY iv.id ASC
    ''',
      [saleId],
    );

    final items = itemRows
        .map(
          (row) => SaleSyncItemPayload(
            itemId: row['id'] as int,
            productLocalId: row['produto_id'] as int?,
            productRemoteId: row['produto_remote_id'] as String?,
            productNameSnapshot: row['nome_produto_snapshot'] as String,
            quantityMil: row['quantidade_mil'] as int,
            unitPriceCents: row['valor_unitario_centavos'] as int,
            totalPriceCents: row['subtotal_centavos'] as int,
            unitCostCents: row['custo_unitario_centavos'] as int,
            totalCostCents: row['custo_total_centavos'] as int,
            unitMeasure: row['unidade_medida_snapshot'] as String,
            productType: row['tipo_produto_snapshot'] as String,
          ),
        )
        .toList();

    final totalCostCents = items.fold<int>(
      0,
      (sum, item) => sum + item.totalCostCents,
    );
    final saleRow = saleRows.first;

    return SaleSyncPayload(
      saleId: saleRow['id'] as int,
      saleUuid: saleRow['uuid'] as String,
      receiptNumber: saleRow['numero_cupom'] as String,
      saleType: SaleTypeX.fromDb(saleRow['tipo_venda'] as String),
      paymentMethod: PaymentMethodX.fromDb(
        saleRow['forma_pagamento'] as String,
      ),
      status: SaleStatusX.fromDb(saleRow['status'] as String),
      totalAmountCents: saleRow['valor_final_centavos'] as int,
      totalCostCents: totalCostCents,
      soldAt: DateTime.parse(saleRow['data_venda'] as String),
      updatedAt: DateTime.parse(saleRow['venda_atualizada_em'] as String),
      clientLocalId: saleRow['cliente_id'] as int?,
      clientRemoteId: saleRow['cliente_remote_id'] as String?,
      notes: saleRow['observacao'] as String?,
      remoteId: saleRow['sync_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(saleRow['sync_status'] as String?),
      lastSyncedAt: saleRow['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(saleRow['sync_last_synced_at'] as String),
      items: items,
    );
  }

  static Future<SaleCancellationSyncPayload?> loadCancellation(
    DatabaseExecutor db, {
    required int saleId,
    required String featureKey,
    required String cancellationFeatureKey,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        v.id,
        v.uuid,
        v.valor_final_centavos,
        v.tipo_venda,
        v.cancelada_em,
        v.observacao,
        sales_sync.remote_id AS sale_remote_id,
        cancel_sync.remote_id AS cancel_remote_id,
        cancel_sync.sync_status AS cancel_sync_status,
        cancel_sync.last_synced_at AS cancel_last_synced_at
      FROM ${TableNames.vendas} v
      LEFT JOIN ${TableNames.syncRegistros} sales_sync
        ON sales_sync.feature_key = '$featureKey'
        AND sales_sync.local_id = v.id
      LEFT JOIN ${TableNames.syncRegistros} cancel_sync
        ON cancel_sync.feature_key = '$cancellationFeatureKey'
        AND cancel_sync.local_id = v.id
      WHERE v.id = ?
      LIMIT 1
    ''',
      [saleId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final canceledAtIso = row['cancelada_em'] as String?;
    if (canceledAtIso == null) {
      return null;
    }

    return SaleCancellationSyncPayload(
      saleId: row['id'] as int,
      saleUuid: row['uuid'] as String,
      saleRemoteId: row['sale_remote_id'] as String?,
      remoteId: row['cancel_remote_id'] as String?,
      amountCents: row['valor_final_centavos'] as int? ?? 0,
      paymentType: row['tipo_venda'] as String? ?? 'vista',
      canceledAt: DateTime.parse(canceledAtIso),
      updatedAt: DateTime.parse(canceledAtIso),
      notes: row['observacao'] as String?,
      syncStatus: syncStatusFromStorage(row['cancel_sync_status'] as String?),
      lastSyncedAt: row['cancel_last_synced_at'] == null
          ? null
          : DateTime.parse(row['cancel_last_synced_at'] as String),
    );
  }
}
